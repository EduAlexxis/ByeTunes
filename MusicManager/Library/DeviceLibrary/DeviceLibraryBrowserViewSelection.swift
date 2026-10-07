import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Selection
extension DeviceLibraryBrowserView {
    var summaryCountText: String {
        switch libraryMode {
        case .songs:
            return "\(filteredSongs.count)"
        case .artists:
            return "\(cachedArtistEntries.count)"
        case .albums:
            return "\(cachedAlbumEntries.count)"
        case .playlists:
            return "\(playlists.count)"
        }
    }

    var allFilteredSongsSelected: Bool {
        let visibleIDs = Set(filteredSongs.map(\.id))
        return !visibleIDs.isEmpty && selectedIDs.isSuperset(of: visibleIDs)
    }

    var allPlaylistsSelected: Bool {
        let allPids = Set(playlists.map(\.pid))
        return !allPids.isEmpty && selectedPlaylistPids.isSuperset(of: allPids)
    }

    func toggleAllPlaylistsSelection() {
        let allPids = Set(playlists.map(\.pid))
        guard !allPids.isEmpty else { return }
        if selectedPlaylistPids.isSuperset(of: allPids) {
            selectedPlaylistPids.subtract(allPids)
        } else {
            selectedPlaylistPids.formUnion(allPids)
        }
    }

    func togglePlaylistSelection(_ pid: Int64) {
        if selectedPlaylistPids.contains(pid) {
            selectedPlaylistPids.remove(pid)
        } else {
            selectedPlaylistPids.insert(pid)
        }
    }

    func deleteSelectedPlaylists() {
        guard !selectedPlaylistPids.isEmpty else { return }
        applyPlaylistActions(selectedPlaylistPids.map { .delete(containerPid: $0) })
        selectedPlaylistPids.removeAll()
        isSelectionMode = false
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func toggleVisibleSelection() {
        let visibleIDs = Set(filteredSongs.map(\.id))
        let selectedVisibleCount = selectedIDs.intersection(visibleIDs).count
        if selectedVisibleCount == visibleIDs.count && !visibleIDs.isEmpty {
            filteredSongs.forEach { selectedIDs.remove($0.id) }
        } else {
            filteredSongs.forEach { selectedIDs.insert($0.id) }
        }
    }

    func areAllSelected(in songs: [DeviceManager.ExportableSongInfo]) -> Bool {
        let ids = Set(songs.map(\.id))
        return !ids.isEmpty && selectedIDs.isSuperset(of: ids)
    }

    func selectAll(in songs: [DeviceManager.ExportableSongInfo]) {
        let ids = Set(songs.map(\.id))
        guard !ids.isEmpty else { return }

        if selectedIDs.isSuperset(of: ids) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }
}
