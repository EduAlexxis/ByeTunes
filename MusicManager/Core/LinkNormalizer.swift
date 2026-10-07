import Foundation

enum LinkSource: String {
    case appleMusic
    case spotify
    case unknown
}

enum LinkKind: String {
    case track
    case album
    case playlist
    case artist
    case unknown
}

struct NormalizedLink {
    let original: URL
    let source: LinkSource
    let kind: LinkKind
    let id: String?
    let normalizedURL: URL
}

enum LinkNormalizer {
    static func normalize(_ input: String) -> NormalizedLink? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return normalize(url)
    }

    static func normalize(_ url: URL) -> NormalizedLink? {
        let host = (url.host ?? "").lowercased()
        if host.contains("spotify.com") { return normalizeSpotify(url) }
        if host.contains("music.apple.com") { return normalizeAppleMusic(url) }
        return nil
    }

    private static func normalizeAppleMusic(_ url: URL) -> NormalizedLink? {
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else { return nil }
        let type = comps.dropFirst().first?.lowercased() ?? ""
        let kind = appleKind(from: type)
        let id = extractAppleMusicID(from: url, fallbackPathComponents: comps)
        return NormalizedLink(
            original: url,
            source: .appleMusic,
            kind: kind,
            id: id,
            normalizedURL: url
        )
    }

    private static func appleKind(from type: String) -> LinkKind {
        switch type {
        case "album": return .album
        case "song": return .track
        case "playlist": return .playlist
        case "artist": return .artist
        default: return .unknown
        }
    }

    private static func extractAppleMusicID(from url: URL, fallbackPathComponents: [String]) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let q = items.first(where: { $0.name == "i" })?.value, !q.isEmpty {
            return q
        }
        if let last = fallbackPathComponents.last,
           last.range(of: "^\\d+$", options: .regularExpression) != nil {
            return last
        }
        return nil
    }

    private static func normalizeSpotify(_ url: URL) -> NormalizedLink? {
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else { return nil }
        let type = comps[0].lowercased()
        let id = comps[1]
        let kind = spotifyKind(from: type)
        guard kind != .unknown, !id.isEmpty else { return nil }
        var out = URLComponents()
        out.scheme = "https"
        out.host = "open.spotify.com"
        out.path = "/\(type)/\(id)"
        let normalized = out.url ?? url
        return NormalizedLink(
            original: url,
            source: .spotify,
            kind: kind,
            id: id,
            normalizedURL: normalized
        )
    }

    private static func spotifyKind(from type: String) -> LinkKind {
        switch type {
        case "track": return .track
        case "album": return .album
        case "playlist": return .playlist
        case "artist": return .artist
        default: return .unknown
        }
    }
}
