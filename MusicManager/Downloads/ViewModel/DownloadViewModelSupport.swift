import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

// MARK: - Support
extension DownloadViewModel {
    func uniqueAlbums(_ albums: [DownloadAlbum]) -> [DownloadAlbum] {
        var seen = Set<String>()
        return albums.filter { album in
            let key = "\(album.provider.rawValue)|\(DownloadSupport.normalizedSearchValue(album.artistLine))|\(DownloadSupport.normalizedSearchValue(album.name))"
            return seen.insert(key).inserted
        }
    }

    func uniqueTracks(_ tracks: [DownloadTrack]) -> [DownloadTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            let key = "\(track.provider.rawValue)|\(DownloadSupport.normalizedSearchValue(track.artistLine))|\(DownloadSupport.normalizedSearchValue(track.albumName))|\(DownloadSupport.normalizedSearchValue(track.name))"
            return seen.insert(key).inserted
        }
    }

    func uniqueTracksForMetadataProfile(_ tracks: [DownloadTrack]) -> [DownloadTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            let key = "\(DownloadSupport.normalizedSearchValue(track.artistLine))|\(DownloadSupport.normalizedSearchValue(track.albumName))|\(DownloadSupport.normalizedSearchValue(track.name))"
            return seen.insert(key).inserted
        }
    }

    func uniqueAlbumsForMetadataProfile(_ albums: [DownloadAlbum]) -> [DownloadAlbum] {
        var seen = Set<String>()
        return albums.filter { album in
            let key = "\(DownloadSupport.normalizedSearchValue(album.artistLine))|\(DownloadSupport.normalizedSearchValue(album.name))"
            return seen.insert(key).inserted
        }
    }

    func matchesArtistLine(_ artistLine: String, artistName: String) -> Bool {
        let target = DownloadSupport.normalizedSearchValue(artistName)
        let normalizedLine = DownloadSupport.normalizedSearchValue(artistLine)
        guard !target.isEmpty, !normalizedLine.isEmpty else { return false }
        if normalizedLine == target { return true }
        let tokens = DownloadSupport.artistTokens(from: artistLine)
        return tokens.contains(where: { $0 == target || $0.contains(target) || target.contains($0) })
    }

    func log(_ message: String) {
        Logger.shared.log("[Download] \(message)")
    }

    static let appleMusicUnavailableMessage = "Unable to download using Apple Music. Please paste the Spotify or Deezer URL."

    func downloadFailureMessage(for track: DownloadTrack, error: Error) -> String {
        if let downloadError = error as? DownloadError, case .trackNotFound = downloadError {
            return Self.appleMusicUnavailableMessage
        }
        return Self.friendlyDownloadFailureMessage(for: error)
    }

    static func friendlyDownloadFailureMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The download timed out. Check your connection and try again."
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection."
            case .cancelled:
                return "Download cancelled."
            default:
                return "A network error occurred. Please try again."
            }
        }

        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .invalidURL, .mappingFailed, .trackNotFound:
                return "This track isn't available right now."
            case .searchFailed:
                return "Search failed. Please try again."
            case .remoteFailure, .httpError, .emptyResponse:
                return "The download server had a problem. Please try again."
            case .fileSaveFailed:
                return "Couldn't save the downloaded file."
            }
        }

        return "Download failed. Please try again."
    }

    func updateVisibleDownloadProgress(_ progress: Double, speedBps: Double, trackID: String) {
        guard activeDownloadTrackIDs.contains(trackID) else { return }
        downloadProgressByTrackID[trackID] = progress
        downloadSpeedByTrackID[trackID] = speedBps
    }


    func restorePersistedQueue() {
        guard let snapshot = QueuePersistenceStore.loadDownloadQueue() else { return }

        let restoredTracks = snapshot.tracksByID.compactMapValues(\.downloadTrack)
        guard !restoredTracks.isEmpty else {
            QueuePersistenceStore.clearDownloadQueue()
            return
        }

        knownTracksByID = restoredTracks
        queueOrder = snapshot.queueOrder.filter { restoredTracks[$0] != nil }
        totalQueueCount = snapshot.totalQueueCount
        completedQueueCount = snapshot.completedQueueCount
        let interruptedIDs = snapshot.activeIDs.filter { restoredTracks[$0] != nil }

        for id in snapshot.failedIDs where restoredTracks[id] != nil {
            trackStates[id] = .failed
            trackFailureReasons[id] = snapshot.failureReasons?[id]
        }

        for id in snapshot.doneIDs where restoredTracks[id] != nil {
            trackStates[id] = .done
        }

        let pendingIDs = interruptedIDs + snapshot.pendingIDs.filter { restoredTracks[$0] != nil && !interruptedIDs.contains($0) }
        pendingQueue = pendingIDs.compactMap { id in
            trackStates[id] = .queued
            return restoredTracks[id]
        }

        if totalQueueCount == 0 && (!pendingQueue.isEmpty || !snapshot.failedIDs.isEmpty) {
            totalQueueCount = pendingQueue.count + snapshot.failedIDs.count
        }
        completedQueueCount = min(completedQueueCount, totalQueueCount)

        if !pendingQueue.isEmpty {
            log("Restored \(pendingQueue.count) queued download(s) from last session.")
            Task { await processQueueIfNeeded() }
        } else if !snapshot.failedIDs.isEmpty {
            log("Restored \(snapshot.failedIDs.count) failed download(s) from last session.")
        }
    }

    func syncQueuePersistence() {
        let failedIDs = queueOrder.filter { trackStates[$0] == .failed }
        let pendingIDs = pendingQueue.map(\.id)
        let hasMeaningfulState = !pendingIDs.isEmpty || !activeDownloadTrackIDs.isEmpty || !failedIDs.isEmpty

        guard hasMeaningfulState else {
            QueuePersistenceStore.clearDownloadQueue()
            return
        }

        let doneIDs = queueOrder.filter { trackStates[$0] == .done }

        let snapshot = PersistedDownloadQueue(
            tracksByID: knownTracksByID.mapValues(PersistedDownloadTrack.init),
            queueOrder: queueOrder,
            pendingIDs: pendingIDs,
            failedIDs: failedIDs,
            activeIDs: Array(activeDownloadTrackIDs),
            doneIDs: doneIDs,
            totalQueueCount: totalQueueCount,
            completedQueueCount: completedQueueCount,
            failureReasons: trackFailureReasons.filter { failedIDs.contains($0.key) }
        )
        QueuePersistenceStore.saveDownloadQueue(snapshot)
    }

    func queueSnapshot() -> DownloadQueueSnapshot {
        var items: [DownloadQueueSnapshot.Item] = []
        for id in queueOrder {
            guard let track = knownTracksByID[id] else { continue }
            let state = trackStates[id] ?? .idle
            guard state != .idle else { continue }

            let queueIndex = pendingQueue.firstIndex(where: { $0.id == id })
            let isActive = activeDownloadTrackIDs.contains(id)
            items.append(
                .init(
                    id: id,
                    name: track.name,
                    artist: track.artistLine,
                    album: track.albumName,
                    state: state,
                    isActive: isActive,
                    progress: isActive ? (downloadProgressByTrackID[id] ?? 0) : 0,
                    queueIndex: queueIndex,
                    failureReason: state == .failed ? trackFailureReasons[id] : nil,
                    qualityNote: state == .done ? trackQualityNotes[id] : nil
                )
            )
        }

        let activeItems = items.filter { $0.isActive }
        let queuedItems = items.filter { $0.queueIndex != nil && !$0.isActive }
            .sorted { ($0.queueIndex ?? 0) < ($1.queueIndex ?? 0) }
        let doneItems = items.filter { $0.state == .done }
        let failedItems = items.filter { $0.state == .failed }

        return DownloadQueueSnapshot(
            activeItems: activeItems,
            queuedItems: queuedItems,
            doneItems: doneItems,
            failedItems: failedItems,
            aggregateProgress: aggregateDownloadProgress,
            queueCounterText: queueCounterText,
            aggregateSpeedBps: aggregateDownloadSpeedBps
        )
    }
}
