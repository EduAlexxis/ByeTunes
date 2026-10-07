import Foundation

struct PictureInPictureItem {
    let id: String
    let title: String
    let artist: String
    let progress: Double
    let speedBps: Double
    let artworkURL: URL?
    var isFetchingMetadata = false
}

struct PictureInPictureSnapshot {
    let doneCount: Int
    let totalCount: Int
    let overallProgress: Double
    let speedBps: Double
    let activeItems: [PictureInPictureItem]
    let upNext: [PictureInPictureItem]
    let pendingCount: Int
    let states: [String: DownloadTrackState]
}

extension DownloadViewModel {
    func pictureInPictureSnapshot() -> PictureInPictureSnapshot {
        let activeIDs = queueOrder.filter { activeDownloadTrackIDs.contains($0) }
        let items: [PictureInPictureItem] = activeIDs.prefix(2).compactMap { id in
            guard let track = knownTracksByID[id] else { return nil }
            return PictureInPictureItem(
                id: id,
                title: track.name,
                artist: track.artistLine,
                progress: downloadProgressByTrackID[id] ?? 0,
                speedBps: downloadSpeedByTrackID[id] ?? 0,
                artworkURL: track.artworkURL,
                isFetchingMetadata: metadataFetchingTrackIDs.contains(id)
            )
        }
        let total = max(totalQueueCount, 1)
        return PictureInPictureSnapshot(
            doneCount: min(completedQueueCount, total),
            totalCount: total,
            overallProgress: aggregateDownloadProgress,
            speedBps: aggregateDownloadSpeedBps,
            activeItems: items,
            upNext: pendingQueue.prefix(8).map { track in
                PictureInPictureItem(
                    id: track.id,
                    title: track.name,
                    artist: track.artistLine,
                    progress: 0,
                    speedBps: 0,
                    artworkURL: track.artworkURL
                )
            },
            pendingCount: pendingQueue.count,
            states: trackStates
        )
    }
}
