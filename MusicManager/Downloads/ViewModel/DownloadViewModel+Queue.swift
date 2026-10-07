import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func pauseQueue() {
        guard !isPaused else { return }
        isPaused = true
        for task in foregroundWorkerTasks.values {
            task.cancel()
        }
        let backgroundActiveIDs = activeDownloadTrackIDs.subtracting(foregroundWorkerTasks.keys)
        if backgroundDownloadsEnabled, !backgroundActiveIDs.isEmpty {
            pausedBackgroundTrackIDs.formUnion(backgroundActiveIDs)
            Task {
                for activeID in backgroundActiveIDs {
                    await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: activeID)
                }
            }
        }
        log("Download queue paused by user.")
    }

    func resumeQueue() {
        guard isPaused else { return }
        isPaused = false
        log("Download queue resumed by user.")
        Task { await processQueueIfNeeded() }
        ContinuedDownloadTask.shared.startIfNeeded(for: self)
        PictureInPictureKeepAlive.shared.engage(for: self)
    }

    func knownTrackName(for trackID: String) -> String? {
        knownTracksByID[trackID].map { "\($0.name) - \($0.artistLine)" }
    }

    var hasPendingOrActiveDownloads: Bool {
        !pendingQueue.isEmpty || !activeDownloadTrackIDs.isEmpty
    }

    func continuedTaskProgress() -> (completedUnits: Int64, totalUnits: Int64, subtitle: String) {
        let total = max(totalQueueCount, 1)
        let activeCredit = downloadProgressByTrackID.values.reduce(0, +)
        let completedUnits = Int64((Double(completedQueueCount) + activeCredit) * 100)
        let totalUnits = Int64(total * 100)
        let finished = min(completedQueueCount, total)
        return (min(completedUnits, totalUnits), totalUnits, "\(finished) of \(total) songs")
    }

    func cancelQueue() {
        for task in foregroundWorkerTasks.values {
            task.cancel()
        }
        let activeIDsToCancel = activeDownloadTrackIDs
        for track in pendingQueue {
            trackStates[track.id] = .idle
        }
        pendingQueue.removeAll()
        for activeID in activeIDsToCancel {
            trackStates[activeID] = .idle
        }
        activeDownloadTrackIDs.removeAll()
        downloadProgressByTrackID.removeAll()
        downloadSpeedByTrackID.removeAll()
        totalQueueCount = 0
        completedQueueCount = 0
        isPaused = false
        pausedBackgroundTrackIDs.removeAll()
        if backgroundDownloadsEnabled, !activeIDsToCancel.isEmpty {
            for activeID in activeIDsToCancel {
                cancelledBackgroundTrackIDs.insert(activeID)
            }
            Task {
                for activeID in activeIDsToCancel {
                    await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: activeID)
                }
            }
        }
        log("Download queue cancelled and cleared by user.")
        syncQueuePersistence()
    }

    func enqueue(track: DownloadTrack) {
        _ = enqueueMany([track])
    }

    @discardableResult
    func enqueue(tracks: [DownloadTrack], albumID: String? = nil) -> Int {
        if let albumID {
            albumTrackIDs[albumID] = tracks.map(\.id)
        }
        let added = enqueueMany(tracks)
        return added
    }

    func loadTracks(for album: DownloadAlbum) async -> [DownloadTrack] {
        guard !resolvingAlbumIDs.contains(album.id) else { return [] }
        resolvingAlbumIDs.insert(album.id)
        defer { resolvingAlbumIDs.remove(album.id) }
        switch album.provider {
        case .appleMusic:
            let albumID = album.albumIdentifier ?? album.id
            return await fetchAlbumTracks(albumID: albumID, fallbackAlbumName: album.name, sourceURL: album.sourceURL)
        case .spotify:
            if album.sourceURL.contains("spotify.com") {
                if let (_, tracks) = await fetchSpotifyAlbum(id: album.id, sourceURL: album.sourceURL) {
                    return tracks
                }
                return []
            } else {
                let albumID = album.albumIdentifier ?? album.id
                let amTracks = await fetchAlbumTracks(albumID: albumID, fallbackAlbumName: album.name, sourceURL: album.sourceURL)
                return amTracks.map { track in
                    DownloadTrack(
                        id: track.id,
                        name: track.name,
                        artistLine: track.artistLine,
                        albumName: track.albumName,
                        artworkURL: track.artworkURL,
                        isExplicit: track.isExplicit,
                        sourceURL: track.sourceURL,
                        sourceContext: track.sourceContext,
                        provider: .spotify,
                        artistIdentifier: track.artistIdentifier,
                        albumIdentifier: track.albumIdentifier,
                        previewURL: track.previewURL
                    )
                }
            }
        case .metadata, .itunes, .deezer:
            if let identifier = album.albumIdentifier,
               identifier.hasPrefix("deezer-album-"),
               let numericID = Int(identifier.dropFirst("deezer-album-".count)),
               let albumDetail = await SongMetadata.fetchDeezerAlbum(id: numericID) {
                let tracks = albumDetail.tracks.data.map { metadataTrack(from: $0) }
                if !tracks.isEmpty {
                    return tracks
                }
            }

            if let tracks = metadataAlbumTrackCache[album.id], !tracks.isEmpty {
                return tracks
            }
            let query = "\(album.artistLine) \(album.name)"
            let batch = await fetchMetadataSearchTracks(query: query, limit: 50, deezerIndex: 0, includeITunes: true)
            let matchingTracks = batch.tracks.filter { track in
                DownloadSupport.normalizedSearchValue(track.albumName) == DownloadSupport.normalizedSearchValue(album.name) &&
                matchesArtistLine(track.artistLine, artistName: album.artistLine)
            }
            return matchingTracks.isEmpty ? batch.tracks : matchingTracks
        }
    }

    func loadTracks(forPlaylist playlist: DownloadAlbum) async -> [DownloadTrack] {
        switch playlist.provider {
        case .appleMusic:
            let playlistID = playlist.albumIdentifier ?? playlist.id
            guard let playlistResult = await fetchAppleMusicPlaylist(id: playlistID, sourceURL: playlist.sourceURL) else { return [] }
            return playlistResult.relationships?.tracks?.data.map {
                DownloadTrack(
                    id: $0.id,
                    name: $0.attributes.name,
                    artistLine: $0.attributes.artistName,
                    albumName: $0.attributes.albumName ?? playlist.name,
                    artworkURL: $0.attributes.artwork?.artworkURL(width: 400, height: 400) ?? playlist.artworkURL,
                    isExplicit: $0.attributes.contentRating == "explicit",
                    sourceURL: $0.attributes.url ?? playlist.sourceURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: nil,
                    previewURL: nil
                )
            } ?? []
        case .spotify:
            if playlist.sourceURL.contains("spotify.com") {
                if let (_, tracks) = await fetchSpotifyPlaylist(id: playlist.id, sourceURL: playlist.sourceURL) {
                    return tracks
                }
                return []
            } else {
                let playlistID = playlist.albumIdentifier ?? playlist.id
                guard let playlistResult = await fetchAppleMusicPlaylist(id: playlistID, sourceURL: playlist.sourceURL) else { return [] }
                return playlistResult.relationships?.tracks?.data.map {
                    DownloadTrack(
                        id: $0.id,
                        name: $0.attributes.name,
                        artistLine: $0.attributes.artistName,
                        albumName: $0.attributes.albumName ?? playlist.name,
                        artworkURL: $0.attributes.artwork?.artworkURL(width: 400, height: 400) ?? playlist.artworkURL,
                        isExplicit: $0.attributes.contentRating == "explicit",
                        sourceURL: $0.attributes.url ?? playlist.sourceURL,
                        sourceContext: .song,
                        provider: .spotify,
                        artistIdentifier: nil,
                        albumIdentifier: nil,
                        previewURL: nil
                    )
                } ?? []
            }
        case .metadata, .itunes, .deezer:
            return []
        }
    }

    func enqueue(album: DownloadAlbum) async {
        let tracks = await loadTracks(for: album)
        guard !tracks.isEmpty else {
            errorText = "Could not load tracks for album \(album.name)"
            return
        }

        let added = enqueue(tracks: tracks, albumID: album.id)
        if added == 0 {
            errorText = "All tracks from \(album.name) are already queued or downloaded."
        } else {
            log("Queued \(added) tracks from album \(album.name)")
        }
    }

    func retry(trackID: String) {
        guard let track = knownTracksByID[trackID] else { return }
        errorText = nil
        trackFailureReasons.removeValue(forKey: trackID)
        trackQualityNotes.removeValue(forKey: trackID)
        _ = enqueueMany([track])
    }

    func removeFailed(trackID: String) {
        guard trackStates[trackID] == .failed else { return }
        trackStates.removeValue(forKey: trackID)
        trackFailureReasons.removeValue(forKey: trackID)
        queueOrder.removeAll { $0 == trackID }
        if totalQueueCount > completedQueueCount {
            totalQueueCount = max(0, totalQueueCount - 1)
        }
        if backgroundDownloadsEnabled {
            cancelledBackgroundTrackIDs.insert(trackID)
            Task {
                await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: trackID)
            }
        }
        syncQueuePersistence()
    }

    func clearAllFailed() {
        let failedIDs = Set(queueOrder.filter { trackStates[$0] == .failed })
        guard !failedIDs.isEmpty else { return }
        for id in failedIDs {
            trackStates.removeValue(forKey: id)
            trackFailureReasons.removeValue(forKey: id)
        }
        queueOrder.removeAll { failedIDs.contains($0) }
        if totalQueueCount > completedQueueCount {
            totalQueueCount = max(completedQueueCount, totalQueueCount - failedIDs.count)
        }
        if backgroundDownloadsEnabled {
            for id in failedIDs {
                cancelledBackgroundTrackIDs.insert(id)
            }
            Task {
                for id in failedIDs {
                    await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: id)
                }
            }
        }
        syncQueuePersistence()
    }

    func clearCompleted() {
        let doneIDs = Set(queueOrder.filter { trackStates[$0] == .done })
        guard !doneIDs.isEmpty else { return }
        for id in doneIDs {
            trackStates.removeValue(forKey: id)
            trackQualityNotes.removeValue(forKey: id)
        }
        queueOrder.removeAll { doneIDs.contains($0) }
        completedQueueCount = max(0, completedQueueCount - doneIDs.count)
        totalQueueCount = max(0, totalQueueCount - doneIDs.count)
        syncQueuePersistence()
    }

    func removeQueued(trackID: String) {
        guard trackStates[trackID] == .queued else { return }
        pendingQueue.removeAll { $0.id == trackID }
        trackStates.removeValue(forKey: trackID)
        queueOrder.removeAll { $0 == trackID }
        totalQueueCount = max(0, totalQueueCount - 1)
        completedQueueCount = min(completedQueueCount, totalQueueCount)
        syncQueuePersistence()
    }

    func retry(album: DownloadAlbum) async {
        errorText = nil

        if let knownTrackIDs = albumTrackIDs[album.id], !knownTrackIDs.isEmpty {
            let knownTracks = knownTrackIDs.compactMap { knownTracksByID[$0] }
            if !knownTracks.isEmpty {
                let added = enqueue(tracks: knownTracks, albumID: album.id)
                if added == 0 {
                    errorText = "No failed tracks from \(album.name) are available to retry."
                }
                return
            }
        }

        await enqueue(album: album)
    }

    func retry(playlist: DownloadAlbum) async {
        errorText = nil

        if let knownTrackIDs = albumTrackIDs[playlist.id], !knownTrackIDs.isEmpty {
            let knownTracks = knownTrackIDs.compactMap { knownTracksByID[$0] }
            if !knownTracks.isEmpty {
                let added = enqueue(tracks: knownTracks, albumID: playlist.id)
                if added == 0 {
                    errorText = "No failed tracks from \(playlist.name) are available to retry."
                }
                return
            }
        }

        let tracks = await loadTracks(forPlaylist: playlist)
        guard !tracks.isEmpty else {
            errorText = "Could not load tracks for playlist \(playlist.name)"
            return
        }

        let added = enqueue(tracks: tracks, albumID: playlist.id)
        if added == 0 {
            errorText = "All tracks from \(playlist.name) are already queued or downloaded."
        }
    }
}
