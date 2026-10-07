import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

private struct LocalAudioCharacteristics {
    var audioFormat: Int = 0
    var codecType: Int = 0
    var codecSubtype: Int = 0
    var sampleRate: Double = 0
    var bitRate: Int = 0
    var isDolbyAtmos: Bool = false
    var hasSpatialAudio: Bool = false
}

private struct FLACFallbackMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var lyrics: String?
    var artworkData: Data?
}

// MARK: - Local File
extension SongMetadata {
    private static func defaultAudioFormatForExtension(_ ext: String) -> Int {
        switch ext.lowercased() {
        case "mp3":
            return 301
        case "flac":
            return 1716281667
        case "opus":
            return 1869641075
        case "m4a", "aac", "m4r":
            return 1633772320
        case "alac":
            return 1634492771
        case "wav", "wave":
            return 1463899717
        default:
            return 0
        }
    }

    private static func inspectLocalAudioCharacteristics(asset: AVURLAsset, url: URL) async -> LocalAudioCharacteristics {
        var result = LocalAudioCharacteristics()
        result.audioFormat = defaultAudioFormatForExtension(url.pathExtension)

        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        for track in tracks {
            if result.bitRate == 0 {
                let estimatedDataRate = Int(((try? await track.load(.estimatedDataRate)) ?? 0).rounded())
                if estimatedDataRate > 0 {
                    result.bitRate = estimatedDataRate
                }
            }

            let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
            for desc in formatDescriptions {
                if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    let asbd = asbdPtr.pointee
                    let formatID = Int(asbd.mFormatID)
                    if result.audioFormat == 0 {
                        result.audioFormat = formatID
                    }
                    result.codecType = formatID
                    if result.sampleRate == 0, asbd.mSampleRate > 0 {
                        result.sampleRate = asbd.mSampleRate
                    }
                }

                let extensions = (CMFormatDescriptionGetExtensions(desc) as NSDictionary?) ?? NSDictionary()
                let formatName = (extensions[kCMFormatDescriptionExtension_FormatName as String] as? String) ?? ""
                let summary = "\(formatName) \(extensions)".lowercased()
                if summary.contains("dolby atmos") || summary.contains("joc") || summary.contains("ec-3+joc") {
                    result.isDolbyAtmos = true
                }
                if summary.contains("spatial") || summary.contains("immersive") {
                    result.hasSpatialAudio = true
                }
            }
        }

        if let allMetadata = try? await asset.load(.metadata) {
            for item in allMetadata {
                if let stringValue = try? await item.load(.stringValue) {
                    let lowered = stringValue.lowercased()
                    if lowered.contains("dolby atmos") || lowered.contains("atmos") {
                        result.isDolbyAtmos = true
                    }
                    if lowered.contains("spatial audio") || lowered.contains("spatial") {
                        result.hasSpatialAudio = true
                    }
                }
            }
        }

        return result
    }

    static func sanitizedFilenameForMetadataHeuristics(_ filename: String) -> String {
        var cleaned = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixPatterns = [
            #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[ _-]+"#,
            #"^[0-9A-Fa-f]{8,}(?:-[0-9A-Fa-f]{2,})+[ _-]+"#,
            #"^[0-9]{6,}[ _-]+"#,
            #"^[0-9A-Fa-f]{10,}[ _-]+"#
        ]

        var didStrip = true
        while didStrip {
            didStrip = false
            for pattern in prefixPatterns {
                let updated = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                if updated != cleaned {
                    cleaned = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                }
            }
        }

        return cleaned
    }

    private static func isLikelyTemporaryImportToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let patterns = [
            #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#,
            #"^[0-9A-Fa-f]{8,}(?:-[0-9A-Fa-f]{2,})+$"#,
            #"^[0-9]{6,}$"#,
            #"^[0-9A-Fa-f]{10,}$"#
        ]

        return patterns.contains {
            trimmed.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func parseSlashSeparatedPair(_ value: String) -> (Int?, Int?) {
        let parts = value
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let first = parts.first.flatMap(Int.init)
        let second = parts.count > 1 ? Int(parts[1]) : nil
        return (first, second)
    }

    private static func readBigEndianUInt24(_ data: Data, offset: Int) -> Int? {
        guard offset + 3 <= data.count else { return nil }
        return (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
    }

    private static func readBigEndianUInt32(_ data: Data, offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func readLittleEndianUInt32(_ data: Data, offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value = data[offset..<offset + 4].enumerated().reduce(UInt32(0)) { partial, pair in
            partial | (UInt32(pair.element) << (UInt32(pair.offset) * 8))
        }
        offset += 4
        return value
    }

    private static func parseFLACMetadataFallback(from url: URL, includeArtwork: Bool) -> FLACFallbackMetadata? {
        guard url.pathExtension.lowercased() == "flac",
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count >= 4,
              String(data: data.prefix(4), encoding: .ascii) == "fLaC" else {
            return nil
        }

        var offset = 4
        var parsed = FLACFallbackMetadata()

        while offset + 4 <= data.count {
            let header = data[offset]
            offset += 1

            let isLastBlock = (header & 0x80) != 0
            let blockType = Int(header & 0x7F)

            guard let blockLength = readBigEndianUInt24(data, offset: offset) else { break }
            offset += 3
            guard offset + blockLength <= data.count else { break }

            let block = data[offset..<offset + blockLength]
            offset += blockLength

            switch blockType {
            case 4:
                var commentOffset = block.startIndex
                guard let vendorLength = readLittleEndianUInt32(data, offset: &commentOffset) else { break }
                commentOffset += Int(vendorLength)
                guard let commentCount = readLittleEndianUInt32(data, offset: &commentOffset) else { break }

                for _ in 0..<commentCount {
                    guard let commentLength = readLittleEndianUInt32(data, offset: &commentOffset) else { break }
                    let length = Int(commentLength)
                    guard commentOffset + length <= block.endIndex else { break }

                    let commentData = data[commentOffset..<commentOffset + length]
                    commentOffset += length
                    guard let comment = String(data: commentData, encoding: .utf8),
                          let equalsIndex = comment.firstIndex(of: "=") else {
                        continue
                    }

                    let key = comment[..<equalsIndex].uppercased()
                    let value = String(comment[comment.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { continue }

                    switch key {
                    case "TITLE":
                        parsed.title = value
                    case "ARTIST":
                        parsed.artist = value
                    case "ALBUM":
                        parsed.album = value
                    case "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST":
                        parsed.albumArtist = value
                    case "GENRE":
                        parsed.genre = value
                    case "DATE", "YEAR":
                        if parsed.year == nil {
                            parsed.year = extractYear(from: value)
                        }
                    case "TRACKNUMBER":
                        let (track, total) = parseSlashSeparatedPair(value)
                        parsed.trackNumber = parsed.trackNumber ?? track
                        parsed.trackCount = parsed.trackCount ?? total
                    case "TRACKTOTAL", "TOTALTRACKS":
                        parsed.trackCount = parsed.trackCount ?? Int(value)
                    case "DISCNUMBER":
                        let (disc, total) = parseSlashSeparatedPair(value)
                        parsed.discNumber = parsed.discNumber ?? disc
                        parsed.discCount = parsed.discCount ?? total
                    case "DISCTOTAL", "TOTALDISCS":
                        parsed.discCount = parsed.discCount ?? Int(value)
                    case "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS":
                        parsed.lyrics = parsed.lyrics ?? value
                    default:
                        break
                    }
                }
            case 6 where includeArtwork && parsed.artworkData == nil:
                var pictureOffset = block.startIndex
                guard readBigEndianUInt32(data, offset: pictureOffset) != nil else { break }
                pictureOffset += 4
                guard let mimeLength = readBigEndianUInt32(data, offset: pictureOffset) else { break }
                pictureOffset += 4 + Int(mimeLength)
                guard let descriptionLength = readBigEndianUInt32(data, offset: pictureOffset) else { break }
                pictureOffset += 4 + Int(descriptionLength)
                pictureOffset += 16
                guard let imageDataLength = readBigEndianUInt32(data, offset: pictureOffset) else { break }
                pictureOffset += 4
                let imageLength = Int(imageDataLength)
                guard pictureOffset + imageLength <= block.endIndex else { break }
                parsed.artworkData = Data(data[pictureOffset..<pictureOffset + imageLength])
            default:
                break
            }

            if isLastBlock { break }
        }

        return parsed
    }

    
    static func fromURL(_ url: URL, includeArtwork: Bool = true) async throws -> SongMetadata {
        let asset = AVURLAsset(url: url)
        
        
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            Logger.shared.log("[SongMetadata] Failed to load duration for \(url.lastPathComponent): \(error.localizedDescription)")
            duration = .zero
        }
        let durationMs = Int(CMTimeGetSeconds(duration) * 1000)
        
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        
        
        let filenameWithoutExt = url.deletingPathExtension().lastPathComponent
        let sanitizedFilenameWithoutExt = sanitizedFilenameForMetadataHeuristics(filenameWithoutExt)
        let effectiveFilenameWithoutExt = sanitizedFilenameWithoutExt.isEmpty ? filenameWithoutExt : sanitizedFilenameWithoutExt
        var title = effectiveFilenameWithoutExt
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var albumArtist: String?
        var genre = "Music"
        var year = Calendar.current.component(.year, from: Date())
        var artworkData: Data?
        
        var trackNumber: Int?
        var trackCount: Int?
        var discNumber: Int?
        var discCount: Int?
        var lyrics: String?
        
        let isM4A = url.pathExtension.lowercased() == "m4a"
        var storeId: Int64 = 0
        var storefrontId: Int64 = 0
        var artistId: Int64 = 0
        var composerId: Int64 = 0
        var playlistId: Int64 = 0
        var genreStoreId: Int64 = 0
        var explicitRating: Int = 0
        var copyright: String?
        var xid: String?
        var releaseDate: Int = 0
        let localAudio = await inspectLocalAudioCharacteristics(asset: asset, url: url)
        
        
        
        let commonMetadata: [AVMetadataItem]
        do {
            commonMetadata = try await asset.load(.commonMetadata)
        } catch {
            Logger.shared.log("[SongMetadata] Failed to load common metadata for \(url.lastPathComponent): \(error.localizedDescription)")
            commonMetadata = []
        }

        
        for item in commonMetadata {
            guard let key = item.commonKey else { continue }
            
            switch key {
            case .commonKeyTitle:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    title = value
                }
            case .commonKeyArtist:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    artist = value
                }
            case .commonKeyAlbumName:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    album = value
                }
            case .commonKeyType:
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    genre = value
                }
            case .commonKeyCreationDate:
                if let value = try? await item.load(.stringValue),
                   let extracted = extractYear(from: value) {
                    year = extracted
                }
            case .commonKeyArtwork:
                if includeArtwork, let data = try? await item.load(.dataValue) {
                    artworkData = data
                    Logger.shared.log("[SongMetadata] Extracted artwork: \(data.count) bytes")
                }
            default: break
            }
        }
        
        
        let allMetadata: [AVMetadataItem]
        do {
            allMetadata = try await asset.load(.metadata)
        } catch {
            Logger.shared.log("[SongMetadata] Failed to load full metadata for \(url.lastPathComponent): \(error.localizedDescription)")
            allMetadata = []
        }
        
        
        for item in allMetadata {
            
            var keyString = ""
            if let strKey = item.key as? String {
                keyString = strKey
            } else if let intKey = item.key as? Int {
                
                
                keyString = "\(intKey)"
            }
            
            let identifier = item.identifier?.rawValue ?? ""
            let combined = "\(identifier)|\(keyString)".uppercased()
            let compactKey = combined.filter { $0.isLetter || $0.isNumber }
            let isAlbumArtistKey = compactKey.contains("ALBUMARTIST") || combined.contains("TPE2") || combined.contains("AART")
            let isAlbumKey = compactKey.contains("ALBUM")
            
            if isM4A {
                let id = identifier
                let isAppleKey = id.contains("rtng") || id.contains("geID") || id.contains("sfID") || id.contains("atID") || id.contains("cmID") || id.contains("plID") || id.contains("cnID") || id.contains("cprt") || id.contains("xid")
                
                if isAppleKey {
                    if let val = try? await item.load(.stringValue), !val.isEmpty {
                        if id.contains("rtng"), let v = Int(val) { explicitRating = v }
                        if id.contains("geID"), let v = Int64(val) { genreStoreId = v }
                        if id.contains("sfID"), let v = Int64(val) { storefrontId = v }
                        if id.contains("atID"), let v = Int64(val) { artistId = v }
                        if id.contains("cmID"), let v = Int64(val) { composerId = v }
                        if id.contains("plID"), let v = Int64(val) { playlistId = v }
                        if id.contains("cnID"), let v = Int64(val) { storeId = v }
                        if id.contains("cprt") { copyright = val }
                        if id.contains("xid") { xid = val }
                    } else if let data = try? await item.load(.dataValue) {
                        if id.contains("rtng") && data.count >= 1 { explicitRating = Int(data[0]) }
                        if data.count >= 4 {
                            let intVal = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                            let val64 = Int64(intVal)
                            if id.contains("geID") { genreStoreId = val64 }
                            if id.contains("sfID") { storefrontId = val64 }
                            if id.contains("atID") { artistId = val64 }
                            if id.contains("cmID") { composerId = val64 }
                            if id.contains("plID") { playlistId = val64 }
                            if id.contains("cnID") { storeId = val64 }
                        }
                    }
                }
                
                if keyString == "\u{00A9}day" {
                    if let val = try? await item.load(.stringValue), !val.isEmpty {
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "en_US_POSIX")
                        
                        let formats = [
                            "yyyy-MM-dd'T'HH:mm:ssZ",
                            "yyyy-MM-dd'T'HH:mm:ss",
                            "yyyy-MM-dd",
                            "yyyy"
                        ]
                        
                        for fmt in formats {
                            df.dateFormat = fmt
                            if let date = df.date(from: val) {
                                releaseDate = Int(date.timeIntervalSinceReferenceDate)
                                Logger.shared.log("[SongMetadata] M4A release date: \(val) -> epoch \(releaseDate)")
                                break
                            }
                        }
                        
                        if let extracted = extractYear(from: val) {
                            year = extracted
                            Logger.shared.log("[SongMetadata] M4A year from ©day: \(year)")
                        }
                    }
                }
            }
            
            
            if trackNumber == nil {
                if combined.contains("TRCK") || combined.contains("TRACK") || combined.contains("TRKN") || keyString.lowercased() == "trkn" {
                    
                    if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let t = Int(components[0]) { trackNumber = t }
                        if components.count > 1, let tc = Int(components[1]) { trackCount = tc }
                    }
                    
                    else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 8 {
                        
                        let track = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                        let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                        if track > 0 { trackNumber = Int(track) }
                        if total > 0 { trackCount = Int(total) }
                    }
                }
            }
            
            
            if discNumber == nil {
                if combined.contains("TPOS") || combined.contains("DISC") || combined.contains("DISK") || keyString.lowercased() == "disk" {
                     if let stringVal = try? await item.load(.stringValue) {
                        let components = stringVal.components(separatedBy: "/")
                        if let d = Int(components[0]) { discNumber = d }
                        if components.count > 1, let dc = Int(components[1]) { discCount = dc }
                     } else if let dataVal = try? await item.load(.dataValue), dataVal.count >= 6 { 
                         
                         let disc = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                         let total = dataVal.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                         if disc > 0 { discNumber = Int(disc) }
                         if total > 0 { discCount = Int(total) }
                     }
                }
            }

            
            if includeArtwork && artworkData == nil {
                
                if combined.contains("ARTWORK") || combined.contains("PICTURE") || combined.contains("APIC") || combined.contains("COVR") {
                    if let data = try? await item.load(.dataValue), !data.isEmpty {
                        artworkData = data
                        Logger.shared.log("[SongMetadata] Deep Scan extracted artwork: \(data.count) bytes (Key: \(combined))")
                    }
                }
            }

            
            if let val = try? await item.load(.stringValue), !val.isEmpty {
                if keyString == "\u{00A9}gen" || keyString == "gnre" {
                     if genre == "Music" { genre = val }
                }
                
                if (combined.contains("TITLE") || combined.contains("NAM")) && !isAlbumKey && title == effectiveFilenameWithoutExt { title = val }
                if (combined.contains("ARTIST") || combined.contains("PERFORMER")) && !isAlbumArtistKey && artist == "Unknown Artist" { artist = val }
                if combined.contains("ALBUM") && !isAlbumArtistKey && album == "Unknown Album" { album = val }
                if (combined.contains("GENRE") || combined.contains("GEN")) && genre == "Music" { genre = val }
                
                
                if isAlbumArtistKey {
                   let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                   if !trimmed.isEmpty && trimmed.lowercased() != "unknown artist" {
                       albumArtist = trimmed
                       Logger.shared.log("[SongMetadata] Extracted Album Artist: \(trimmed) from key: \(combined)")
                   } else {
                       Logger.shared.log("[SongMetadata] Ignored invalid Album Artist: '\(val)'")
                   }
                }

                
                if year == Calendar.current.component(.year, from: Date()) {
                    if combined.contains("DATE") || combined.contains("YEAR") || combined.contains("TYER") || combined.contains("TDRC") || combined.contains("DAY") {
                        if let extracted = extractYear(from: val) {
                            year = extracted
                            Logger.shared.log("[SongMetadata] Extracted year: \(year) from key: \(combined) (Val: \(val))")
                        }
                    }
                }
                
                if lyrics == nil {
                    if combined.contains("USLT") || combined.contains("LYRICS") || combined.contains("UNSYNC") || keyString == "\u{00A9}lyr" {
                         lyrics = SongMetadata.cleanLyrics(val, title: title, artist: artist)
                         Logger.shared.log("[SongMetadata] Extracted and cleaned lyrics from key: \(combined)")
                    }
                }
            }
            
            if trackNumber == nil {
                if keyString == "trkn" || combined.contains("TRKN") {
                    if let data = try? await item.load(.dataValue), data.count >= 8 {
                         let track = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                         let total = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                         if track > 0 { trackNumber = Int(track) }
                         if total > 0 { trackCount = Int(total) }
                         Logger.shared.log("[SongMetadata] Extracted Track via Data: \(trackNumber ?? 0)/\(trackCount ?? 0)")
                    }
                }
            }
            if discNumber == nil {
                if keyString == "disk" || combined.contains("DISK") {
                    if let data = try? await item.load(.dataValue), data.count >= 6 {
                         let disc = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
                         let total = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
                         if disc > 0 { discNumber = Int(disc) }
                         if total > 0 { discCount = Int(total) }
                         Logger.shared.log("[SongMetadata] Extracted Disc via Data: \(discNumber ?? 0)/\(discCount ?? 0)")
                    }
                }
            }
        }
        
        
        if let aa = albumArtist, (aa.isEmpty || aa.lowercased() == "unknown artist") {
            albumArtist = nil
        }
        
        if url.pathExtension.lowercased() == "flac" &&
            (title == effectiveFilenameWithoutExt || artist == "Unknown Artist" || album == "Unknown Album" || trackNumber == nil || discNumber == nil || (includeArtwork && artworkData == nil)) {
            if let flacFallback = parseFLACMetadataFallback(from: url, includeArtwork: includeArtwork) {
                if title == effectiveFilenameWithoutExt, let fallbackTitle = flacFallback.title, !fallbackTitle.isEmpty {
                    title = fallbackTitle
                }
                if artist == "Unknown Artist", let fallbackArtist = flacFallback.artist, !fallbackArtist.isEmpty {
                    artist = fallbackArtist
                }
                if album == "Unknown Album", let fallbackAlbum = flacFallback.album, !fallbackAlbum.isEmpty {
                    album = fallbackAlbum
                }
                if albumArtist == nil, let fallbackAlbumArtist = flacFallback.albumArtist, !fallbackAlbumArtist.isEmpty {
                    albumArtist = fallbackAlbumArtist
                }
                if genre == "Music", let fallbackGenre = flacFallback.genre, !fallbackGenre.isEmpty {
                    genre = fallbackGenre
                }
                if year == Calendar.current.component(.year, from: Date()), let fallbackYear = flacFallback.year {
                    year = fallbackYear
                }
                trackNumber = trackNumber ?? flacFallback.trackNumber
                trackCount = trackCount ?? flacFallback.trackCount
                discNumber = discNumber ?? flacFallback.discNumber
                discCount = discCount ?? flacFallback.discCount
                if lyrics == nil, let fallbackLyrics = flacFallback.lyrics, !fallbackLyrics.isEmpty {
                    lyrics = SongMetadata.cleanLyrics(fallbackLyrics, title: title, artist: artist)
                }
                if includeArtwork && artworkData == nil, let fallbackArtwork = flacFallback.artworkData, !fallbackArtwork.isEmpty {
                    artworkData = fallbackArtwork
                }
                Logger.shared.log("[SongMetadata] Applied FLAC Vorbis fallback metadata for \(url.lastPathComponent)")
            }
        }

        if isLikelyTemporaryImportToken(title) {
            title = effectiveFilenameWithoutExt
        }
        if isLikelyTemporaryImportToken(artist) {
            artist = "Unknown Artist"
        }
        if isLikelyTemporaryImportToken(album) {
            album = "Unknown Album"
        }

        genre = canonicalGenre(genre)

        if (title == effectiveFilenameWithoutExt || artist == "Unknown Artist") && sanitizedFilenameWithoutExt.contains(" - ") {
             let parts = sanitizedFilenameWithoutExt.components(separatedBy: " - ")
             
             if parts.count >= 3 {
                 if let trackNum = Int(parts[0]) {
                     trackNumber = trackNum
                     artist = parts[1].trimmingCharacters(in: .whitespaces)
                     title = parts[2].trimmingCharacters(in: .whitespaces)
                     Logger.shared.log("[SongMetadata] Parsed filename (Track - Artist - Title): \(sanitizedFilenameWithoutExt)")
                 } else {
                     let p1 = parts[0].trimmingCharacters(in: .whitespaces)
                     let p2 = parts[1].trimmingCharacters(in: .whitespaces)
                     if !isLikelyTemporaryImportToken(p1) {
                         artist = p1
                     }
                     title = p2
                 }
             }
             else if parts.count == 2 {
                 if let trackNum = Int(parts[0]) {
                     trackNumber = trackNum
                     title = parts[1].trimmingCharacters(in: .whitespaces)
                     Logger.shared.log("[SongMetadata] Parsed filename (Track - Title): \(sanitizedFilenameWithoutExt)")
                 } else {
                     let p1 = parts[0].trimmingCharacters(in: .whitespaces)
                     let p2 = parts[1].trimmingCharacters(in: .whitespaces)
                     
                     let p2LooksLikeArtist = p2.contains(",") || p2.lowercased().contains("feat")
                     let p1LooksLikeArtist = p1.contains(",") || p1.lowercased().contains("feat")
                     
                     if p2LooksLikeArtist && !p1LooksLikeArtist {
                         title = p1
                         if !isLikelyTemporaryImportToken(p2) {
                             artist = p2
                         }
                         Logger.shared.log("[SongMetadata] Parsed filename (Title - Artist) [Heuristic]: \(sanitizedFilenameWithoutExt)")
                     } else {
                         if !isLikelyTemporaryImportToken(p1) {
                             artist = p1
                         }
                         title = p2
                         Logger.shared.log("[SongMetadata] Parsed filename (Artist - Title): \(sanitizedFilenameWithoutExt)")
                     }
                 }
             }
        }
        
        Logger.shared.log("[SongMetadata] Final: title=\(title), artist=\(artist), album=\(album), track=\(trackNumber ?? 0)/\(trackCount ?? 0)")
        
        if isM4A && (storeId > 0 || storefrontId > 0) {
            Logger.shared.log("[SongMetadata] M4A Apple IDs: storeId=\(storeId), sfID=\(storefrontId), atID=\(artistId), cmID=\(composerId), plID=\(playlistId), geID=\(genreStoreId), rtng=\(explicitRating)")
        }
        if localAudio.isDolbyAtmos || localAudio.hasSpatialAudio {
            Logger.shared.log("[SongMetadata] Local audio traits detected for \(url.lastPathComponent): atmos=\(localAudio.isDolbyAtmos), spatial=\(localAudio.hasSpatialAudio), format=\(localAudio.audioFormat), bitrate=\(localAudio.bitRate), sampleRate=\(localAudio.sampleRate)")
        }
        
        return SongMetadata(
            localURL: url,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            durationMs: durationMs,
            fileSize: fileSize,
            remoteFilename: generateRemoteFilename(withExtension: url.pathExtension),
            artworkData: artworkData,
            appleMusicAudioTraits: [],
            isMasteredForItunes: false,
            isAppleDigitalMaster: false,
            playbackAudioFormat: localAudio.audioFormat,
            playbackCodecType: localAudio.codecType,
            playbackCodecSubtype: localAudio.codecSubtype,
            playbackSampleRate: localAudio.sampleRate,
            playbackBitRate: localAudio.bitRate,
            localFileHasDolbyAtmos: localAudio.isDolbyAtmos,
            localFileHasSpatialAudio: localAudio.hasSpatialAudio,
            trackNumber: trackNumber,
            trackCount: trackCount,
            discNumber: discNumber,
            discCount: discCount,
            lyrics: lyrics,
            storeId: storeId,
            storefrontId: storefrontId,
            artistId: artistId,
            composerId: composerId,
            playlistId: playlistId,
            genreStoreId: genreStoreId,
            explicitRating: explicitRating,
            copyright: copyright,
            xid: xid,
            releaseDate: releaseDate
        )
    }

    static func extractEmbeddedArtwork(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)

        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                guard item.commonKey == .commonKeyArtwork else { continue }
                if let data = try? await item.load(.dataValue), !data.isEmpty {
                    return data
                }
            }
        }

        if let allMetadata = try? await asset.load(.metadata) {
            for item in allMetadata {
                var keyString = ""
                if let strKey = item.key as? String {
                    keyString = strKey
                } else if let intKey = item.key as? Int {
                    keyString = "\(intKey)"
                }

                let identifier = item.identifier?.rawValue ?? ""
                let combined = "\(identifier)|\(keyString)".uppercased()
                if combined.contains("ARTWORK") || combined.contains("PICTURE") || combined.contains("APIC") || combined.contains("COVR") {
                    if let data = try? await item.load(.dataValue), !data.isEmpty {
                        return data
                    }
                }
            }
        }

        return nil
    }

    static func extractEmbeddedArtworkThumbnail(from url: URL, maxDimension: CGFloat = 120) async -> Data? {
        guard let fullData = await extractEmbeddedArtwork(from: url) else { return nil }
        return createArtworkThumbnailData(from: fullData, maxDimension: maxDimension)
    }

    private static func createArtworkThumbnailData(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let largestDimension = max(size.width, size.height)
        let scale = largestDimension > maxDimension ? (maxDimension / largestDimension) : 1
        let targetSize = CGSize(
            width: max(size.width * scale, 1),
            height: max(size.height * scale, 1)
        )

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.72)
    }
    
    
    static private func extractYear(from string: String) -> Int? {
        
        
        
        
        do {
            let regex = try NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")
            let nsString = string as NSString
            let results = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
            
            if let first = results.first {
                let match = nsString.substring(with: first.range)
                if let y = Int(match), y >= 1900 && y <= 2100 {
                    return y
                }
            }
        } catch {
            return nil
        }
        
        
        if let prefixInt = Int(string.prefix(4)), prefixInt >= 1900 && prefixInt <= 2100 {
            return prefixInt
        }
        
        return nil
    }
}
