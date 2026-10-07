import Foundation

nonisolated enum AudioTagWriterError: LocalizedError {
    case unsupportedFormat(String)
    case invalidFile
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return ext.isEmpty ? "This file type can't be tagged." : "Saving with metadata isn't supported for .\(ext) files yet."
        case .invalidFile:
            return "The audio file couldn't be read."
        case .writeFailed:
            return "The tagged copy couldn't be written."
        }
    }
}

nonisolated enum AudioTagWriter {
    static func supports(_ url: URL) -> Bool {
        ["flac", "mp3"].contains(url.pathExtension.lowercased())
    }

    static func writeTaggedFile(of song: SongMetadata, to destination: URL) throws {
        let ext = song.localURL.pathExtension.lowercased()
        guard supports(song.localURL) else {
            throw AudioTagWriterError.unsupportedFormat(ext)
        }

        let needsSecurityScope = song.localURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                song.localURL.stopAccessingSecurityScopedResource()
            }
        }

        switch ext {
        case "flac": try writeFLAC(song: song, to: destination)
        default: try writeMP3(song: song, to: destination)
        }
    }

    static func copyKeptSong(_ song: SongMetadata, to destination: URL) throws {
        if UserDefaults.standard.bool(forKey: "tagKeptDownloadedSongs"), supports(song.localURL) {
            do {
                try writeTaggedFile(of: song, to: destination)
                return
            } catch {
                Task { @MainActor in
                    Logger.shared.log("[TagWriter] Tagging kept copy failed, keeping original file: \(error)")
                }
                try? FileManager.default.removeItem(at: destination)
            }
        }
        try FileManager.default.copyItem(at: song.localURL, to: destination)
    }

    private static let managedVorbisKeys: Set<String> = [
        "TITLE", "ARTIST", "ALBUM", "ALBUMTITLE", "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST",
        "GENRE", "DATE", "YEAR", "TRACKNUMBER", "TRACK", "TRACKTOTAL", "TOTALTRACKS",
        "DISCNUMBER", "DISC", "DISCTOTAL", "TOTALDISCS", "LYRICS", "UNSYNCEDLYRICS", "COPYRIGHT", "ISRC"
    ]

    private static func imageMimeType(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return "image/jpeg"
    }

    private static func cleanedGenre(_ song: SongMetadata) -> String? {
        let genre = song.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        if genre.isEmpty || genre == "Music" || genre == "Unknown Genre" { return nil }
        return genre
    }

    private static func lyricsText(_ song: SongMetadata) -> String? {
        guard let lyrics = song.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !lyrics.isEmpty else { return nil }
        return lyrics
    }

    private static func littleEndian32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    private static func bigEndian32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func parseVorbisComment(_ data: Data) -> (vendor: String, comments: [String])? {
        let bytes = [UInt8](data)
        var index = 0

        func readUInt32() -> Int? {
            guard index + 4 <= bytes.count else { return nil }
            let value = Int(bytes[index]) | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 24
            index += 4
            return value
        }

        func readString() -> String? {
            guard let length = readUInt32(), index + length <= bytes.count else { return nil }
            let string = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            index += length
            return string
        }

        guard let vendor = readString(), let count = readUInt32() else { return nil }
        var comments: [String] = []
        for _ in 0..<count {
            guard let comment = readString() else { break }
            comments.append(comment)
        }
        return (vendor, comments)
    }

    private static func flacBlock(type: UInt8, body: Data, isLast: Bool) -> Data? {
        guard body.count < (1 << 24) else { return nil }
        var block = Data()
        block.append(type | (isLast ? 0x80 : 0))
        block.append(UInt8((body.count >> 16) & 0xFF))
        block.append(UInt8((body.count >> 8) & 0xFF))
        block.append(UInt8(body.count & 0xFF))
        block.append(body)
        return block
    }

    private static func writeFLAC(song: SongMetadata, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: song.localURL)
        defer { try? input.close() }

        guard let marker = try input.read(upToCount: 4), marker == Data("fLaC".utf8) else {
            throw AudioTagWriterError.invalidFile
        }

        var keptBlocks: [(type: UInt8, body: Data)] = []
        var existingComments: [String] = []
        var vendor = "ByeTunes"
        var existingPictures: [Data] = []
        var isLast = false

        while !isLast {
            guard let header = try input.read(upToCount: 4), header.count == 4 else {
                throw AudioTagWriterError.invalidFile
            }
            isLast = header[header.startIndex] & 0x80 != 0
            let type = header[header.startIndex] & 0x7F
            let length = Int(header[header.startIndex + 1]) << 16 | Int(header[header.startIndex + 2]) << 8 | Int(header[header.startIndex + 3])
            let body = length == 0 ? Data() : (try input.read(upToCount: length) ?? Data())
            guard body.count == length else { throw AudioTagWriterError.invalidFile }

            switch type {
            case 1:
                break
            case 4:
                if let parsed = parseVorbisComment(body) {
                    vendor = parsed.vendor
                    existingComments = parsed.comments
                }
            case 6:
                existingPictures.append(body)
            default:
                keptBlocks.append((type, body))
            }
        }

        guard keptBlocks.first?.type == 0 else { throw AudioTagWriterError.invalidFile }
        let audioOffset = try input.offset()

        var comments = existingComments.filter { comment in
            guard let separator = comment.firstIndex(of: "=") else { return true }
            return !managedVorbisKeys.contains(comment[..<separator].uppercased())
        }

        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            comments.append("\(key)=\(value)")
        }

        add("TITLE", song.title)
        add("ARTIST", song.artist)
        add("ALBUM", song.album)
        add("ALBUMARTIST", song.albumArtist ?? song.artist)
        add("GENRE", cleanedGenre(song))
        add("DATE", song.year > 0 ? String(song.year) : nil)
        add("TRACKNUMBER", song.trackNumber.map(String.init))
        add("TRACKTOTAL", song.trackCount.flatMap { $0 > 0 ? String($0) : nil })
        add("DISCNUMBER", song.discNumber.map(String.init))
        add("DISCTOTAL", song.discCount.flatMap { $0 > 0 ? String($0) : nil })
        add("LYRICS", lyricsText(song))
        add("COPYRIGHT", song.copyright)
        add("ISRC", song.xid)

        var commentBody = Data()
        let vendorBytes = Data(vendor.utf8)
        commentBody.append(contentsOf: littleEndian32(vendorBytes.count))
        commentBody.append(vendorBytes)
        commentBody.append(contentsOf: littleEndian32(comments.count))
        for comment in comments {
            let bytes = Data(comment.utf8)
            commentBody.append(contentsOf: littleEndian32(bytes.count))
            commentBody.append(bytes)
        }

        var pictureBodies = existingPictures
        if let artwork = song.artworkData, !artwork.isEmpty {
            let mime = Data(imageMimeType(artwork).utf8)
            var picture = Data()
            picture.append(contentsOf: bigEndian32(3))
            picture.append(contentsOf: bigEndian32(mime.count))
            picture.append(mime)
            picture.append(contentsOf: bigEndian32(0))
            picture.append(contentsOf: bigEndian32(0))
            picture.append(contentsOf: bigEndian32(0))
            picture.append(contentsOf: bigEndian32(0))
            picture.append(contentsOf: bigEndian32(0))
            picture.append(contentsOf: bigEndian32(artwork.count))
            picture.append(artwork)
            if picture.count < (1 << 24) {
                pictureBodies = [picture]
            }
        }

        var blocks: [(type: UInt8, body: Data)] = keptBlocks
        blocks.append((4, commentBody))
        for picture in pictureBodies {
            blocks.append((6, picture))
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try output.write(contentsOf: Data("fLaC".utf8))
        for (index, block) in blocks.enumerated() {
            guard let encoded = flacBlock(type: block.type, body: block.body, isLast: index == blocks.count - 1) else {
                throw AudioTagWriterError.writeFailed
            }
            try output.write(contentsOf: encoded)
        }

        try input.seek(toOffset: audioOffset)
        try copyRemaining(from: input, to: output)
    }

    private static func copyRemaining(from input: FileHandle, to output: FileHandle) throws {
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private static func utf16Payload(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for unit in text.utf16 {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        return bytes
    }

    private static func id3Frame(_ identifier: String, body: [UInt8]) -> Data {
        var frame = Data(identifier.utf8)
        frame.append(contentsOf: bigEndian32(body.count))
        frame.append(contentsOf: [0, 0])
        frame.append(contentsOf: body)
        return frame
    }

    private static func id3TextFrame(_ identifier: String, _ text: String?) -> Data? {
        guard let text, !text.isEmpty else { return nil }
        return id3Frame(identifier, body: [1] + utf16Payload(text))
    }

    private static func id3Number(_ number: Int?, total: Int?) -> String? {
        guard let number, number > 0 else { return nil }
        if let total, total > 0 { return "\(number)/\(total)" }
        return String(number)
    }

    private static func writeMP3(song: SongMetadata, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: song.localURL)
        defer { try? input.close() }

        var audioOffset: UInt64 = 0
        if let head = try input.read(upToCount: 10), head.count == 10 {
            let bytes = [UInt8](head)
            if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
                let size = Int(bytes[6] & 0x7F) << 21 | Int(bytes[7] & 0x7F) << 14 | Int(bytes[8] & 0x7F) << 7 | Int(bytes[9] & 0x7F)
                audioOffset = UInt64(10 + size + (bytes[5] & 0x10 != 0 ? 10 : 0))
            }
        } else {
            throw AudioTagWriterError.invalidFile
        }

        var frames = Data()
        let textValues: [(String, String?)] = [
            ("TIT2", song.title),
            ("TPE1", song.artist),
            ("TALB", song.album),
            ("TPE2", song.albumArtist ?? song.artist),
            ("TCON", cleanedGenre(song)),
            ("TYER", song.year > 0 ? String(song.year) : nil),
            ("TRCK", id3Number(song.trackNumber, total: song.trackCount)),
            ("TPOS", id3Number(song.discNumber, total: song.discCount)),
            ("TCOP", song.copyright),
            ("TSRC", song.xid)
        ]
        for (identifier, value) in textValues {
            if let frame = id3TextFrame(identifier, value) {
                frames.append(frame)
            }
        }

        if let lyrics = lyricsText(song) {
            var body: [UInt8] = [1]
            body.append(contentsOf: Array("eng".utf8))
            body.append(contentsOf: [0xFF, 0xFE, 0, 0])
            body.append(contentsOf: utf16Payload(lyrics))
            frames.append(id3Frame("USLT", body: body))
        }

        if let artwork = song.artworkData, !artwork.isEmpty {
            var body: [UInt8] = [0]
            body.append(contentsOf: Array(imageMimeType(artwork).utf8))
            body.append(contentsOf: [0, 3, 0])
            body.append(contentsOf: artwork)
            frames.append(id3Frame("APIC", body: body))
        }

        let size = frames.count
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [3, 0, 0])
        tag.append(contentsOf: [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
        tag.append(frames)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try output.write(contentsOf: tag)
        try input.seek(toOffset: audioOffset)
        try copyRemaining(from: input, to: output)
    }
}
