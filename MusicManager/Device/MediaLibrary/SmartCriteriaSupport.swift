import Foundation

extension SmartPlaylistRule {
    func criteria() -> SmartCriteriaGroup? {
        var rules: [SmartCriteriaItem] = []
        switch kind {
        case .genre:
            rules = values.map { .rule(.text(field: SmartCriteriaField.genre, value: $0)) }
        case .artist:
            rules = values.map { .rule(.text(field: SmartCriteriaField.artist, value: $0)) }
        case .decade:
            rules = values.compactMap { Int64($0) }.map {
                .rule(.number(field: SmartCriteriaField.year, action: SmartCriteriaAction.numberInRange, from: $0, to: $0 + 9))
            }
        case .fileFormat:
            rules = values.map { .rule(.text(field: SmartCriteriaField.kind, value: $0)) }
        case .explicitRating:
            return nil
        }
        guard !rules.isEmpty else { return nil }
        let mediaKinds = SmartCriteriaGroup(matchAll: false, items: [
            .rule(.number(field: SmartCriteriaField.mediaKind, from: 1)),
            .rule(.number(field: SmartCriteriaField.mediaKind, from: 32))
        ])
        let userRules = SmartCriteriaGroup(matchAll: false, items: rules)
        return SmartCriteriaGroup(matchAll: true, items: [.group(mediaKinds), .group(userRules)])
    }
}

extension SmartCriteriaGroup {
    func summaryLines() -> [String] {
        var lines: [String] = []
        let visible = withoutMusicKindWrapper()
        if visible.items.count == 1, case .rule(let rule) = visible.items[0] {
            return [rule.summary]
        }
        visible.appendSummary(to: &lines, depth: 0)
        return lines
    }

    private var isMusicKindWrapper: Bool {
        guard !matchAll, items.count == 2 else { return false }
        for item in items {
            guard case .rule(let rule) = item, rule.field == SmartCriteriaField.mediaKind, !rule.isText else { return false }
        }
        return true
    }

    private func withoutMusicKindWrapper() -> SmartCriteriaGroup {
        guard matchAll else { return self }
        let remaining = items.filter { item in
            if case .group(let group) = item, group.isMusicKindWrapper { return false }
            return true
        }
        guard remaining.count == 1, case .group(let only) = remaining[0] else {
            var copy = self
            copy.items = remaining
            return copy
        }
        return only
    }

    private func appendSummary(to lines: inout [String], depth: Int) {
        let indent = String(repeating: "    ", count: depth)
        lines.append("\(indent)\(matchAll ? "Match all of:" : "Match any of:")")
        for item in items {
            switch item {
            case .rule(let rule):
                lines.append("\(indent)    • \(rule.summary)")
            case .group(let group):
                group.appendSummary(to: &lines, depth: depth + 1)
            }
        }
    }

    func evaluate(_ song: DeviceManager.ExportableSongInfo) -> Bool? {
        var sawUnknown = false
        var sawTrue = false
        var sawFalse = false
        for item in items {
            let outcome: Bool?
            switch item {
            case .rule(let rule): outcome = rule.evaluate(song)
            case .group(let group): outcome = group.evaluate(song)
            }
            if let outcome {
                if outcome { sawTrue = true } else { sawFalse = true }
            } else {
                sawUnknown = true
            }
        }
        if items.isEmpty { return true }
        if matchAll {
            if sawFalse { return false }
            return sawUnknown ? nil : true
        }
        if sawTrue { return true }
        return sawUnknown ? nil : false
    }

    func matchingSongs(in songs: [DeviceManager.ExportableSongInfo]) -> (songs: [DeviceManager.ExportableSongInfo], isComplete: Bool) {
        var matches: [DeviceManager.ExportableSongInfo] = []
        var complete = true
        for song in songs {
            switch evaluate(song) {
            case .some(true): matches.append(song)
            case .some(false): break
            case .none: complete = false
            }
        }
        return (matches, complete)
    }
}

extension SmartCriteriaRule {
    static let fieldNames: [UInt32: String] = [
        SmartCriteriaField.name: "Title",
        SmartCriteriaField.album: "Album",
        SmartCriteriaField.artist: "Artist",
        SmartCriteriaField.year: "Year",
        SmartCriteriaField.genre: "Genre",
        SmartCriteriaField.kind: "Kind",
        SmartCriteriaField.playCount: "Plays",
        SmartCriteriaField.rating: "Rating",
        SmartCriteriaField.mediaKind: "Media Kind",
        SmartCriteriaField.albumArtist: "Album Artist",
        SmartCriteriaField.likedState: "Favorite"
    ]

    var fieldName: String {
        Self.fieldNames[field] ?? "Field 0x\(String(field, radix: 16))"
    }

    private var isNegated: Bool {
        let high = action >> 24
        return high == 2 || high == 3
    }

    private var baseAction: UInt32 { action & 0x00ffffff }

    var summary: String {
        let not = isNegated ? "not " : ""
        if let text {
            let verb: String
            switch baseAction {
            case 1: verb = "is"
            case 2: verb = "contains"
            case 4: verb = "starts with"
            case 8: verb = "ends with"
            default: verb = "matches"
            }
            return "\(fieldName) \(not)\(verb) \"\(text)\""
        }
        let value = numberDisplay(fromValue)
        switch baseAction {
        case 0x10: return "\(fieldName) \(not)is greater than \(value)"
        case 0x40: return "\(fieldName) \(not)is less than \(value)"
        case 0x100: return "\(fieldName) \(not)is between \(value) and \(numberDisplay(toValue))"
        default:
            if toValue != fromValue { return "\(fieldName) \(not)is between \(value) and \(numberDisplay(toValue))" }
            return "\(fieldName) \(not)is \(value)"
        }
    }

    private func numberDisplay(_ value: Int64) -> String {
        if field == SmartCriteriaField.mediaKind {
            return value == 1 ? "Music" : "Kind \(value)"
        }
        if field == SmartCriteriaField.likedState {
            return value == 2 ? "Loved" : (value == 1 ? "Disliked" : "None")
        }
        return "\(value)"
    }

    func evaluate(_ song: DeviceManager.ExportableSongInfo) -> Bool? {
        let result: Bool?
        if let text {
            let candidate: String?
            switch field {
            case SmartCriteriaField.name: candidate = song.title
            case SmartCriteriaField.album: candidate = song.album
            case SmartCriteriaField.artist: candidate = song.artist
            case SmartCriteriaField.albumArtist: candidate = song.albumArtist
            case SmartCriteriaField.genre: candidate = song.genre
            default: candidate = nil
            }
            guard let candidate else { return nil }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            switch baseAction {
            case 1: result = candidate.compare(text, options: options) == .orderedSame
            case 2: result = candidate.range(of: text, options: options) != nil
            case 4: result = candidate.range(of: text, options: options.union(.anchored)) != nil
            case 8: result = candidate.range(of: text, options: options.union([.anchored, .backwards])) != nil
            default: result = nil
            }
        } else {
            let value: Int64?
            switch field {
            case SmartCriteriaField.year: value = song.year > 0 ? Int64(song.year) : 0
            case SmartCriteriaField.mediaKind: value = 1
            default: value = nil
            }
            guard let value else { return nil }
            switch baseAction {
            case 0x10: result = value > fromValue
            case 0x40: result = value < fromValue
            case 0x100: result = value >= fromValue && value <= toValue
            default: result = value >= fromValue && value <= toValue
            }
        }
        guard let result else { return nil }
        return isNegated ? !result : result
    }
}
