import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Data
extension DeviceLibraryBrowserView {
    func recomputeLibraryGroupings() {
        cachedGroupedSongs = computeGroupedSongs()
        cachedArtistEntries = computeArtistEntries()
        cachedAlbumEntries = computeAlbumEntries()
    }

    func refreshSongs(completion: (() -> Void)? = nil) {
        isLoading = true
        statusMessage = ""
        manager.fetchExportableSongs { result in
            DispatchQueue.main.async {
                songs = result
                if selectedGenre != Self.allGenresOption && !availableGenres.contains(selectedGenre) {
                    selectedGenre = Self.allGenresOption
                }
                recomputeLibraryGroupings()
                selectedIDs = selectedIDs.intersection(Set(result.map(\.id)))
                if result.isEmpty {
                    isSelectionMode = false
                }

                manager.fetchExportablePlaylists { pList in
                    DispatchQueue.main.async {
                        Logger.shared.log("[Playlists] Loaded \(pList.count) playlists, \(manager.pinnedPlaylistPids.count) pinned")
                        self.playlists = pList.map { p in
                            let pSongs = p.songPids.compactMap { pid in
                                result.first(where: { $0.itemPid == pid })
                            }
                            if pSongs.count != p.songPids.count {
                                Logger.shared.log("[Playlists] '\(p.name)' matched \(pSongs.count) of \(p.songPids.count) songs")
                            }
                            return PlaylistEntry(name: p.name, pid: p.pid, songs: pSongs)
                        }
                        isLoading = false
                        statusMessage = result.isEmpty ? "No songs found on the device." : ""
                        queuedArtworkSongs.removeAll()
                        queuedArtworkIDs.removeAll()
                        artworkLoadingIDs.removeAll()
                        prefetchArtworkForCurrentMode()
                        loadPlaylistCovers(for: pList)
                        completion?()
                    }
                }
            }
        }
    }

    func loadPlaylistCovers(for pList: [(name: String, pid: Int64, songPids: [Int64], coverRelativePath: String?)]) {
        for p in pList {
            guard let relativePath = p.coverRelativePath else { continue }
            manager.downloadPlaylistCoverArtwork(relativePath: relativePath) { data in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if let idx = playlists.firstIndex(where: { $0.pid == p.pid }) {
                        playlists[idx].coverImage = image
                    }
                }
            }
        }
    }
}
