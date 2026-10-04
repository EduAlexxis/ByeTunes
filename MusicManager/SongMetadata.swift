import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox


struct AppleMusicArtworkColors: Codable {
    var backgroundColor: String
    var primaryTextColor: String
    var secondaryTextColor: String
    var tertiaryTextColor: String
}

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

struct SongMetadata: Identifiable {
    let id = UUID()
    
    var localURL: URL
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var genre: String
    var year: Int
    var durationMs: Int
    var fileSize: Int
    var remoteFilename: String
    var artworkData: Data?
    var artworkPreviewData: Data? = nil
    var appleMusicArtworkColors: AppleMusicArtworkColors? = nil
    var appleMusicAudioTraits: [String] = []
    var isMasteredForItunes: Bool = false
    var isAppleDigitalMaster: Bool = false
    var playbackAudioFormat: Int = 0
    var playbackCodecType: Int = 0
    var playbackCodecSubtype: Int = 0
    var playbackSampleRate: Double = 0
    var playbackBitRate: Int = 0
    var localFileHasDolbyAtmos: Bool = false
    var localFileHasSpatialAudio: Bool = false
    
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var lyrics: String?
    
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

    var customAlbumBackgroundColor: String? = nil

    var richAppleMetadataFetched: Bool = false

    var hasAppleCatalogIdentity: Bool {
        storeId > 0
    }

    var hasAppleArtistIdentity: Bool {
        artistId > 0
    }

    var hasAppleAlbumIdentity: Bool {
        playlistId > 0
    }

    var hasAppleISRC: Bool {
        guard let xid else { return false }
        return !xid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var audioFormatLabel: String {
        switch AudioFormatID(playbackCodecType) {
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD:
            return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatLinearPCM:
            let ext = localURL.pathExtension.lowercased()
            return ext == "aiff" || ext == "aif" ? "AIFF" : "WAV"
        default:
            let ext = localURL.pathExtension
            return ext.isEmpty ? "—" : ext.uppercased()
        }
    }

    var isLosslessAudio: Bool {
        audioFormatLabel == "FLAC" || audioFormatLabel == "ALAC"
    }

    var appleMetadataCoverageSummary: String {
        let flags = [
            "storeId=\(storeId)",
            "artistId=\(artistId)",
            "albumId=\(playlistId)",
            "composerId=\(composerId)",
            "genreId=\(genreStoreId)",
            "isrc=\(hasAppleISRC ? (xid ?? "") : "none")",
            "releaseDate=\(releaseDate)",
            "traits=\(appleMusicAudioTraits.isEmpty ? "none" : appleMusicAudioTraits.joined(separator: ","))",
            "adm=\(isAppleDigitalMaster)",
            "mfit=\(isMasteredForItunes)"
        ]
        return flags.joined(separator: ", ")
    }

    var appleMetadataMatchTier: String {
        if hasAppleCatalogIdentity && hasAppleArtistIdentity && hasAppleAlbumIdentity && hasAppleISRC {
            return "full"
        }
        if hasAppleCatalogIdentity && (hasAppleArtistIdentity || hasAppleAlbumIdentity) {
            return "partial"
        }
        if hasAppleCatalogIdentity {
            return "track-only"
        }
        return "none"
    }

    var isDolbyAtmosCapable: Bool {
        localFileHasDolbyAtmos || appleMusicAudioTraits.contains { $0.caseInsensitiveCompare("atmos") == .orderedSame }
    }

    var hasSpatialAudioTrait: Bool {
        localFileHasSpatialAudio || appleMusicAudioTraits.contains { $0.caseInsensitiveCompare("spatial") == .orderedSame }
    }

    var hasAppleLosslessTrait: Bool {
        appleMusicAudioTraits.contains { trait in
            trait.caseInsensitiveCompare("lossless") == .orderedSame ||
            trait.caseInsensitiveCompare("hi-res-lossless") == .orderedSame ||
            trait.caseInsensitiveCompare("hires-lossless") == .orderedSame
        }
    }
    
    
    var artworkToken: String {
        return "local://\(remoteFilename)"
    }
    
    
    nonisolated static func generateRemoteFilename(withExtension ext: String? = nil) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomName = String((0..<12).map { _ in letters.randomElement()! })
        let e = (ext?.isEmpty == false) ? ext!.lowercased() : "mp3"
        return "\(randomName).\(e)"
    }
    
    
    static func generatePersistentId() -> Int64 {
        return Int64.random(in: 1_000_000_000_000_000_000...Int64.max)
    }

    static func shouldPreserveLocalFile(_ url: URL) -> Bool {
        guard UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else { return false }
        let persistentDirectory = persistentDownloadsDirectory()
        let standardizedFilePath = url.standardizedFileURL.path
        let standardizedDirectoryPath = persistentDirectory.standardizedFileURL.path + "/"
        return standardizedFilePath.hasPrefix(standardizedDirectoryPath)
    }

    static func defaultPersistentDownloadsDirectory() -> URL {
        URL.documentsDirectory.appendingPathComponent("Downloaded Songs", isDirectory: true)
    }

    static func persistentDownloadsDirectory() -> URL {
        customPersistentDownloadsDirectory() ?? defaultPersistentDownloadsDirectory()
    }

    static func customPersistentDownloadsDirectory() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "downloadedSongsFolderBookmark") else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale,
               let refreshedBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshedBookmark, forKey: "downloadedSongsFolderBookmark")
            }

            return url
        } catch {
            Logger.shared.log("[SongMetadata] Failed to resolve custom downloads folder bookmark: \(error)")
            return nil
        }
    }

    static func generateGroupingKey(_ text: String) -> Data {
        guard !text.isEmpty else { return Data() }
        
        var result = [UInt8]()
        for char in text.uppercased() {
            if char >= "A" && char <= "Z" {
                result.append(UInt8(char.asciiValue! - Character("A").asciiValue! + 1))
            } else if char == " " {
                result.append(0x04)
            } else if char == "/" {
                result.append(0x0A)
            }
        }
        return Data(result)
    }
    
    static func canonicalGenre(_ raw: String?) -> String {
        guard let raw else { return "Music" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Music" }
        
        let lowered = trimmed.lowercased()
        let unknownSet: Set<String> = [
            "unknown",
            "unknown genre",
            "n/a",
            "na",
            "none",
            "null",
            "(null)"
        ]
        if unknownSet.contains(lowered) {
            return "Music"
        }
        return trimmed
    }

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
    
    static func cleanLyrics(_ rawLyrics: String, title: String? = nil, artist: String? = nil) -> String {
        var cleaned = rawLyrics.replacingOccurrences(of: #"\[([a-z]+):.*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        
        cleaned = cleaned.replacingOccurrences(of: #"\[\d{2,}:\d{2}(\.\d{2,})?\]"#, with: "", options: .regularExpression)
        
        cleaned = cleaned.replacingOccurrences(of: #"\d+\s+Contributors"#, with: "", options: .regularExpression)
        
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)

        let lines = cleaned.components(separatedBy: .newlines)
        var resultLines: [String] = []
        
        let noiseWords = ["lyrics", "letra", "contributors", "official", "video", "audio"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let last = resultLines.last, !last.isEmpty {
                    resultLines.append("")
                }
                continue
            }
            
            if let title = title {
                let lowLine = trimmed.lowercased()
                let lowTitle = title.lowercased()
                
                if lowLine == lowTitle {
                    continue
                }
                
                if lowLine.contains(lowTitle) {
                    var remainder = lowLine.replacingOccurrences(of: lowTitle, with: "")
                    for noise in noiseWords {
                        remainder = remainder.replacingOccurrences(of: noise, with: "")
                    }
                    let cleanRemainder = remainder.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                    if cleanRemainder.isEmpty {
                        continue 
                    }
                }
            }
            
            resultLines.append(trimmed)
        }
        
        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fetchLyricsFromLRCLIB(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        let titleEnc = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artistEnc = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let albumEnc = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let durationSec = durationMs / 1000
        
        let urlString = "https://lrclib.net/api/get?artist_name=\(artistEnc)&track_name=\(titleEnc)&album_name=\(albumEnc)&duration=\(durationSec)"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("ByeTunes/2.5 (https://github.com/EduAlexxis/ByeTunes)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await SongMetadataNetworking.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let lyrics = (json?["plainLyrics"] as? String) ?? (json?["syncedLyrics"] as? String)
            
            if let l = lyrics, !l.isEmpty {
                Logger.shared.log("[SongMetadata] Successfully fetched lyrics from LRCLIB")
                return SongMetadata.cleanLyrics(l, title: title, artist: artist)
            }
        } catch {
            Logger.shared.log("[SongMetadata] LRCLIB fetch failed: \(error)")
        }
        return nil
    }

    static func fetchLyrics(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        if let lrclibLyrics = await fetchLyricsFromLRCLIB(title: title, artist: artist, album: album, durationMs: durationMs) {
            return lrclibLyrics
        }

        if let musixMatchLyrics = await fetchLyricsFromMusixMatch(title: title, artist: artist, album: album, durationMs: durationMs) {
            return musixMatchLyrics
        }

        if let netEaseLyrics = await fetchLyricsFromNetEase(title: title, artist: artist, album: album, durationMs: durationMs) {
            return netEaseLyrics
        }

        return nil
    }

    private static var musixMatchAppURLCache: String?
    private static var musixMatchSecretCache: String?

    private static func fetchLyricsFromMusixMatch(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        do {
            guard let searchResponse = try await performMusixMatchRequest(
                endpoint: "track.search",
                queryItems: [
                    URLQueryItem(name: "q", value: "\(title) \(artist)"),
                    URLQueryItem(name: "f_has_lyrics", value: "true"),
                    URLQueryItem(name: "page_size", value: "5"),
                    URLQueryItem(name: "page", value: "1")
                ]
            ) else {
                return nil
            }

            guard let trackID = bestMusixMatchTrackID(from: searchResponse, title: title, artist: artist, album: album, durationMs: durationMs) else {
                Logger.shared.log("[SongMetadata] Musixmatch search returned no suitable lyric match")
                return nil
            }

            guard let lyricsResponse = try await performMusixMatchRequest(
                endpoint: "track.lyrics.get",
                queryItems: [URLQueryItem(name: "track_id", value: String(trackID))]
            ) else {
                return nil
            }

            guard
                let message = lyricsResponse["message"] as? [String: Any],
                let body = message["body"] as? [String: Any],
                let lyrics = body["lyrics"] as? [String: Any],
                let lyricsBody = lyrics["lyrics_body"] as? String
            else {
                return nil
            }

            let cleaned = cleanLyrics(stripMusixMatchFooter(from: lyricsBody), title: title, artist: artist)
            guard !cleaned.isEmpty else { return nil }

            Logger.shared.log("[SongMetadata] Successfully fetched lyrics from Musixmatch fallback")
            return cleaned
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch fallback failed: \(error)")
            return nil
        }
    }

    private static func performMusixMatchRequest(endpoint: String, queryItems: [URLQueryItem]) async throws -> [String: Any]? {
        let baseURLString = "https://www.musixmatch.com/ws/1.1/\(endpoint)"
        let defaultItems: [(String, String)] = [
            ("app_id", "web-desktop-app-v1.0"),
            ("format", "json")
        ]
        let allItems = defaultItems + queryItems.map { ($0.name, $0.value ?? "") }
        let canonicalQuery = allItems
            .map { "\(musixMatchPercentEncode($0.0))=\(musixMatchPercentEncode($0.1))" }
            .joined(separator: "&")
            .replacingOccurrences(of: "%20", with: "+")
            .replacingOccurrences(of: " ", with: "+")
        let canonicalURLString = "\(baseURLString)?\(canonicalQuery)"

        let signature = try await musixMatchSignature(for: canonicalURLString)
        guard let signedURL = URL(string: canonicalURLString + signature) else { return nil }

        var request = URLRequest(url: signedURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode != 200 {
            return nil
        }

        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func bestMusixMatchTrackID(from response: [String: Any], title: String, artist: String, album: String, durationMs: Int) -> Int? {
        guard
            let message = response["message"] as? [String: Any],
            let body = message["body"] as? [String: Any],
            let trackList = body["track_list"] as? [[String: Any]]
        else {
            return nil
        }

        let normalizedTitle = normalizedLyricsMatchValue(title)
        let normalizedArtist = normalizedLyricsMatchValue(artist)
        let normalizedAlbum = normalizedLyricsMatchValue(album)
        let expectedDurationSec = durationMs > 0 ? durationMs / 1000 : nil

        let bestTrack = trackList.compactMap { entry -> (trackID: Int, score: Int)? in
            guard
                let track = entry["track"] as? [String: Any],
                let trackID = track["track_id"] as? Int
            else {
                return nil
            }

            let trackTitle = normalizedLyricsMatchValue(track["track_name"] as? String)
            let trackArtist = normalizedLyricsMatchValue(track["artist_name"] as? String)
            let trackAlbum = normalizedLyricsMatchValue(track["album_name"] as? String)
            let trackLength = track["track_length"] as? Int

            var score = 0

            if trackTitle == normalizedTitle {
                score += 120
            } else if trackTitle.contains(normalizedTitle) || normalizedTitle.contains(trackTitle) {
                score += 70
            }

            if trackArtist == normalizedArtist {
                score += 120
            } else if trackArtist.contains(normalizedArtist) || normalizedArtist.contains(trackArtist) {
                score += 70
            }

            if !normalizedAlbum.isEmpty {
                if trackAlbum == normalizedAlbum {
                    score += 30
                } else if trackAlbum.contains(normalizedAlbum) || normalizedAlbum.contains(trackAlbum) {
                    score += 15
                }
            }

            if let expectedDurationSec, let trackLength, trackLength > 0 {
                score += max(0, 30 - abs(trackLength - expectedDurationSec))
            }

            return (trackID, score)
        }
        .max(by: { $0.score < $1.score })

        guard let bestTrack, bestTrack.score >= 140 else { return nil }
        return bestTrack.trackID
    }

    private static func normalizedLyricsMatchValue(_ value: String?) -> String {
        guard let value else { return "" }
        let lowered = value.lowercased()
        let cleaned = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMusixMatchFooter(from lyrics: String) -> String {
        if let footerRange = lyrics.range(of: "*******") {
            return String(lyrics[..<footerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var musixMatchUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    }

    private static func musixMatchPercentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func musixMatchSignature(for absoluteURL: String) async throws -> String {
        let secret = try await musixMatchSecret()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd"

        let message = Data((absoluteURL + dateFormatter.string(from: Date())).utf8)
        let key = SymmetricKey(data: Data(secret.utf8))
        let signatureData = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        let signature = signatureData.base64EncodedString()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedSignature = signature.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? signature
        return "&signature=\(encodedSignature)&signature_protocol=sha256"
    }

    private static func musixMatchSecret() async throws -> String {
        if let musixMatchSecretCache, !musixMatchSecretCache.isEmpty {
            return musixMatchSecretCache
        }

        let appURL = try await musixMatchAppURL()
        var request = URLRequest(url: appURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let javascript = String(decoding: data, as: UTF8.self)
        let pattern = #"from\(\s*"(.*?)"\s*\.split"#

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: javascript, range: NSRange(javascript.startIndex..., in: javascript)),
            let encodedRange = Range(match.range(at: 1), in: javascript)
        else {
            throw URLError(.cannotParseResponse)
        }

        let encoded = String(javascript[encodedRange])
        let reversed = String(encoded.reversed())

        guard
            let decodedData = Data(base64Encoded: reversed),
            let secret = String(data: decodedData, encoding: .utf8),
            !secret.isEmpty
        else {
            throw URLError(.cannotDecodeRawData)
        }

        musixMatchSecretCache = secret
        return secret
    }

    private static func musixMatchAppURL() async throws -> URL {
        if let cached = musixMatchAppURLCache, let url = URL(string: cached) {
            return url
        }

        guard let searchURL = URL(string: "https://www.musixmatch.com/search") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: searchURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("mxm_bab=AB", forHTTPHeaderField: "Cookie")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let html = String(decoding: data, as: UTF8.self)
        let pattern = #"src="([^"]*/_next/static/chunks/pages/_app-[^"]+\.js)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw URLError(.cannotParseResponse)
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard
            let lastMatch = matches.last,
            let relativeRange = Range(lastMatch.range(at: 1), in: html)
        else {
            throw URLError(.cannotParseResponse)
        }

        let relativePath = String(html[relativeRange])
        let fullURLString: String
        if relativePath.hasPrefix("http://") || relativePath.hasPrefix("https://") {
            fullURLString = relativePath
        } else {
            fullURLString = "https://www.musixmatch.com" + relativePath
        }

        guard let url = URL(string: fullURLString) else {
            throw URLError(.badURL)
        }

        musixMatchAppURLCache = fullURLString
        return url
    }

    private static let netEaseHost = "music.163.com"
    private static let netEaseEapiPathSalt = "-36cd479b6b5-"
    private static let netEaseEapiAESKey = "e82ckenh8dichen8"
    private static let netEaseUserAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154"
    private static let netEaseDefaultDeviceID = "pyncm!"

    private static func fetchLyricsFromNetEase(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        do {
            guard let searchResponse = try await performNetEaseEapiRequest(
                path: "/eapi/cloudsearch/pc",
                payload: [
                    "s": "\(title) \(artist)",
                    "type": "1",
                    "limit": "5",
                    "offset": "0"
                ]
            ) else {
                return nil
            }

            guard let songID = bestNetEaseTrackID(from: searchResponse, title: title, artist: artist, album: album, durationMs: durationMs) else {
                Logger.shared.log("[SongMetadata] NetEase search returned no suitable lyric match")
                return nil
            }

            guard let lyricsResponse = try await performNetEaseEapiRequest(
                path: "/eapi/song/lyric/v1",
                payload: [
                    "id": String(songID),
                    "cp": false,
                    "lv": 0,
                    "tv": 0,
                    "rv": 0,
                    "kv": 0,
                    "yv": 0,
                    "ytv": 0,
                    "yrv": 0
                ]
            ) else {
                return nil
            }

            let lyricCandidates = [
                ((lyricsResponse["lrc"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["klyric"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["yrc"] as? [String: Any])?["lyric"] as? String)
            ]

            for candidate in lyricCandidates {
                guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let cleaned = cleanLyrics(stripTimedLyrics(candidate), title: title, artist: artist)
                if !cleaned.isEmpty {
                    Logger.shared.log("[SongMetadata] Successfully fetched lyrics from NetEase fallback")
                    return cleaned
                }
            }
        } catch {
            Logger.shared.log("[SongMetadata] NetEase fallback failed: \(error)")
        }

        return nil
    }

    private static func performNetEaseEapiRequest(path: String, payload: [String: Any]) async throws -> [String: Any]? {
        let apiPath = path.replacingOccurrences(of: "/eapi/", with: "/api/")
        var requestPayload = payload
        requestPayload["header"] = netEaseHeaderJSONString()

        guard let payloadData = try? JSONSerialization.data(withJSONObject: requestPayload, options: []),
              let payloadJSONString = String(data: payloadData, encoding: .utf8) else {
            return nil
        }

        let digestSource = "nobody\(apiPath)use\(payloadJSONString)md5forencrypt"
        let digest = md5Hex(digestSource)
        let saltedPayload = "\(apiPath)\(netEaseEapiPathSalt)\(payloadJSONString)\(netEaseEapiPathSalt)\(digest)"
        guard let encryptedPayload = aesECBHexEncrypt(saltedPayload, key: netEaseEapiAESKey) else {
            return nil
        }

        guard let url = URL(string: "https://\(netEaseHost)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(netEaseUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("", forHTTPHeaderField: "Referer")
        request.setValue("os=iPhone OS; appver=10.0.0; osver=16.2; channel=distribution; deviceId=\(netEaseDefaultDeviceID)", forHTTPHeaderField: "Cookie")
        request.httpBody = "params=\(encryptedPayload)".data(using: .utf8)

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard statusCode == 200 else { return nil }
        if let decryptedData = aesECBHexDecrypt(data, key: netEaseEapiAESKey),
           let json = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] {
            return json
        }

        if let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return rawJSON
        }
        return nil
    }

    private static func netEaseHeaderJSONString() -> String {
        let header: [String: String] = [
            "os": "iPhone OS",
            "appver": "10.0.0",
            "osver": "16.2",
            "channel": "distribution",
            "deviceId": netEaseDefaultDeviceID,
            "requestId": String(Int.random(in: 20_000_000...29_999_999))
        ]

        let data = try? JSONSerialization.data(withJSONObject: header, options: [])
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    private static func bestNetEaseTrackID(from response: [String: Any], title: String, artist: String, album: String, durationMs: Int) -> Int? {
        guard
            let result = response["result"] as? [String: Any],
            let songs = result["songs"] as? [[String: Any]]
        else {
            return nil
        }

        let normalizedTitle = normalizedLyricsMatchValue(title)
        let normalizedArtist = normalizedLyricsMatchValue(artist)
        let normalizedAlbum = normalizedLyricsMatchValue(album)

        let bestSong = songs.compactMap { song -> (id: Int, score: Int)? in
            guard let id = song["id"] as? Int else { return nil }

            let songTitle = normalizedLyricsMatchValue(song["name"] as? String)
            let albumName = normalizedLyricsMatchValue((song["album"] as? [String: Any])?["name"] as? String)
            let duration = song["dt"] as? Int
            let artists = (song["ar"] as? [[String: Any]]) ?? (song["artists"] as? [[String: Any]]) ?? []
            let artistNames = artists.compactMap { normalizedLyricsMatchValue($0["name"] as? String) }.joined(separator: " ")

            var score = 0

            if songTitle == normalizedTitle {
                score += 120
            } else if songTitle.contains(normalizedTitle) || normalizedTitle.contains(songTitle) {
                score += 70
            }

            if artistNames == normalizedArtist {
                score += 120
            } else if artistNames.contains(normalizedArtist) || normalizedArtist.contains(artistNames) {
                score += 70
            }

            if !normalizedAlbum.isEmpty {
                if albumName == normalizedAlbum {
                    score += 30
                } else if albumName.contains(normalizedAlbum) || normalizedAlbum.contains(albumName) {
                    score += 15
                }
            }

            if let duration, duration > 0, durationMs > 0 {
                score += max(0, 30 - abs((duration / 1000) - (durationMs / 1000)))
            }

            return (id, score)
        }
        .max(by: { $0.score < $1.score })

        guard let bestSong, bestSong.score >= 140 else { return nil }
        return bestSong.id
    }

    private static func stripTimedLyrics(_ lyrics: String) -> String {
        let stripped = lyrics.replacingOccurrences(
            of: #"\[[^\]]*\]|\([0-9]+,[0-9]+\)"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func md5Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func aesECBHexEncrypt(_ string: String, key: String) -> String? {
        guard let encrypted = aesECB(data: Data(string.utf8), key: Data(key.utf8), operation: CCOperation(kCCEncrypt)) else {
            return nil
        }
        return encrypted.map { String(format: "%02x", $0) }.joined()
    }

    private static func aesECBHexDecrypt(_ data: Data, key: String) -> Data? {
        let hexString = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cipherData = dataFromHexString(hexString) else { return nil }
        return aesECB(data: cipherData, key: Data(key.utf8), operation: CCOperation(kCCDecrypt))
    }

    private static func aesECB(data: Data, key: Data, operation: CCOperation) -> Data? {
        let outputLength = data.count + kCCBlockSizeAES128
        var outputData = Data(count: outputLength)
        var bytesProcessed: size_t = 0

        let status = outputData.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        dataBytes.baseAddress,
                        data.count,
                        outputBytes.baseAddress,
                        outputLength,
                        &bytesProcessed
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outputData.removeSubrange(bytesProcessed..<outputData.count)
        return outputData
    }

    private static func dataFromHexString(_ hex: String) -> Data? {
        let cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanHex.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: cleanHex.count / 2)
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = cleanHex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}

struct LRCLIBResult: Codable, Identifiable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LyricsSearchService: String, CaseIterable, Identifiable {
    case lrclib
    case musixmatch
    case netease

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lrclib:
            return "LRCLIB"
        case .musixmatch:
            return "Musixmatch"
        case .netease:
            return "NetEase"
        }
    }
}

struct LyricsSearchResult: Identifiable {
    let id: String
    let service: LyricsSearchService
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?
    let hasSyncedLyrics: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    let remoteID: Int?
}

extension SongMetadata {
    static let storefrontMap: [String: Int64] = [
        "us": 143441, "gb": 143444, "ca": 143455, "au": 143460,
        "de": 143443, "fr": 143442, "jp": 143462, "mx": 143468,
        "es": 143454, "it": 143450, "br": 143503, "kr": 143466,
        "cn": 143465, "in": 143467, "ru": 143469, "se": 143456,
        "nl": 143452, "no": 143457, "dk": 143458, "fi": 143447,
        "at": 143445, "ch": 143459, "be": 143446, "ie": 143449,
        "nz": 143461, "sg": 143464, "hk": 143463, "tw": 143470,
        "ar": 143505, "cl": 143483, "co": 143501, "pe": 143507,
        "ve": 143502, "ec": 143509, "cr": 143495, "pa": 143485,
        "do": 143508, "gt": 143504, "hn": 143510, "sv": 143506,
        "py": 143513, "uy": 143514, "bo": 143516, "ni": 143512,
        "pr": 143522, "ph": 143474, "th": 143475, "my": 143473,
        "id": 143476, "vn": 143471, "pk": 143477, "eg": 143516,
        "sa": 143479, "ae": 143481, "il": 143491, "za": 143472,
        "ng": 143561, "ke": 143529, "pt": 143453, "pl": 143478,
        "tr": 143480, "ua": 143492, "ro": 143487, "hu": 143482,
        "cz": 143489, "gr": 143448, "sk": 143496, "bg": 143526,
        "hr": 143494, "lt": 143520, "lv": 143519, "ee": 143518,
        "si": 143499, "lu": 143451, "mt": 143521
    ]
}

extension SongMetadata {
    static func searchLyrics(query: String, service: LyricsSearchService) async -> [LyricsSearchResult] {
        switch service {
        case .lrclib:
            return await searchLyricsFromLRCLIB(query: query)
        case .musixmatch:
            return await searchLyricsFromMusixMatch(query: query)
        case .netease:
            return await searchLyricsFromNetEase(query: query)
        }
    }

    static func resolveLyrics(for result: LyricsSearchResult, songTitle: String, songArtist: String) async -> String? {
        switch result.service {
        case .lrclib:
            let raw = result.syncedLyrics ?? result.plainLyrics ?? ""
            let cleaned = cleanLyrics(raw, title: songTitle, artist: songArtist)
            return cleaned.isEmpty ? nil : cleaned
        case .musixmatch:
            guard let remoteID = result.remoteID else { return nil }
            return await fetchLyricsFromMusixMatchTrackID(remoteID, title: songTitle, artist: songArtist)
        case .netease:
            guard let remoteID = result.remoteID else { return nil }
            return await fetchLyricsFromNetEaseTrackID(remoteID, title: songTitle, artist: songArtist)
        }
    }

    private static func searchLyricsFromLRCLIB(query: String) async -> [LyricsSearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://lrclib.net/api/search?q=\(encodedQuery)") else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("ByeTunes/2.5 (https://github.com/EduAlexxis/ByeTunes)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await SongMetadataNetworking.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard statusCode == 200 else { return [] }
            let results = try JSONDecoder().decode([LRCLIBResult].self, from: data)
            return results.map {
                LyricsSearchResult(
                    id: "lrclib-\($0.id)",
                    service: .lrclib,
                    title: $0.trackName ?? "Unknown Title",
                    artist: $0.artistName ?? "Unknown Artist",
                    album: $0.albumName,
                    durationMs: $0.duration.map { Int($0 * 1000) },
                    hasSyncedLyrics: $0.syncedLyrics?.isEmpty == false,
                    plainLyrics: $0.plainLyrics,
                    syncedLyrics: $0.syncedLyrics,
                    remoteID: $0.id
                )
            }
        } catch {
            Logger.shared.log("[SongMetadata] LRCLIB search failed: \(error)")
            return []
        }
    }

    private static func searchLyricsFromMusixMatch(query: String) async -> [LyricsSearchResult] {
        do {
            guard let response = try await performMusixMatchRequest(
                endpoint: "track.search",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "f_has_lyrics", value: "true"),
                    URLQueryItem(name: "page_size", value: "20"),
                    URLQueryItem(name: "page", value: "1")
                ]
            ) else {
                return []
            }

            guard
                let message = response["message"] as? [String: Any],
                let body = message["body"] as? [String: Any],
                let trackList = body["track_list"] as? [[String: Any]]
            else {
                return []
            }

            let results = trackList.compactMap { entry -> LyricsSearchResult? in
                guard
                    let track = entry["track"] as? [String: Any],
                    let trackID = track["track_id"] as? Int
                else {
                    return nil
                }

                return LyricsSearchResult(
                    id: "musixmatch-\(trackID)",
                    service: .musixmatch,
                    title: (track["track_name"] as? String) ?? "Unknown Title",
                    artist: (track["artist_name"] as? String) ?? "Unknown Artist",
                    album: track["album_name"] as? String,
                    durationMs: (track["track_length"] as? Int).map { $0 * 1000 },
                    hasSyncedLyrics: (track["has_richsync"] as? Int == 1) || (track["has_subtitles"] as? Int == 1),
                    plainLyrics: nil,
                    syncedLyrics: nil,
                    remoteID: trackID
                )
            }
            return results
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch search failed: \(error)")
            return []
        }
    }

    private static func searchLyricsFromNetEase(query: String) async -> [LyricsSearchResult] {
        do {
            guard let response = try await performNetEaseEapiRequest(
                path: "/eapi/cloudsearch/pc",
                payload: [
                    "s": query,
                    "type": "1",
                    "limit": "20",
                    "offset": "0"
                ]
            ) else {
                return []
            }

            guard
                let result = response["result"] as? [String: Any],
                let songs = result["songs"] as? [[String: Any]]
            else {
                return []
            }

            let results = songs.compactMap { song -> LyricsSearchResult? in
                guard let id = song["id"] as? Int else { return nil }
                let artists = (song["ar"] as? [[String: Any]]) ?? (song["artists"] as? [[String: Any]]) ?? []
                let artistNames = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                let albumName = (song["al"] as? [String: Any])?["name"] as? String ?? (song["album"] as? [String: Any])?["name"] as? String

                return LyricsSearchResult(
                    id: "netease-\(id)",
                    service: .netease,
                    title: (song["name"] as? String) ?? "Unknown Title",
                    artist: artistNames.isEmpty ? "Unknown Artist" : artistNames,
                    album: albumName,
                    durationMs: song["dt"] as? Int,
                    hasSyncedLyrics: true,
                    plainLyrics: nil,
                    syncedLyrics: nil,
                    remoteID: id
                )
            }
            return results
        } catch {
            Logger.shared.log("[SongMetadata] NetEase search failed: \(error)")
            return []
        }
    }

    private static func fetchLyricsFromMusixMatchTrackID(_ trackID: Int, title: String, artist: String) async -> String? {
        do {
            guard let lyricsResponse = try await performMusixMatchRequest(
                endpoint: "track.lyrics.get",
                queryItems: [URLQueryItem(name: "track_id", value: String(trackID))]
            ) else {
                return nil
            }

            guard
                let message = lyricsResponse["message"] as? [String: Any],
                let body = message["body"] as? [String: Any],
                let lyrics = body["lyrics"] as? [String: Any],
                let lyricsBody = lyrics["lyrics_body"] as? String
            else {
                return nil
            }

            let cleaned = cleanLyrics(stripMusixMatchFooter(from: lyricsBody), title: title, artist: artist)
            if !cleaned.isEmpty {
                Logger.shared.log("[SongMetadata] Found lyrics from Musixmatch")
            }
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch lyrics resolve failed: \(error)")
            return nil
        }
    }

    private static func fetchLyricsFromNetEaseTrackID(_ trackID: Int, title: String, artist: String) async -> String? {
        do {
            guard let lyricsResponse = try await performNetEaseEapiRequest(
                path: "/eapi/song/lyric/v1",
                payload: [
                    "id": String(trackID),
                    "cp": false,
                    "lv": 0,
                    "tv": 0,
                    "rv": 0,
                    "kv": 0,
                    "yv": 0,
                    "ytv": 0,
                    "yrv": 0
                ]
            ) else {
                return nil
            }

            let lyricCandidates = [
                ((lyricsResponse["lrc"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["klyric"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["yrc"] as? [String: Any])?["lyric"] as? String)
            ]

            for candidate in lyricCandidates {
                guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let cleaned = cleanLyrics(stripTimedLyrics(candidate), title: title, artist: artist)
                if !cleaned.isEmpty {
                    Logger.shared.log("[SongMetadata] Found lyrics from NetEase")
                    return cleaned
                }
            }
            return nil
        } catch {
            Logger.shared.log("[SongMetadata] NetEase lyrics resolve failed: \(error)")
            return nil
        }
    }

    static func applyAppleMusicMatch(_ match: AppleMusicAPI.AppleMusicSong, to song: SongMetadata) async -> SongMetadata {
        var enrichedSong = song
        let amsMatch = match
        
        enrichedSong.title = amsMatch.attributes.name
        enrichedSong.artist = amsMatch.attributes.artistName
        if let alb = amsMatch.attributes.albumName { enrichedSong.album = alb }
        if let trackNumber = amsMatch.attributes.trackNumber {
            enrichedSong.trackNumber = trackNumber
        }
        if let discNumber = amsMatch.attributes.discNumber {
            enrichedSong.discNumber = discNumber
        }
        if let durationInMillis = amsMatch.attributes.durationInMillis, durationInMillis > 0 {
            enrichedSong.durationMs = durationInMillis
        }
        enrichedSong.appleMusicAudioTraits = amsMatch.attributes.audioTraits ?? []
        enrichedSong.isAppleDigitalMaster = amsMatch.attributes.isAppleDigitalMaster ?? false
        enrichedSong.isMasteredForItunes = amsMatch.attributes.isMasteredForItunes ?? false
        
        if let songIdInt = Int64(amsMatch.id) {
            enrichedSong.storeId = songIdInt
        }
        
        if let dateStr = amsMatch.attributes.releaseDate {
            if let yearInt = Int(dateStr.prefix(4)) {
                enrichedSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(dateStr) {
                enrichedSong.releaseDate = epoch
            }
        } else if let firstAlbum = amsMatch.relationships?.albums?.data.first,
                  let albDateStr = firstAlbum.attributes.releaseDate {
            if let yearInt = Int(albDateStr.prefix(4)) {
                enrichedSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(albDateStr) {
                enrichedSong.releaseDate = epoch
            }
        }
        
        if let isrc = amsMatch.attributes.isrc, !isrc.isEmpty {
            enrichedSong.xid = isrc
        }
        
        if let rating = amsMatch.attributes.contentRating {
            enrichedSong.explicitRating = (rating == "explicit") ? 1 : (rating == "clean" ? 2 : 0)
        }
        
        if let firstAlbum = amsMatch.relationships?.albums?.data.first,
           let cprt = firstAlbum.attributes.copyright {
            enrichedSong.copyright = cprt
        }
        
        if let firstArtist = amsMatch.relationships?.artists?.data.first,
           let artistIdInt = Int64(firstArtist.id) {
            enrichedSong.artistId = artistIdInt
        }
        
        if let firstComposer = amsMatch.relationships?.composers?.data.first,
           let composerIdInt = Int64(firstComposer.id) {
            enrichedSong.composerId = composerIdInt
        }
        
        if let firstGenre = amsMatch.relationships?.genres?.data.first,
           let genreIdInt = Int64(firstGenre.id) {
            enrichedSong.genreStoreId = genreIdInt
        }
        
        if let firstGenreName = amsMatch.attributes.genreNames?.first {
            enrichedSong.genre = canonicalGenre(firstGenreName)
        }
        
        if let firstAlbum = amsMatch.relationships?.albums?.data.first,
           let albumIdInt = Int64(firstAlbum.id) {
            enrichedSong.playlistId = albumIdInt
        }
        
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        enrichedSong.storefrontId = SongMetadata.storefrontMap[region] ?? 143441
        
        if let artworkUrl = amsMatch.attributes.artwork?.artworkURL() {
            if let (data, _) = try? await SongMetadataNetworking.data(from: artworkUrl) {
                enrichedSong.artworkData = data
            }
        }
        enrichedSong.appleMusicArtworkColors = amsMatch.attributes.artwork?.colors

        enrichedSong.genre = canonicalGenre(enrichedSong.genre)
        enrichedSong.richAppleMetadataFetched = true
        return enrichedSong
    }
}

struct iTunesSearchResult: Codable {
    let results: [iTunesSong]
}

struct iTunesSong: Codable, Identifiable {
    var id: Int { trackId ?? Int.random(in: 0...Int.max) }
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackViewUrl: String?
    let previewUrl: String?
    let primaryGenreName: String?
    let artistId: Int?
    let collectionId: Int?
    let releaseDate: String?
    let artworkUrl100: String?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
}



extension SongMetadata {
    
    
    static func searchiTunes(query: String, limit: Int = 10) async -> [iTunesSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion") ?? "US"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let boundedLimit = min(max(limit, 1), 200)
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=\(boundedLimit)&country=\(region)") else {
            return []
        }
        
        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
            return result.results
        } catch {
            Logger.shared.log("[SongMetadata] iTunes search failed: \(error)")
            return []
        }
    }
    
    
    static func applyiTunesMatch(_ match: iTunesSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        if let t = match.trackName { newSong.title = t }
        if let a = match.artistName { newSong.artist = a }
        if let al = match.collectionName { newSong.album = al }
        if let g = match.primaryGenreName { newSong.genre = canonicalGenre(g) }
        if let aId = match.artistId { newSong.artistId = Int64(aId) }
        if let cId = match.collectionId { newSong.playlistId = Int64(cId) }
        if let tId = match.trackId { newSong.storeId = Int64(tId) }
        newSong.storefrontId = 143441
        
        newSong.trackNumber = match.trackNumber
        newSong.trackCount = match.trackCount
        newSong.discNumber = match.discNumber
        newSong.discCount = match.discCount
        
        if let dateStr = match.releaseDate {
            if let yearInt = Int(dateStr.prefix(4)) {
                newSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(dateStr) {
                newSong.releaseDate = epoch
            }
        }
        
        
        if let artUrl = match.artworkUrl100 {
            
            let highResUrlString = artUrl.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
            if let highResUrl = URL(string: highResUrlString),
               let (artData, _) = try? await SongMetadataNetworking.data(from: highResUrl) {
                newSong.artworkData = artData
                Logger.shared.log("[SongMetadata] Updated artwork with iTunes High-Res version: \(artData.count) bytes")
            }
        }
        
        newSong.genre = canonicalGenre(newSong.genre)
        return newSong
    }

    
    static func enrichWithiTunesMetadata(_ song: SongMetadata) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Searching iTunes for: \(song.artist) - \(song.title)")
        
        let query = "\(song.artist) \(song.title)"
        let results = await searchiTunes(query: query)
        
        
        var bestMatch: iTunesSong?
        
        for match in results {
            guard let remoteArtist = match.artistName,
                  let remoteTitle = match.trackName else { continue }
            
            
            if song.artist != "Unknown Artist" {
                let localNorm = song.artist.lowercased().filter { !$0.isPunctuation }
                let remoteNorm = remoteArtist.lowercased().filter { !$0.isPunctuation }
                
                
                if localNorm.contains(remoteNorm) || remoteNorm.contains(localNorm) {
                    bestMatch = match
                    Logger.shared.log("[SongMetadata] ✓ Validated match: \(remoteTitle) by \(remoteArtist)")
                    break 
                } else {
                    Logger.shared.log("[SongMetadata] x Rejected match: \(remoteTitle) by \(remoteArtist) (Artist mismatch)")
                }
            } else {
                
                bestMatch = match
                break
            }
        }
        
        guard let match = bestMatch else {
            Logger.shared.log("[SongMetadata] No valid iTunes match found after filtering.")
            return song
        }
        
        var enrichedSong = await applyiTunesMatch(match, to: song)
        
        if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
            enrichedSong = await matchAppleMusicMetadata(enrichedSong)
        }
        
        return enrichedSong
    }
    
    static func enrichWithAppleMusicMetadata(_ song: SongMetadata) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Performing full Apple Music fetch for: \(song.artist) - \(song.title)")
        let query = "\(song.artist) \(song.title)"

        if let amsMatch = await AppleMusicAPI.shared.searchSong(query: query, albumHint: song.album, titleHint: song.title) {
            let enriched = await applyAppleMusicMatch(amsMatch, to: song)
            Logger.shared.log("[SongMetadata] ✓ Apple Music match (\(enriched.appleMetadataMatchTier)): \(enriched.title) (\(enriched.storeId))")
            return enriched
        }

        Logger.shared.log("[SongMetadata] Apple Music fetch returned no match for: \(song.artist) - \(song.title)")
        return song
    }

    static func enrichWithExactAppleMusicTrack(_ song: SongMetadata, trackID: String, urlHint: String? = nil) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Performing exact Apple Music fetch for track ID: \(trackID)")

        guard let amsMatch = await AppleMusicAPI.shared.fetchSong(id: trackID, urlHint: urlHint) else {
            Logger.shared.log("[SongMetadata] Exact Apple Music fetch failed for track ID: \(trackID)")
            return song
        }

        let enriched = await applyAppleMusicMatch(amsMatch, to: song)
        Logger.shared.log("[SongMetadata] ✓ Exact Apple Music match (\(enriched.appleMetadataMatchTier)): \(enriched.title) (\(enriched.storeId))")
        return enriched
    }
    
    static func matchAppleMusicMetadata(_ song: SongMetadata) async -> SongMetadata {
        let query = "\(song.artist) \(song.title)"
        Logger.shared.log("[SongMetadata] 🔍 Shadow-searching Apple Music for rich metadata: '\(query)'")

        if let amsMatch = await AppleMusicAPI.shared.searchSong(query: query, albumHint: song.album, titleHint: song.title) {
            Logger.shared.log("[SongMetadata] ✨ Found Apple Music Server Match: \(amsMatch.attributes.name) by \(amsMatch.attributes.artistName) (ID: \(amsMatch.id))")
            let enriched = await applyAppleMusicMatch(amsMatch, to: song)
            Logger.shared.log("[SongMetadata] ✨ Rich Apple metadata tier: \(enriched.appleMetadataMatchTier) for \(enriched.title)")
            return enriched
        } else {
            Logger.shared.log("[SongMetadata] ⚠️ No rich metadata match found on Apple Music for: '\(query)'")
        }
        
        return song
    }

    static func enrichDownloadedSong(_ initialSong: SongMetadata, sourceTrack: DownloadTrack? = nil) async -> SongMetadata {
        var song = initialSong

        if let sourceTrack {
            song = await enrichWithExactAppleMusicTrack(song, trackID: sourceTrack.id, urlHint: sourceTrack.sourceURL)
            if song.storeId == 0 {
                song = await enrichWithAppleMusicMetadata(song)
            }
        } else {
            let metadataSource = UserDefaults.standard.string(forKey: "metadataSource") ?? "apple"
            let autofetch = UserDefaults.standard.bool(forKey: "autofetchMetadata")

            if metadataSource == "apple" && autofetch {
                song = await enrichWithAppleMusicMetadata(song)
            } else if metadataSource == "itunes" && autofetch {
                song = await enrichWithiTunesMetadata(song)
            } else if metadataSource == "deezer" && autofetch {
                song = await enrichWithDeezerMetadata(song)
            } else if metadataSource == "local" && autofetch {
                if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
                    song = await matchAppleMusicMetadata(song)
                }
            }
        }

        let fetchLyricsEnabled = UserDefaults.standard.bool(forKey: "fetchLyrics")
        let appleSubscriptionLyrics = UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")
        if fetchLyricsEnabled && !appleSubscriptionLyrics && (song.lyrics == nil || song.lyrics?.isEmpty == true) {
            if let fetchedLyrics = await SongMetadata.fetchLyrics(
                title: song.title,
                artist: song.artist,
                album: song.album,
                durationMs: song.durationMs
            ) {
                song.lyrics = fetchedLyrics
            }
        }

        return song
    }
}



struct DeezerSearchResult: Codable {
    let data: [DeezerSong]
}

struct DeezerSong: Codable, Identifiable {
    let id: Int
    let title: String
    let link: String?
    let preview: String?
    let artist: DeezerReference
    let album: DeezerAlbumReference
    let duration: Int
    let explicit_lyrics: Bool?
    let isrc: String?
    let rank: Int?
    
    
    var trackName: String { title }
    var artistName: String { artist.name }
    var albumName: String { album.title }
    var artworkUrl: String { album.cover_xl }
}

struct DeezerReference: Codable {
    let id: Int
    let name: String
}

struct DeezerAlbumReference: Codable {
    let id: Int
    let title: String
    let cover_xl: String
}

struct DeezerTrackDetails: Codable {
    let track_position: Int?
    let disk_number: Int?
    let release_date: String?
}

struct DeezerTracksWrapper: Codable {
    let data: [DeezerSong]
}

struct DeezerAlbumDetail: Codable {
    let id: Int
    let title: String
    let cover_xl: String
    let artist: DeezerReference
    let tracks: DeezerTracksWrapper
}

struct DeezerPlaylistDetail: Codable {
    let id: Int
    let title: String
    let picture_xl: String
    let creator: DeezerReference
    let tracks: DeezerTracksWrapper
}

struct DeezerArtistDetail: Codable {
    let id: Int
    let name: String
    let picture_xl: String
}

struct DeezerArtistTopTracksResult: Codable {
    let data: [DeezerSong]
}

struct DeezerArtistAlbumSummary: Codable {
    let id: Int
    let title: String
    let cover_xl: String
}

struct DeezerArtistAlbumsResult: Codable {
    let data: [DeezerArtistAlbumSummary]
}



extension SongMetadata {
    
    
    static func searchDeezer(query: String, limit: Int = 10, index: Int = 0) async -> [DeezerSong] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let boundedLimit = min(max(limit, 1), 100)
        let boundedIndex = max(index, 0)
        guard let url = URL(string: "https://api.deezer.com/search?q=\(encodedQuery)&limit=\(boundedLimit)&index=\(boundedIndex)") else {
            return []
        }
        
        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            let result = try JSONDecoder().decode(DeezerSearchResult.self, from: data)
            return result.data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer search failed: \(error)")
            return []
        }
    }
    
    static func fetchDeezerTrackDetails(id: Int) async -> DeezerTrackDetails? {
        guard let url = URL(string: "https://api.deezer.com/track/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerTrackDetails.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Failed to fetch Deezer track details: \(error)")
            return nil
        }
    }

    static func fetchDeezerTrack(id: Int) async -> DeezerSong? {
        guard let url = URL(string: "https://api.deezer.com/track/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerSong.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer track fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerAlbum(id: Int) async -> DeezerAlbumDetail? {
        guard let url = URL(string: "https://api.deezer.com/album/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerAlbumDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer album fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerPlaylist(id: Int) async -> DeezerPlaylistDetail? {
        guard let url = URL(string: "https://api.deezer.com/playlist/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerPlaylistDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer playlist fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerArtist(id: Int) async -> DeezerArtistDetail? {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerArtistTopTracks(id: Int, limit: Int = 100) async -> [DeezerSong] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)/top?limit=\(limit)") else { return [] }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistTopTracksResult.self, from: data).data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist top tracks fetch failed for \(id): \(error)")
            return []
        }
    }

    static func fetchDeezerArtistAlbums(id: Int, limit: Int = 100) async -> [DeezerArtistAlbumSummary] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)/albums?limit=\(limit)") else { return [] }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistAlbumsResult.self, from: data).data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist albums fetch failed for \(id): \(error)")
            return []
        }
    }

    static func fetchDeezerTrackByISRC(_ isrc: String) async -> DeezerSong? {
        let trimmed = isrc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        guard let url = URL(string: "https://api.deezer.com/track/isrc:\(encoded)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerSong.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer ISRC lookup failed for \(trimmed): \(error)")
            return nil
        }
    }
    
    
    static func applyDeezerMatch(_ match: DeezerSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        newSong.title = match.title
        newSong.artist = match.artist.name
        newSong.album = match.album.title
        
        if let explicit = match.explicit_lyrics {
            newSong.explicitRating = explicit ? 1 : 0
        }
        
        newSong.durationMs = match.duration * 1000
        
        
        if let details = await fetchDeezerTrackDetails(id: match.id) {
            newSong.trackNumber = details.track_position
            newSong.discNumber = details.disk_number
            
            if let releaseDate = details.release_date {
                
                let components = releaseDate.split(separator: "-")
                if let yearStr = components.first, let yearInt = Int(yearStr) {
                    newSong.year = yearInt
                }
            }
            Logger.shared.log("[SongMetadata] Enhanced with Deezer details: Trk \(details.track_position ?? 0), Disc \(details.disk_number ?? 0), Year \(newSong.year)")
        }
        
        
        if let artUrl = URL(string: match.album.cover_xl),
           let (artData, _) = try? await SongMetadataNetworking.data(from: artUrl) {
            newSong.artworkData = artData
            Logger.shared.log("[SongMetadata] Updated artwork with Deezer High-Res version: \(artData.count) bytes")
        }
        
        return newSong
    }
    
    static func enrichWithDeezerMetadata(_ song: SongMetadata) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Searching Deezer for: \(song.artist) - \(song.title)")
        let query = "\(song.artist) \(song.title)"
        let results = await searchDeezer(query: query)
        
        var enrichedSong = song
        if let firstMatch = results.first {
             Logger.shared.log("[SongMetadata] ✓ Deezer match: \(firstMatch.title) by \(firstMatch.artist.name)")
             enrichedSong = await applyDeezerMatch(firstMatch, to: song)
        }
        
        if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
            enrichedSong = await matchAppleMusicMetadata(enrichedSong)
        }
        
        return enrichedSong
    }
}
// MARK: - Apple Music API
actor AppleMusicAPI {
    static let shared = AppleMusicAPI()
    private let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    
    struct AppleMusicSearchResponse: Codable {
        let results: AppleMusicSearchResults?
        let errors: [AppleMusicAPIErrorPayload]?
    }
    
    struct AppleMusicSearchResults: Codable {
        let songs: AppleMusicSongsPage?
    }
    
    struct AppleMusicSongsPage: Codable {
        let data: [AppleMusicSong]
    }

    struct AppleMusicAPIErrorPayload: Codable {
        let id: String?
        let title: String?
        let detail: String?
        let status: String?
        let code: String?
    }
    
    struct AppleMusicSong: Codable, Identifiable {
        let id: String
        let attributes: AppleMusicSongAttributes
        let relationships: AppleMusicSongRelationships?
    }
    
    struct AppleMusicSongAttributes: Codable {
        let name: String
        let artistName: String
        let albumName: String?
        let url: String?
        let audioTraits: [String]?
        let genreNames: [String]?
        let isrc: String?
        let contentRating: String?
        let releaseDate: String?
        let trackNumber: Int?
        let discNumber: Int?
        let durationInMillis: Int?
        let isAppleDigitalMaster: Bool?
        let isMasteredForItunes: Bool?
        let artwork: AppleMusicArtwork?
    }
    
    struct AppleMusicArtwork: Codable {
        let width: Int
        let height: Int
        let url: String
        let bgColor: String?
        let textColor1: String?
        let textColor2: String?
        let textColor3: String?
        let textColor4: String?
        
        var colors: AppleMusicArtworkColors? {
            guard let bgColor else {
                return nil
            }
            return AppleMusicArtworkColors(
                backgroundColor: bgColor,
                primaryTextColor: textColor1 ?? "FFFFFF",
                secondaryTextColor: textColor2 ?? textColor1 ?? "FFFFFF",
                tertiaryTextColor: textColor3 ?? textColor2 ?? textColor1 ?? "CCCCCC"
            )
        }
        
        func artworkURL(width w: Int = 1000, height h: Int = 1000) -> URL? {
            let processed = url.replacingOccurrences(of: "{w}", with: "\(w)")
                             .replacingOccurrences(of: "{h}", with: "\(h)")
                             .replacingOccurrences(of: "{c}", with: "bb")
                             .replacingOccurrences(of: "{f}", with: "jpg")
            return URL(string: processed)
        }
    }
    
    struct AppleMusicSongRelationships: Codable {
        let albums: AppleMusicAlbumsPage?
        let artists: AppleMusicDataPage?
        let composers: AppleMusicDataPage?
        let genres: AppleMusicDataPage?
    }
    
    struct AppleMusicDataPage: Codable {
        let data: [AppleMusicReference]
    }
    
    struct AppleMusicReference: Codable {
        let id: String
    }
    
    struct AppleMusicAlbumsPage: Codable {
        let data: [AppleMusicAlbum]
    }
    
    struct AppleMusicAlbum: Codable {
        let id: String
        let attributes: AppleMusicAlbumAttributes
    }
    
    struct AppleMusicAlbumAttributes: Codable {
        let copyright: String?
        let releaseDate: String?
    }

    struct PublicCatalogAlbum: Identifiable {
        let id: String
        let name: String
        let artistName: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    struct PublicCatalogPlaylist: Identifiable {
        let id: String
        let name: String
        let curatorName: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    struct PublicCatalogArtist: Identifiable {
        let id: String
        let name: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    private struct PublicSearchPageEnvelope: Decodable {
        let data: [PublicSearchPageNode]
    }

    private struct PublicSearchPageNode: Decodable {
        let data: PublicSearchPageData
    }

    private struct PublicSearchPageData: Decodable {
        let sections: [PublicSearchSection]
    }

    private struct PublicSearchSection: Decodable {
        let header: PublicSearchSectionHeader?
        let items: [PublicSearchItem]?
    }

    private struct PublicSearchSectionHeader: Decodable {
        let item: PublicSearchHeaderItem?
    }

    private struct PublicSearchHeaderItem: Decodable {
        let titleLink: PublicSearchTextLink?
    }

    private struct PublicSearchItem: Decodable {
        let title: String?
        let titleLinks: [PublicSearchTextLink]?
        let subtitle: String?
        let subtitleLinks: [PublicSearchTextLink]?
        let artwork: PublicSearchArtworkWrapper?
        let contentDescriptor: PublicSearchContentDescriptor?
        let segue: PublicSearchSegue?
        let duration: Int?
        let showExplicitBadge: Bool?
    }

    private struct PublicSearchTextLink: Decodable {
        let title: String?
        let segue: PublicSearchSegue?
    }

    private struct PublicSearchArtworkWrapper: Decodable {
        let dictionary: PublicSearchArtworkDictionary?
    }

    private struct PublicSearchArtworkDictionary: Decodable {
        let width: Int?
        let height: Int?
        let url: String?
        let bgColor: String?
        let textColor1: String?
        let textColor2: String?
        let textColor3: String?
        let textColor4: String?
    }

    private struct PublicSearchContentDescriptor: Decodable {
        let identifiers: PublicSearchIdentifiers?
        let url: String?
    }

    private struct PublicSearchIdentifiers: Decodable {
        let storeAdamID: String?
    }

    private struct PublicSearchSegue: Decodable {
        let subactions: [PublicSearchSubaction]?
        let destination: PublicSearchDestination?
    }

    private struct PublicSearchSubaction: Decodable {
        let destination: PublicSearchDestination?
    }

    private struct PublicSearchDestination: Decodable {
        let contentDescriptor: PublicSearchContentDescriptor?
        let prominentItemIdentifier: String?
    }

    private struct PublicAlbumPageEnvelope: Decodable {
        let data: [PublicAlbumPageNode]
    }

    private struct PublicAlbumPageNode: Decodable {
        let intent: PublicAlbumPageIntent?
        let data: PublicAlbumPageData
    }

    private struct PublicAlbumPageIntent: Decodable {
        let contentDescriptor: PublicSearchContentDescriptor?
        let prominentItemIdentifier: String?
    }

    private struct PublicAlbumPageData: Decodable {
        let sections: [PublicAlbumPageSection]
    }

    private struct PublicAlbumPageSection: Decodable {
        let id: String?
        let itemKind: String?
        let items: [PublicAlbumPageItem]?
    }

    private struct PublicAlbumPageItem: Decodable {
        let title: String?
        let tertiaryLinks: [PublicSearchTextLink]?
        let subtitleLinks: [PublicSearchTextLink]?
        let quaternaryTitle: String?
        let artwork: PublicSearchArtworkWrapper?
        let tallArtwork: PublicSearchArtworkWrapper?
        let uberArtwork: PublicSearchArtworkWrapper?
        let audioBadges: PublicAlbumAudioBadges?
        let contentDescriptor: PublicSearchContentDescriptor?
        let trackNumber: Int?
        let duration: Int?
        let showExplicitBadge: Bool?
        let composer: String?
        let discNumber: Int?
        let artistName: String?
        let previewUrl: String?
        let isProminent: Bool?
    }

    private struct PublicAlbumAudioBadges: Decodable {
        let dolbyAtmos: Bool?
        let lossless: Bool?
        let hiResLossless: Bool?
        let digitalMaster: Bool?
    }

    func searchSongs(query: String, limit: Int = 5, offset: Int = 0) async -> [AppleMusicSong] {
        return await searchSongsViaPublicSearch(query: query, limit: limit, offset: offset).songs
    }

    func searchSongsWithAvailability(query: String, limit: Int, offset: Int) async -> (songs: [AppleMusicSong], hasMore: Bool) {
        return await searchSongsViaPublicSearch(query: query, limit: limit, offset: offset)
    }

    func searchSong(query: String, albumHint: String? = nil, titleHint: String? = nil) async -> AppleMusicSong? {
        let hasAlbumHint = albumHint.map { !$0.isEmpty && $0 != "Unknown Album" } ?? false
        let hasTitleHint = titleHint.map { !Self.titleKey($0).isEmpty } ?? false
        let candidates: [AppleMusicSong]
        if hasTitleHint {
            candidates = await searchSongs(query: query, limit: 10, offset: 0)
        } else if hasAlbumHint {
            candidates = await searchSongs(query: query, limit: 5, offset: 0)
        } else {
            candidates = await searchSongs(query: query, limit: 1, offset: 0)
        }

        guard let song = Self.bestMatch(for: candidates, albumHint: albumHint, titleHint: titleHint) else {
            return nil
        }

        if song.attributes.audioTraits != nil || song.attributes.trackNumber != nil {
            return song
        }

        if let detailed = await fetchSongViaPublicPage(urlString: song.attributes.url, expectedTrackID: song.id) {
            return detailed
        }

        return song
    }

    private static func titleKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func bestMatch(for candidates: [AppleMusicSong], albumHint: String?, titleHint: String?) -> AppleMusicSong? {
        let hintKey = titleHint.map { titleKey($0) } ?? ""
        var pool = candidates

        if !hintKey.isEmpty {
            let exact = candidates.filter { titleKey($0.attributes.name) == hintKey }
            if !exact.isEmpty {
                pool = exact
            } else {
                let loose = candidates.filter { candidate in
                    let key = titleKey(candidate.attributes.name)
                    return !key.isEmpty && (key.contains(hintKey) || hintKey.contains(key))
                }
                guard !loose.isEmpty else { return nil }
                pool = loose
            }
        }

        guard let albumHint, !albumHint.isEmpty, albumHint != "Unknown Album" else {
            return pool.first
        }

        let normalizedHint = albumHint.lowercased().filter { !$0.isPunctuation }
        if let albumMatch = pool.first(where: { candidate in
            guard let candidateAlbum = candidate.attributes.albumName else { return false }
            let normalizedCandidate = candidateAlbum.lowercased().filter { !$0.isPunctuation }
            return normalizedCandidate.contains(normalizedHint) || normalizedHint.contains(normalizedCandidate)
        }) {
            return albumMatch
        }

        return pool.first
    }

    func fetchSong(id: String, urlHint: String? = nil) async -> AppleMusicSong? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let publicURL = urlHint ?? "https://music.apple.com/\(region)/song/\(id)"
        if let publicSong = await fetchSongViaPublicPage(urlString: publicURL, expectedTrackID: id) {
            return publicSong
        }
        return nil
    }

    func searchAlbumsPublic(query: String, limit: Int = 15, offset: Int = 0) async -> [PublicCatalogAlbum] {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Albums")
        guard offset < sectionItems.count else { return [] }
        let slice = sectionItems.dropFirst(offset).prefix(limit)
        return slice.compactMap { item in
            guard let id = item.contentDescriptor?.identifiers?.storeAdamID,
                  let url = item.contentDescriptor?.url,
                  let name = item.titleLinks?.first?.title ?? item.title else {
                return nil
            }
            let artistName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Unknown Artist"
            return PublicCatalogAlbum(
                id: id,
                name: name,
                artistName: artistName,
                url: url,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            )
        }
    }

    func searchPlaylistsPublic(query: String, limit: Int = 15, offset: Int = 0) async -> [PublicCatalogPlaylist] {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Playlists")
        guard offset < sectionItems.count else { return [] }
        let slice = sectionItems.dropFirst(offset).prefix(limit)
        return slice.compactMap { item in
            guard let id = item.contentDescriptor?.identifiers?.storeAdamID,
                  let url = item.contentDescriptor?.url,
                  let name = item.titleLinks?.first?.title ?? item.title else {
                return nil
            }
            let curatorName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Apple Music Playlist"
            return PublicCatalogPlaylist(
                id: id,
                name: name,
                curatorName: curatorName,
                url: url,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            )
        }
    }

    func fetchAlbumPublic(id: String, urlHint: String? = nil) async -> PublicCatalogAlbum? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/album/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let albumID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let artistName = headerItem?.subtitleLinks?.first?.title ?? "Unknown Artist"
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)

        return PublicCatalogAlbum(
            id: albumID,
            name: name,
            artistName: artistName,
            url: url,
            artwork: mapPublicArtwork(headerItem?.artwork?.dictionary)
        )
    }

    func fetchAlbumTracksPublic(id: String, urlHint: String? = nil) async -> [AppleMusicSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/album/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return []
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let albumID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id
        let albumName = headerItem?.title ?? "Unknown Album"
        let defaultArtist = headerItem?.subtitleLinks?.first?.title ?? "Unknown Artist"
        let artistID = headerItem?.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let releaseDate = parsePublicReleaseDate(headerItem?.quaternaryTitle)
        let fallbackArtwork = mapPublicArtwork(headerItem?.artwork?.dictionary)
        let audioTraits = traits(from: headerItem?.audioBadges)

        let trackItems = node.data.sections
            .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
            .items ?? []

        return trackItems.compactMap { item in
            guard let trackID = item.contentDescriptor?.identifiers?.storeAdamID,
                  let title = item.title else {
                return nil
            }

            let artistName = item.artistName ?? defaultArtist
            let artwork = mapPublicArtwork(item.artwork?.dictionary) ?? fallbackArtwork
            let relationships = AppleMusicSongRelationships(
                albums: AppleMusicAlbumsPage(data: [
                    AppleMusicAlbum(
                        id: albumID,
                        attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: releaseDate)
                    )
                ]),
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            return AppleMusicSong(
                id: trackID,
                attributes: AppleMusicSongAttributes(
                    name: title,
                    artistName: artistName,
                    albumName: albumName,
                    url: item.contentDescriptor?.url,
                    audioTraits: audioTraits,
                    genreNames: parsePublicGenres(headerItem?.quaternaryTitle),
                    isrc: nil,
                    contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                    releaseDate: releaseDate,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    durationInMillis: item.duration,
                    isAppleDigitalMaster: headerItem?.audioBadges?.digitalMaster ?? false,
                    isMasteredForItunes: headerItem?.audioBadges?.digitalMaster ?? false,
                    artwork: artwork
                ),
                relationships: relationships
            )
        }
    }

    func fetchPlaylistPublic(id: String, urlHint: String? = nil) async -> PublicCatalogPlaylist? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/playlist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let playlistID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let curatorName = headerItem?.subtitleLinks?.first?.title ?? "Apple Music Playlist"
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let artwork = mapPublicArtwork(headerItem?.tallArtwork?.dictionary) ?? mapPublicArtwork(headerItem?.artwork?.dictionary)

        return PublicCatalogPlaylist(
            id: playlistID,
            name: name,
            curatorName: curatorName,
            url: url,
            artwork: artwork
        )
    }

    func fetchPlaylistTracksPublic(id: String, urlHint: String? = nil) async -> [AppleMusicSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/playlist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return []
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let playlistURL = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let fallbackArtwork = mapPublicArtwork(headerItem?.artwork?.dictionary)

        let trackItems = node.data.sections
            .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
            .items ?? []

        return trackItems.compactMap { item in
            guard let trackID = item.contentDescriptor?.identifiers?.storeAdamID,
                  let title = item.title else {
                return nil
            }

            let artistName = item.subtitleLinks?.first?.title ?? item.artistName ?? "Unknown Artist"
            let artistID = item.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let albumName = item.tertiaryLinks?.first?.title
            let albumID = item.tertiaryLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let artwork = mapPublicArtwork(item.artwork?.dictionary) ?? fallbackArtwork
            let audioTraits = traits(from: item.audioBadges)

            let relationships = AppleMusicSongRelationships(
                albums: albumID.map {
                    AppleMusicAlbumsPage(data: [
                        AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: nil))
                    ])
                },
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            return AppleMusicSong(
                id: trackID,
                attributes: AppleMusicSongAttributes(
                    name: title,
                    artistName: artistName,
                    albumName: albumName,
                    url: item.contentDescriptor?.url ?? playlistURL,
                    audioTraits: audioTraits,
                    genreNames: nil,
                    isrc: nil,
                    contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                    releaseDate: nil,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    durationInMillis: item.duration,
                    isAppleDigitalMaster: item.audioBadges?.digitalMaster,
                    isMasteredForItunes: item.audioBadges?.digitalMaster,
                    artwork: artwork
                ),
                relationships: relationships
            )
        }
    }

    func fetchArtistPublic(id: String, urlHint: String? = nil) async -> PublicCatalogArtist? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/artist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("artistDetailHeaderLockup") })?
            .items?
            .first

        let artistID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let artwork = mapPublicArtwork(headerItem?.uberArtwork?.dictionary) ?? mapPublicArtwork(headerItem?.artwork?.dictionary)

        return PublicCatalogArtist(
            id: artistID,
            name: name,
            url: url,
            artwork: artwork
        )
    }

    private func fetchPublicSearchSection(query: String, title: String) async -> [PublicSearchItem] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        var components = URLComponents(string: "https://music.apple.com/\(region)/search")!
        components.queryItems = [URLQueryItem(name: "term", value: query)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html) else {
                await Logger.shared.log("[AppleMusicAPI] Public search page JSON was not found for query: \(query)")
                return []
            }

            let jsonString = String(html[range])
            guard let jsonData = jsonString.data(using: .utf8) else { return [] }
            let decoded = try JSONDecoder().decode(PublicSearchPageEnvelope.self, from: jsonData)
            let sections = decoded.data.first?.data.sections ?? []
            let matchedSection = sections.first { section in
                section.header?.item?.titleLink?.title == title
            }
            return matchedSection?.items ?? []
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public search page fallback failed for \(title): \(error)")
            return []
        }
    }

    private func fetchPublicCatalogPageNode(urlString: String) async -> PublicAlbumPageNode? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let jsonData = String(html[range]).data(using: .utf8) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(PublicAlbumPageEnvelope.self, from: jsonData)
            return decoded.data.first
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public catalog page fetch failed for \(urlString): \(error)")
            return nil
        }
    }

    private func searchSongsViaPublicSearch(query: String, limit: Int, offset: Int) async -> (songs: [AppleMusicSong], hasMore: Bool) {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Songs")
        guard offset < sectionItems.count else { return ([], false) }
        let hasMore = sectionItems.count > offset + limit
        let page = Array(sectionItems.dropFirst(offset).prefix(limit))

        let lightweightSongs = page.compactMap(mapPublicSearchSong)
        guard !lightweightSongs.isEmpty else { return ([], false) }

        let songs = await withTaskGroup(of: (Int, AppleMusicSong).self) { group in
            for (index, song) in lightweightSongs.enumerated() {
                group.addTask {
                    if song.attributes.albumName != nil {
                        return (index, song)
                    }

                    if let hydrated = await self.fetchSongViaPublicPage(
                        urlString: song.attributes.url,
                        expectedTrackID: song.id
                    ) {
                        return (index, hydrated)
                    }

                    return (index, song)
                }
            }

            var orderedSongs = Array<AppleMusicSong?>(repeating: nil, count: lightweightSongs.count)
            for await (index, song) in group {
                orderedSongs[index] = song
            }
            return orderedSongs.compactMap { $0 }
        }
        return (songs, hasMore)
    }

    private func fetchSongViaPublicPage(urlString: String?, expectedTrackID: String) async -> AppleMusicSong? {
        guard let urlString, let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let jsonData = String(html[range]).data(using: .utf8) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(PublicAlbumPageEnvelope.self, from: jsonData)
            guard let node = decoded.data.first else { return nil }
            let sections = node.data.sections
            let prominentID = node.intent?.prominentItemIdentifier ?? expectedTrackID

            let headerItem = sections
                .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
                .items?
                .first

            let trackItems = sections
                .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
                .items ?? []

            guard let matchedTrack = trackItems.first(where: {
                $0.contentDescriptor?.identifiers?.storeAdamID == expectedTrackID ||
                $0.contentDescriptor?.identifiers?.storeAdamID == prominentID ||
                $0.isProminent == true
            }) else {
                return nil
            }

            let albumID = headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
                matchedTrack.contentDescriptor?.identifiers?.storeAdamID
            let artistID = headerItem?.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let releaseDate = parsePublicReleaseDate(headerItem?.quaternaryTitle)
            let artwork = matchedTrack.artwork?.dictionary.flatMap(mapPublicArtwork) ?? headerItem?.artwork?.dictionary.flatMap(mapPublicArtwork)
            let audioTraits = traits(from: headerItem?.audioBadges)
            let artistName = matchedTrack.artistName ??
                headerItem?.subtitleLinks?.first?.title ??
                "Unknown Artist"
            let albumName = headerItem?.title ?? "Unknown Album"
            let contentRating = (matchedTrack.showExplicitBadge ?? false) ? "explicit" : nil

            let relationships = AppleMusicSongRelationships(
                albums: albumID.map { AppleMusicAlbumsPage(data: [AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: releaseDate))]) },
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            let song = AppleMusicSong(
                id: expectedTrackID,
                attributes: AppleMusicSongAttributes(
                    name: matchedTrack.title ?? "Unknown Title",
                    artistName: artistName,
                    albumName: albumName,
                    url: matchedTrack.contentDescriptor?.url ?? urlString,
                    audioTraits: audioTraits,
                    genreNames: parsePublicGenres(headerItem?.quaternaryTitle),
                    isrc: nil,
                    contentRating: contentRating,
                    releaseDate: releaseDate,
                    trackNumber: matchedTrack.trackNumber,
                    discNumber: matchedTrack.discNumber,
                    durationInMillis: matchedTrack.duration,
                    isAppleDigitalMaster: headerItem?.audioBadges?.digitalMaster ?? false,
                    isMasteredForItunes: headerItem?.audioBadges?.digitalMaster ?? false,
                    artwork: artwork
                ),
                relationships: relationships
            )
            return song
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public song page fallback failed for \(expectedTrackID): \(error)")
            return nil
        }
    }

    private func mapPublicSearchSong(_ item: PublicSearchItem) -> AppleMusicSong? {
        let trackID = item.contentDescriptor?.identifiers?.storeAdamID ??
            item.segue?.subactions?.last?.destination?.prominentItemIdentifier
        guard let trackID,
              let title = item.title,
              let url = item.contentDescriptor?.url else {
            return nil
        }

        let artistName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Unknown Artist"
        let artistID = item.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let albumID = item.segue?.subactions?.last?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let relationships = AppleMusicSongRelationships(
            albums: albumID.map { AppleMusicAlbumsPage(data: [AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: nil))]) },
            artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
            composers: nil,
            genres: nil
        )

        return AppleMusicSong(
            id: trackID,
            attributes: AppleMusicSongAttributes(
                name: title,
                artistName: artistName,
                albumName: nil,
                url: url,
                audioTraits: nil,
                genreNames: nil,
                isrc: nil,
                contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                releaseDate: nil,
                trackNumber: nil,
                discNumber: nil,
                durationInMillis: item.duration,
                isAppleDigitalMaster: nil,
                isMasteredForItunes: nil,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            ),
            relationships: relationships
        )
    }

    private func traits(from badges: PublicAlbumAudioBadges?) -> [String] {
        guard let badges else { return [] }
        var values: [String] = ["lossy-stereo"]
        if badges.hiResLossless == true { values.append("hi-res-lossless") }
        if badges.lossless == true { values.append("lossless") }
        if badges.dolbyAtmos == true {
            values.append("atmos")
            values.append("spatial")
        }
        return values
    }

    private func parsePublicGenres(_ quaternaryTitle: String?) -> [String]? {
        guard let quaternaryTitle else { return nil }
        let components = quaternaryTitle
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = components.first, !first.isEmpty else { return nil }
        return [first]
    }

    private func parsePublicReleaseDate(_ quaternaryTitle: String?) -> String? {
        guard let quaternaryTitle else { return nil }
        let components = quaternaryTitle
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let yearComponent = components.last, yearComponent.allSatisfy(\.isNumber) {
            return yearComponent
        }
        return nil
    }

    private func mapPublicArtwork(_ dictionary: PublicSearchArtworkDictionary?) -> AppleMusicArtwork? {
        guard let dictionary, let url = dictionary.url else { return nil }
        return AppleMusicArtwork(
            width: dictionary.width ?? 1000,
            height: dictionary.height ?? 1000,
            url: url,
            bgColor: dictionary.bgColor,
            textColor1: dictionary.textColor1,
            textColor2: dictionary.textColor2,
            textColor3: dictionary.textColor3,
            textColor4: dictionary.textColor4
        )
    }
}

extension SongMetadata {
    static func parseDateToEpoch(_ dateStr: String) -> Int? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy"
        ]
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: dateStr) {
                return Int(date.timeIntervalSinceReferenceDate)
            }
        }
        return nil
    }
}
