import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

@MainActor
final class DownloadViewModel: ObservableObject {
    static let shared = DownloadViewModel()

    // MARK: - Search Results
    @Published var artistResults: [DownloadArtist] = []
    @Published var songResults: [DownloadTrack] = []
    @Published var albumResults: [DownloadAlbum] = []
    @Published var playlistResults: [DownloadAlbum] = []
    @Published var pendingDirectLinkAction: DownloadDirectLinkAction?
    @Published var isPaused = false

    // MARK: - Queue State
    var foregroundWorkerTasks: [String: Task<Void, Never>] = [:]
    var maxConcurrentDownloads: Int {
        isLosslessDownloadFormat ? 1 : 2
    }
    var isLosslessDownloadFormat: Bool {
        let format = desiredDownloadFormat().lowercased()
        return format == "flac" || format == "alac"
    }
    var isAppActive = UIApplication.shared.applicationState != .background
    var lifecycleObservers: [NSObjectProtocol] = []
    let downloadStartPacer = DownloadStartPacer(minSpacing: .milliseconds(300))

    var shouldShowPauseButton: Bool {
        !pendingQueue.isEmpty || !activeDownloadTrackIDs.isEmpty
    }

    var shouldShowCancelButton: Bool {
        !pendingQueue.isEmpty || !activeDownloadTrackIDs.isEmpty || isPaused
    }

    // MARK: - Search State
    @Published var isSearching = false
    @Published var errorText: String?
    @Published var canLoadMoreSongs = false
    @Published var canLoadMoreAlbums = false
    @Published var canLoadMorePlaylists = false
    @Published var isLoadingMoreSongs = false
    @Published var isLoadingMoreAlbums = false
    @Published var isLoadingMorePlaylists = false
    @Published var activeDownloadTrackIDs: Set<String> = []
    @Published var activePreviewTrackID: String?
    @Published var previewLoadingTrackIDs: Set<String> = []
    @Published var emittedSongs: [SongMetadata] = []
    @Published var totalQueueCount = 0
    @Published var completedQueueCount = 0
    @Published var downloadProgressByTrackID: [String: Double] = [:]
    @Published var downloadSpeedByTrackID: [String: Double] = [:]

    let session: URLSession = .shared
    var pendingQueue: [DownloadTrack] = []
    var trackStates: [String: DownloadTrackState] = [:]
    var trackFailureReasons: [String: String] = [:]
    var trackQualityNotes: [String: String] = [:]
    var knownTracksByID: [String: DownloadTrack] = [:]
    var queueOrder: [String] = []
    var albumTrackIDs: [String: [String]] = [:]
    var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @Published var resolvingAlbumIDs: Set<String> = []
    var lastSearchQuery = ""
    var lastSearchProvider: DownloadView.SearchProvider = .appleMusic
    let songPageSize = 25
    let albumPageSize = 15
    let playlistPageSize = 15
    var metadataCachedSearchTracks: [DownloadTrack] = []
    var metadataCachedSearchAlbums: [DownloadAlbum] = []
    var metadataCachedSearchPlaylists: [DownloadAlbum] = []
    var metadataAlbumTrackCache: [String: [DownloadTrack]] = [:]
    var metadataDeezerOffset = 0
    var metadataCanFetchMoreDeezer = false
    var previewPlayer: AVPlayer?
    var previewEndObserver: NSObjectProtocol?
    var previewStatusObserver: NSKeyValueObservation?
    var cachedPreviewURLs: [String: URL] = [:]
    var metadataFetchingTrackIDs = Set<String>()

    var backgroundDownloadsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "backgroundDownloadsEnabled")
    }

    // MARK: - Lifecycle
    init() {
        restorePersistedQueue()
        lifecycleObservers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.appDidBecomeActive()
                }
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.appDidEnterBackground()
                }
            }
        ]
    }

    // MARK: - Progress
    var aggregateDownloadProgress: Double {
        guard totalQueueCount > 0 else { return 0 }
        let activeCredit = downloadProgressByTrackID.values.reduce(0, +)
        return min((Double(completedQueueCount) + activeCredit) / Double(totalQueueCount), 1)
    }

    var aggregateDownloadSpeedBps: Double {
        downloadSpeedByTrackID.values.reduce(0, +)
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
        }
    }

    var queueCounterText: String {
        if isPaused {
            return "Paused"
        }
        guard totalQueueCount > 0 else { return "Queue" }
        if !activeDownloadTrackIDs.isEmpty {
            return "\(min(completedQueueCount + activeDownloadTrackIDs.count, totalQueueCount))/\(totalQueueCount)"
        }
        return "\(min(completedQueueCount, totalQueueCount))/\(totalQueueCount)"
    }

    var queueIndicatorSymbol: String {
        if isPaused {
            return "pause.fill"
        }
        guard totalQueueCount > 0 else { return "arrow.down" }
        if activeDownloadTrackIDs.isEmpty && pendingQueue.isEmpty && completedQueueCount >= totalQueueCount {
            return "checkmark"
        }
        return "arrow.down"
    }

    // MARK: - Track State
    func state(for trackID: String) -> DownloadTrackState {
        trackStates[trackID] ?? .idle
    }

    func canEnqueue(trackID: String) -> Bool {
        switch state(for: trackID) {
        case .idle, .failed:
            return true
        case .queued, .downloading, .done:
            return false
        }
    }

    func state(forAlbumID albumID: String) -> DownloadTrackState {
        guard let trackIDs = albumTrackIDs[albumID], !trackIDs.isEmpty else { return .idle }
        let states = trackIDs.map { state(for: $0) }
        if states.contains(.downloading) { return .downloading }
        if states.contains(.queued) { return .queued }
        if !states.isEmpty && states.allSatisfy({ $0 == .done }) { return .done }
        if states.contains(.failed) { return .failed }
        return .idle
    }

    func isResolvingAlbum(albumID: String) -> Bool {
        resolvingAlbumIDs.contains(albumID)
    }

    func isPreviewPlaying(for trackID: String) -> Bool {
        activePreviewTrackID == trackID
    }

    func isPreviewLoading(for trackID: String) -> Bool {
        previewLoadingTrackIDs.contains(trackID)
    }
}
