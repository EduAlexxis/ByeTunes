import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

struct DownloadTrack: Identifiable {
    enum SourceContext {
        case song
        case album
    }

    let id: String
    let name: String
    let artistLine: String
    let albumName: String
    let artworkURL: URL?
    let isExplicit: Bool
    let sourceURL: String
    let sourceContext: SourceContext
    let provider: DownloadView.SearchProvider
    let artistIdentifier: String?
    let albumIdentifier: String?
    let previewURL: URL?
}

struct DownloadAlbum: Identifiable {
    let id: String
    let name: String
    let artistLine: String
    let artworkURL: URL?
    let sourceURL: String
    let provider: DownloadView.SearchProvider
    let artistIdentifier: String?
    let albumIdentifier: String?
}

struct DownloadArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: DownloadView.SearchProvider
    let artworkURL: URL?
}

struct DownloadArtistProfile {
    let tracks: [DownloadTrack]
    let albums: [DownloadAlbum]
}

enum DownloadTrackState {
    case idle
    case queued
    case downloading
    case done
    case failed
}

struct DownloadDirectLinkAction: Identifiable {
    let id = UUID()
    let payload: DownloadDirectLinkPayload
}

enum DownloadDirectLinkPayload {
    case track(DownloadTrack)
    case collection(album: DownloadAlbum, tracks: [DownloadTrack], title: String, helperText: String)
    case artist(DownloadArtist)
}

struct BackendCandidate {
    let label: String
    let request: URLRequest?
    let customDownload: ((_ trackID: String, _ suggestedName: String, _ fallbackExtension: String) async throws -> URL)?
    var requestedFormat: String? = nil
}

struct BackendDownloadOutcome {
    let fileURL: URL
    let backendLabel: String
}

struct PreparedBackgroundDownloadPlan {
    let candidates: [BackendCandidate]
    let suggestedName: String
    let fallbackExtension: String
}


enum DownloadPlatform: String {
    case appleMusic
    case spotify
    case deezer
    case qobuz
    case tidal
    case amazon
    case pandora
    case soundcloud
    case youtubeMusic
    case unknown

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .deezer: return "Deezer"
        case .qobuz: return "Qobuz"
        case .tidal: return "Tidal"
        case .amazon: return "Amazon Music"
        case .pandora: return "Pandora"
        case .soundcloud: return "SoundCloud"
        case .youtubeMusic: return "YouTube Music"
        case .unknown: return "Unknown"
        }
    }

    var backendGenreSource: String {
        switch self {
        case .appleMusic: return "itunes"
        case .spotify: return "spotify"
        case .deezer: return "itunes"
        case .qobuz: return "itunes"
        case .tidal: return "itunes"
        case .amazon: return "itunes"
        case .pandora: return "itunes"
        case .soundcloud: return "itunes"
        case .youtubeMusic: return "itunes"
        case .unknown: return "itunes"
        }
    }
}

struct DownloadSourceChoice {
    let platform: DownloadPlatform
    let url: String
    let backendGenreSource: String
}

struct MetadataSearchBatch {
    let tracks: [DownloadTrack]
    let deezerCount: Int
}

enum DirectLinkKind {
    case appleSong(id: String, sourceURL: String)
    case appleAlbum(id: String, sourceURL: String)
    case appleArtist(id: String, sourceURL: String)
    case applePlaylist(id: String, sourceURL: String)
    case spotifyTrack(id: String, sourceURL: String)
    case spotifyAlbum(id: String, sourceURL: String)
    case spotifyArtist(id: String, sourceURL: String)
    case spotifyPlaylist(id: String, sourceURL: String)
    case deezerTrack(id: String, sourceURL: String)
    case deezerAlbum(id: String, sourceURL: String)
    case deezerArtist(id: String, sourceURL: String)
    case deezerPlaylist(id: String, sourceURL: String)
    case deezerShortLink(sourceURL: String)
}

enum DownloadError: LocalizedError {
    case invalidURL(String)
    case searchFailed
    case mappingFailed(String)
    case trackNotFound
    case remoteFailure(String)
    case httpError(Int, String)
    case emptyResponse
    case fileSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL."
        case .searchFailed: return "Search failed."
        case .mappingFailed(let message): return message
        case .trackNotFound: return "No downloadable match was found for this track."
        case .remoteFailure(let text): return "Backend failure: \(text)"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .emptyResponse: return "Backend returned empty response."
        case .fileSaveFailed(let message): return "Save failed: \(message)"
        }
    }
}

enum DownloadSupport {
    static func fileExtension(for mimeType: String?, fallback: String) -> String {
        guard let type = mimeType?.lowercased() else { return fallback }
        if type.contains("opus") { return "opus" }
        if type.contains("flac") { return "flac" }
        if type.contains("mpeg") || type.contains("mp3") { return "mp3" }
        if type.contains("aac") || type.contains("mp4") { return "m4a" }
        if type.contains("wav") { return "wav" }
        return fallback
    }

    static func fallbackExtension(forRequestedFormat format: String?, defaultingTo fallback: String) -> String {
        guard let format else { return fallback }
        switch format.lowercased() {
        case "alac": return "m4a"
        case "": return fallback
        default: return format.lowercased()
        }
    }

    static func tidyFilename(_ value: String) -> String {
        var invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        invalid.formUnion(.controlCharacters)
        invalid.formUnion(.illegalCharacters)
        let separated = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        var cleaned = separated.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.count > 120 {
            cleaned = String(cleaned.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? "download" : cleaned
    }

    nonisolated static func normalizedSearchValue(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let cleaned = folded.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func artistTokens(from value: String) -> [String] {
        let separatorsPattern = #"\s*(?:,|&| x | y | feat\.?|ft\.?|with)\s*"#
        let canonicalized = value.replacingOccurrences(of: separatorsPattern, with: ",", options: .regularExpression)
        return canonicalized
            .components(separatedBy: ",")
            .map(normalizedSearchValue)
            .filter { !$0.isEmpty }
    }
}

actor DownloadStartPacer {
    private let defaultMinSpacing: Duration
    private var lastStart: ContinuousClock.Instant?

    init(minSpacing: Duration) {
        self.defaultMinSpacing = minSpacing
    }

    func waitForNextSlot(minSpacing: Duration? = nil) async {
        let spacing = minSpacing ?? defaultMinSpacing
        if let lastStart {
            let elapsed = ContinuousClock.now - lastStart
            if elapsed < spacing {
                try? await Task.sleep(for: spacing - elapsed)
            }
        }
        lastStart = ContinuousClock.now
    }
}

final class DownloadBackgroundTaskState {
    var id: UIBackgroundTaskIdentifier = .invalid
}

struct DownloadQueueSnapshot {
    struct Item: Identifiable {
        let id: String
        let name: String
        let artist: String
        let album: String
        let state: DownloadTrackState
        let isActive: Bool
        let progress: Double
        let queueIndex: Int?
        let failureReason: String?
        let qualityNote: String?
    }

    let activeItems: [Item]
    let queuedItems: [Item]
    let doneItems: [Item]
    let failedItems: [Item]
    let aggregateProgress: Double
    let queueCounterText: String
    let aggregateSpeedBps: Double
}
