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
        let randomName = String((0..<12).map { _ in letters.randomElement() ?? "A" })
        let e = ext.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "mp3"
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
