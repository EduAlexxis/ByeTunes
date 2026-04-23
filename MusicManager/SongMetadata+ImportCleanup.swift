import Foundation

extension SongMetadata {
    static func cleanImportedMetadata(_ song: SongMetadata) -> SongMetadata {
        var cleaned = song

        let rawFilename = song.localURL.deletingPathExtension().lastPathComponent
        let normalizedFilename = normalizedImportedFilename(rawFilename)

        let parsed = parseArtistAndTitle(from: normalizedFilename)

        cleaned.title = cleanedTitle(
            current: cleaned.title,
            fallbackParsedTitle: parsed.title,
            fallbackFilename: normalizedFilename
        )

        cleaned.artist = cleanedArtist(
            current: cleaned.artist,
            fallbackParsedArtist: parsed.artist
        )

        cleaned.album = cleanedAlbum(cleaned.album)
        cleaned.genre = cleanedGenre(cleaned.genre)

        if let track = parsed.trackNumber, cleaned.trackNumber == nil {
            cleaned.trackNumber = track
        }

        return cleaned
    }

    private static func normalizedImportedFilename(_ value: String) -> String {
        var cleaned = value

        cleaned = cleaned.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^\d{5,}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s*-\s*"#,
            with: " - ",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingGarbage(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^\d{5,}\s+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseArtistAndTitle(from filename: String) -> (artist: String?, title: String?, trackNumber: Int?) {
        let parts = filename
            .components(separatedBy: " - ")
            .map { stripLeadingGarbage($0) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return (nil, nil, nil)
        }

        if parts.count >= 3, let track = Int(parts[0]), parts[0].count <= 3 {
            let artist = stripLeadingGarbage(parts[1])
            let title = stripLeadingGarbage(parts[2...].joined(separator: " - "))
            return (artist.isEmpty ? nil : artist, title.isEmpty ? nil : title, track)
        }

        if parts.count == 2 {
            let p1 = stripLeadingGarbage(parts[0])
            let p2 = stripLeadingGarbage(parts[1])

            if let track = Int(p1), p1.count <= 3 {
                return (nil, p2.isEmpty ? nil : p2, track)
            }

            let p1Lower = p1.lowercased()
            let p2Lower = p2.lowercased()

            let p1LooksLikeTitle =
                p1Lower.contains("official") ||
                p1Lower.contains("audio") ||
                p1Lower.contains("video") ||
                p1Lower.contains("lyrics")

            let p2LooksLikeTitle =
                p2Lower.contains("official") ||
                p2Lower.contains("audio") ||
                p2Lower.contains("video") ||
                p2Lower.contains("lyrics")

            let p1LooksLikeArtist =
                p1Lower.contains("feat") || p1Lower.contains("ft.") || p1.contains(",")

            let p2LooksLikeArtist =
                p2Lower.contains("feat") || p2Lower.contains("ft.") || p2.contains(",")

            if p1LooksLikeTitle && !p2LooksLikeTitle {
                return (p2.isEmpty ? nil : p2, p1.isEmpty ? nil : p1, nil)
            }

            if p2LooksLikeArtist && !p1LooksLikeArtist {
                return (p2.isEmpty ? nil : p2, p1.isEmpty ? nil : p1, nil)
            }

            return (p1.isEmpty ? nil : p1, p2.isEmpty ? nil : p2, nil)
        }

        return (nil, filename.isEmpty ? nil : filename, nil)
    }

    private static func cleanedTitle(current: String, fallbackParsedTitle: String?, fallbackFilename: String) -> String {
        let stripped = stripLeadingGarbage(current)
        let lowered = stripped.lowercased()

        let shouldReplace =
            stripped.isEmpty ||
            lowered == "unknown title" ||
            stripped.range(of: #"^[0-9A-Fa-f-]{36}[_\-\s]+"#, options: .regularExpression) != nil ||
            stripped.range(of: #"^\d{5,}\s+\S+"#, options: .regularExpression) != nil

        if shouldReplace {
            if let fallbackParsedTitle, !fallbackParsedTitle.isEmpty {
                return fallbackParsedTitle
            }
            return fallbackFilename
        }

        return stripped
    }

    private static func cleanedArtist(current: String, fallbackParsedArtist: String?) -> String {
        let stripped = stripLeadingGarbage(current)
        let lowered = stripped.lowercased()

        let shouldReplace =
            stripped.isEmpty ||
            lowered == "unknown artist" ||
            stripped.range(of: #"^[0-9A-Fa-f-]{36}[_\-\s]+"#, options: .regularExpression) != nil ||
            stripped.range(of: #"^\d{5,}\s+\S+"#, options: .regularExpression) != nil

        if shouldReplace {
            if let fallbackParsedArtist, !fallbackParsedArtist.isEmpty {
                return fallbackParsedArtist
            }
            return "Unknown Artist"
        }

        return stripped
    }

    private static func cleanedAlbum(_ value: String) -> String {
        let stripped = stripLeadingGarbage(value)
        let lowered = stripped.lowercased()
        if stripped.isEmpty || lowered == "unknown album" {
            return "Unknown Album"
        }
        return stripped
    }

    private static func cleanedGenre(_ value: String) -> String {
        let stripped = stripLeadingGarbage(value)
        let lowered = stripped.lowercased()
        if stripped.isEmpty || lowered == "unknown genre" {
            return "Music"
        }
        return stripped
    }
}
