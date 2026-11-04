import SwiftUI

struct SmartPlaylistEditorView: View {
    let songs: [DeviceManager.ExportableSongInfo]
    let onCreate: (String, SmartCriteriaGroup, SmartPlaylistLimit, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Field: String, CaseIterable, Identifiable {
        case artist = "Artist"
        case genre = "Genre"
        case title = "Title"
        case album = "Album"
        case albumArtist = "Album Artist"
        case year = "Year"
        case playCount = "Plays"
        case favorite = "Favorite"
        var id: String { rawValue }

        var isText: Bool {
            switch self {
            case .artist, .genre, .title, .album, .albumArtist: return true
            default: return false
            }
        }

        var isNumber: Bool { self == .year || self == .playCount }

        var icon: String {
            switch self {
            case .artist: return "person.fill"
            case .genre: return "music.note"
            case .title: return "textformat"
            case .album: return "square.stack"
            case .albumArtist: return "person.2.fill"
            case .year: return "calendar"
            case .playCount: return "play.circle"
            case .favorite: return "heart.fill"
            }
        }

        var criteriaField: UInt32 {
            switch self {
            case .artist: return SmartCriteriaField.artist
            case .genre: return SmartCriteriaField.genre
            case .title: return SmartCriteriaField.name
            case .album: return SmartCriteriaField.album
            case .albumArtist: return SmartCriteriaField.albumArtist
            case .year: return SmartCriteriaField.year
            case .playCount: return SmartCriteriaField.playCount
            case .favorite: return SmartCriteriaField.likedState
            }
        }
    }

    private enum TextOp: String, CaseIterable, Identifiable {
        case contains = "contains"
        case isExactly = "is"
        case isNot = "is not"
        case notContains = "does not contain"
        case startsWith = "starts with"
        case endsWith = "ends with"
        var id: String { rawValue }

        var action: UInt32 {
            switch self {
            case .contains: return SmartCriteriaAction.textContains
            case .isExactly: return SmartCriteriaAction.textIs
            case .isNot: return SmartCriteriaAction.textIsNot
            case .notContains: return SmartCriteriaAction.textNotContains
            case .startsWith: return SmartCriteriaAction.textStartsWith
            case .endsWith: return SmartCriteriaAction.textEndsWith
            }
        }
    }

    private enum NumberOp: String, CaseIterable, Identifiable {
        case isExactly = "is"
        case greater = "is greater than"
        case less = "is less than"
        case between = "is between"
        var id: String { rawValue }

        var action: UInt32 {
            switch self {
            case .isExactly: return SmartCriteriaAction.numberIs
            case .greater: return SmartCriteriaAction.numberGreater
            case .less: return SmartCriteriaAction.numberLess
            case .between: return SmartCriteriaAction.numberInRange
            }
        }
    }

    private struct EditableRule: Identifiable {
        let id = UUID()
        var depth = 0
        var isGroup = false
        var groupMatchesAll = true
        var field: Field = .artist
        var textOp: TextOp = .contains
        var numberOp: NumberOp = .isExactly
        var text = ""
        var number = ""
        var number2 = ""

        var criteriaRule: SmartCriteriaRule? {
            if field.isText {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                return .text(field: field.criteriaField, action: textOp.action, value: value)
            }
            if field.isNumber {
                guard let first = Int64(number.trimmingCharacters(in: .whitespaces)) else { return nil }
                if numberOp == .between {
                    guard let second = Int64(number2.trimmingCharacters(in: .whitespaces)) else { return nil }
                    return .number(field: field.criteriaField, action: numberOp.action, from: first, to: second)
                }
                return .number(field: field.criteriaField, action: numberOp.action, from: first, to: first)
            }
            return .number(field: field.criteriaField, action: SmartCriteriaAction.numberIs, from: 2)
        }
    }

    private static let maxDepth = 2

    @State private var rules: [EditableRule] = [EditableRule()]
    @State private var matchAll = true
    @State private var limitEnabled = false
    @State private var limitText = "25"
    @State private var showingNaming = false

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
    }

    private var strongTextColor: Color { colorScheme == .dark ? .white : .black }
    private var mutedTextColor: Color { colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4) }
    private var controlFillColor: Color { colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.92) }
    private var accentPink: Color { Color(red: 1.0, green: 0.27, blue: 0.42) }
    private var hairlineColor: Color { colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85) }

    private var limit: SmartPlaylistLimit {
        var result = SmartPlaylistLimit()
        result.isLimited = limitEnabled
        result.value = min(max(Int(limitText.trimmingCharacters(in: .whitespaces)) ?? 25, 1), 9999)
        return result
    }

    private func buildGroup(_ index: inout Int, depth: Int, matchesAll: Bool) -> SmartCriteriaGroup {
        var items: [SmartCriteriaItem] = []
        while index < rules.count, rules[index].depth >= depth {
            let row = rules[index]
            if row.depth > depth { index += 1; continue }
            index += 1
            if row.isGroup {
                let sub = buildGroup(&index, depth: depth + 1, matchesAll: row.groupMatchesAll)
                if !sub.items.isEmpty { items.append(.group(sub)) }
            } else if let rule = row.criteriaRule {
                items.append(.rule(rule))
            }
        }
        return SmartCriteriaGroup(matchAll: matchesAll, items: items)
    }

    private var criteria: SmartCriteriaGroup? {
        var index = 0
        let userRules = buildGroup(&index, depth: 0, matchesAll: matchAll)
        guard !userRules.items.isEmpty else { return nil }
        let mediaKinds = SmartCriteriaGroup(matchAll: false, items: [
            .rule(.number(field: SmartCriteriaField.mediaKind, from: 1)),
            .rule(.number(field: SmartCriteriaField.mediaKind, from: 32))
        ])
        return SmartCriteriaGroup(matchAll: true, items: [.group(mediaKinds), .group(userRules)])
    }

    private var preview: (count: Int, isComplete: Bool)? {
        guard let criteria else { return nil }
        let result = criteria.matchingSongs(in: songs)
        return (result.songs.count, result.isComplete)
    }

    private var suggestedName: String {
        guard let first = rules.first(where: { !$0.isGroup && $0.criteriaRule != nil }) else { return "Smart Playlist" }
        if first.field.isText { return first.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if first.field == .favorite { return "Favorites" }
        return "\(first.field.rawValue) \(first.number)"
    }

    private func suggestions(for rule: EditableRule) -> [String] {
        let query = rule.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var pool = Set<String>()
        for song in songs {
            switch rule.field {
            case .artist: DeviceLibraryBrowserView.splitArtistNames(song.artist).forEach { pool.insert($0) }
            case .genre: pool.insert(song.genre.trimmingCharacters(in: .whitespacesAndNewlines))
            case .album: pool.insert(song.album)
            case .albumArtist: pool.insert(song.albumArtist)
            case .title: pool.insert(song.title)
            default: break
            }
        }
        return pool
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(query) && $0.caseInsensitiveCompare(query) != .orderedSame }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(3)
            .map { $0 }
    }

    private func subtreeEnd(from index: Int) -> Int {
        let depth = rules[index].depth
        var end = index + 1
        if rules[index].isGroup {
            while end < rules.count, rules[end].depth > depth { end += 1 }
        }
        return end
    }

    private func insertRule(after index: Int) {
        let end = subtreeEnd(from: index)
        var rule = EditableRule()
        rule.depth = rules[index].depth
        rules.insert(rule, at: end)
    }

    private func insertGroup(after index: Int) {
        let end = subtreeEnd(from: index)
        var header = EditableRule()
        header.depth = rules[index].depth
        header.isGroup = true
        var child = EditableRule()
        child.depth = header.depth + 1
        rules.insert(contentsOf: [header, child], at: end)
    }

    private func removeRow(at index: Int) {
        guard rules.count > 1 else { return }
        let end = subtreeEnd(from: index)
        rules.removeSubrange(index..<end)
        if rules.isEmpty { rules = [EditableRule()] }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        matchHeader
                        rulesPanel
                        limitPanel
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Smart Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(accentPink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") { showingNaming = true }
                        .foregroundStyle(accentPink)
                        .disabled(criteria == nil)
                }
            }
            .sheet(isPresented: $showingNaming) {
                PlaylistNamingView(title: "Name Smart Playlist", icon: "wand.and.stars", iconTint: accentPink, initialName: suggestedName) { name, coverImageData in
                    guard let criteria, !name.isEmpty else { return }
                    onCreate(name, criteria, limit, coverImageData)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var matchHeader: some View {
        HStack(spacing: 10) {
            Text("Match")
                .font(.body)
                .foregroundStyle(strongTextColor)
            Menu {
                Button("all") { matchAll = true }
                Button("any") { matchAll = false }
            } label: {
                greyMenu(matchAll ? "all" : "any", fill: false)
                    .frame(width: 84)
            }
            Text("of the following rules:")
                .font(.body)
                .foregroundStyle(strongTextColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var rulesPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(hairlineColor)
                }
                if row.isGroup {
                    groupRow(index)
                } else {
                    ruleRow(index)
                }
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func indentBar(_ depth: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(hairlineColor)
                    .frame(width: 2)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
            }
        }
    }

    private func rowButtons(_ index: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { removeRow(at: index) }
            } label: {
                squareIcon("minus")
            }
            .buttonStyle(.plain)
            .disabled(rules.count <= 1)
            .opacity(rules.count <= 1 ? 0.4 : 1)

            Menu {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { insertRule(after: index) }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                if rules[index].depth < Self.maxDepth {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { insertGroup(after: index) }
                    } label: {
                        Label("Add Group of Rules", systemImage: "square.stack")
                    }
                }
            } label: {
                squareIcon("plus")
            }
        }
    }

    private func squareIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(strongTextColor)
            .frame(width: 32, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(controlFillColor))
    }

    private func greyMenu(_ text: String, fill: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(strongTextColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(mutedTextColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: fill ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: 8).fill(controlFillColor))
    }

    private func groupRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            if rules[index].depth > 0 {
                indentBar(rules[index].depth)
            }
            Menu {
                Button("All") { rules[index].groupMatchesAll = true }
                Button("Any") { rules[index].groupMatchesAll = false }
            } label: {
                greyMenu(rules[index].groupMatchesAll ? "All" : "Any", fill: false)
                    .frame(width: 72)
            }
            Text("of the following are true")
                .font(.footnote)
                .foregroundStyle(mutedTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            rowButtons(index)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ruleRow(_ index: Int) -> some View {
        let rule = rules[index]
        return HStack(alignment: .top, spacing: 8) {
            if rule.depth > 0 {
                indentBar(rule.depth)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(Field.allCases) { field in
                            Button(field.rawValue) { rules[index].field = field }
                        }
                    } label: {
                        greyMenu(rule.field.rawValue)
                    }

                    if rule.field.isText {
                        Menu {
                            ForEach(TextOp.allCases) { op in
                                Button(op.rawValue) { rules[index].textOp = op }
                            }
                        } label: {
                            greyMenu(rule.textOp.rawValue)
                        }
                    } else if rule.field.isNumber {
                        Menu {
                            ForEach(NumberOp.allCases) { op in
                                Button(op.rawValue) { rules[index].numberOp = op }
                            }
                        } label: {
                            greyMenu(rule.numberOp.rawValue)
                        }
                    } else {
                        greyMenu("is loved")
                            .opacity(0.6)
                    }
                }

                HStack(spacing: 8) {
                    valueEditor(index)
                    Spacer(minLength: 0)
                    rowButtons(index)
                }

                ForEach(suggestions(for: rule), id: \.self) { suggestion in
                    Button {
                        rules[index].text = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.footnote)
                            .foregroundStyle(mutedTextColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func valueEditor(_ index: Int) -> some View {
        let rule = rules[index]
        if rule.field.isText {
            valueBox(TextField("Value", text: $rules[index].text).autocorrectionDisabled())
        } else if rule.field.isNumber {
            HStack(spacing: 8) {
                valueBox(TextField(rule.field == .year ? "2015" : "0", text: $rules[index].number).keyboardType(.numberPad))
                if rule.numberOp == .between {
                    Text("and")
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                    valueBox(TextField(rule.field == .year ? "2020" : "0", text: $rules[index].number2).keyboardType(.numberPad))
                }
            }
        }
    }

    private func valueBox<Content: View>(_ content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(strongTextColor)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(panelBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hairlineColor, lineWidth: 1))
            )
    }

    private var limitPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $limitEnabled.animation(.easeOut(duration: 0.2))) {
                Text("Limit to")
                    .font(.body)
                    .foregroundStyle(strongTextColor)
            }
            .tint(accentPink)

            if limitEnabled {
                HStack(spacing: 8) {
                    TextField("25", text: $limitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .foregroundStyle(strongTextColor)
                        .frame(width: 64, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(panelBackground)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(hairlineColor, lineWidth: 1))
                        )
                    greyMenu("items", fill: false)
                        .frame(width: 96)
                        .opacity(0.6)
                    Text("selected by random")
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview {
                let shown = limitEnabled ? min(preview.count, limit.value) : preview.count
                Text(preview.isComplete ? "\(shown) song\(shown == 1 ? "" : "s") match." : "\(shown)+ songs match.")
                    .font(.footnote)
                    .foregroundStyle(mutedTextColor)
                if !preview.isComplete {
                    Text("Plays and favorites are checked by Music, so the final playlist may have more songs.")
                        .font(.footnote)
                        .foregroundStyle(mutedTextColor)
                }
            }
            Text("Music keeps the playlist up to date as songs are added.")
                .font(.footnote)
                .foregroundStyle(mutedTextColor)
        }
        .padding(.horizontal, 4)
    }
}
