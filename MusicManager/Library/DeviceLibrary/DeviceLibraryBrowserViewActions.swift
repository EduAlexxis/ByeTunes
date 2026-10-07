import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Actions
extension DeviceLibraryBrowserView {
    func beginEditing(_ song: DeviceManager.ExportableSongInfo) {
        editingOriginalSong = song
        editingDraftSong = SongMetadata(
            localURL: FileManager.default.temporaryDirectory.appendingPathComponent(song.remoteFilename),
            title: song.title,
            artist: song.artist,
            album: song.album,
            albumArtist: nil,
            genre: song.genre,
            year: song.year,
            durationMs: song.durationMs,
            fileSize: song.fileSize,
            remoteFilename: song.remoteFilename,
            artworkData: artworkDataCache[song.id],
            explicitRating: song.explicitRating
        )
        editingDraftSong.trackNumber = song.trackNumber
        editingDraftSong.lyrics = song.lyrics
        showingMetadataEditor = true
    }

    func applyMetadataEdits(_ updatedSong: SongMetadata, original: DeviceManager.ExportableSongInfo) {
        isLoading = true
        statusMessage = ""
        manager.updateExportableSongMetadata(original: original, updatedSong: updatedSong) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    func applyAlbumMetadataEdits(
        to targetSongs: [DeviceManager.ExportableSongInfo],
        artist: String,
        album: String,
        genre: String,
        year: Int,
        artworkData: Data?,
        explicitRating: Int?
    ) {
        guard !targetSongs.isEmpty else { return }
        isLoading = true
        isApplyingAlbumEdit = true
        statusMessage = ""
        manager.updateExportableSongsMetadata(
            originals: targetSongs,
            artist: artist,
            album: album,
            genre: genre,
            year: year,
            artworkData: artworkData,
            explicitRating: explicitRating
        ) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                isApplyingAlbumEdit = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    func suggestedSongs(
        for album: AlbumEntry,
        in candidates: [DeviceManager.ExportableSongInfo]
    ) -> [DeviceManager.ExportableSongInfo] {
        let albumYear = album.songs.first(where: { $0.year > 0 })?.year ?? 0
        let normalizedAlbumArtist = album.artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return candidates
            .filter { candidate in
                let normalizedCandidateArtist = candidate.artist
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard normalizedCandidateArtist == normalizedAlbumArtist else { return false }
                guard albumYear > 0, candidate.year > 0 else { return true }
                return abs(candidate.year - albumYear) <= 1
            }
            .sorted { lhs, rhs in
                if albumYear > 0, lhs.year > 0, rhs.year > 0 {
                    let lhsDistance = abs(lhs.year - albumYear)
                    let rhsDistance = abs(rhs.year - albumYear)
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func replaceSongAudioFile(_ song: DeviceManager.ExportableSongInfo, with newLocalURL: URL) {
        isLoading = true
        statusMessage = "Replacing audio file for \(song.title)..."
        manager.replaceExportableSongAudioFile(original: song, newLocalURL: newLocalURL) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    func deleteSong(_ song: DeviceManager.ExportableSongInfo) {
        isLoading = true
        statusMessage = ""
        manager.deleteExportableSong(song) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    selectedIDs.remove(song.id)
                    if selectedIDs.isEmpty {
                        isSelectionMode = false
                    }
                    refreshSongs()
                }
            }
        }
    }

    func deleteSelectedSongs() {
        let items = selectedSongs
        guard !items.isEmpty else { return }

        isLoading = true
        statusMessage = ""
        manager.deleteExportableSongs(items) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    selectedIDs.subtract(items.map(\.id))
                    isSelectionMode = false
                    refreshSongs()
                }
            }
        }
    }

    func exportSelectedSongs() {
        let items = selectedSongs
        guard !items.isEmpty else { return }

        let exportFolder = preferredExportFolder
        if exportFolder == nil && !hasSavedExportFolder {
            pendingExportAfterFolderSelection = true
            showingFolderPicker = true
            return
        }

        isExporting = true
        statusMessage = "Exporting \(items.count) song(s) to \(exportFolder?.lastPathComponent ?? "the app folder")..."
        manager.exportSongs(items, destinationFolder: exportFolder) { success, message, _ in
            DispatchQueue.main.async {
                isExporting = false
                statusMessage = success ? message : "\(message) Tap Change Folder and pick another location."
            }
        }
    }

    var selectedPlaylistSongs: [DeviceManager.ExportableSongInfo] {
        var seenIDs = Set<String>()
        return playlists
            .filter { selectedPlaylistPids.contains($0.pid) }
            .flatMap(\.songs)
            .filter { seenIDs.insert($0.id).inserted }
    }

    func exportSelectedPlaylists() {
        let items = selectedPlaylistSongs
        guard !items.isEmpty else { return }

        let exportFolder = preferredExportFolder
        if exportFolder == nil && !hasSavedExportFolder {
            pendingPlaylistExportAfterFolderSelection = true
            showingFolderPicker = true
            return
        }

        isExporting = true
        statusMessage = "Exporting \(items.count) song(s) to \(exportFolder?.lastPathComponent ?? "the app folder")..."
        manager.exportSongs(items, destinationFolder: exportFolder) { success, message, _ in
            DispatchQueue.main.async {
                isExporting = false
                statusMessage = success ? message : "\(message) Tap Change Folder and pick another location."
            }
        }
    }

    func handleExportFolderSelection(url: URL?) {
        guard let url else {
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            return
        }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.exportFolderBookmarkKey)
            statusMessage = "Export folder set to \(url.lastPathComponent)."
            let shouldExportSongsNow = pendingExportAfterFolderSelection
            let shouldExportPlaylistsNow = pendingPlaylistExportAfterFolderSelection
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            if shouldExportSongsNow {
                DispatchQueue.main.async {
                    exportSelectedSongs()
                }
            } else if shouldExportPlaylistsNow {
                DispatchQueue.main.async {
                    exportSelectedPlaylists()
                }
            }
        } catch {
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            statusMessage = "Could not save export folder."
        }
    }

    static func resolveBookmarkedFolder(forKey key: String) -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
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
                UserDefaults.standard.set(refreshedBookmark, forKey: key)
            }

            return url
        } catch {
            if !Self.didLogExportBookmarkResolutionFailure {
                Self.didLogExportBookmarkResolutionFailure = true
                Logger.shared.log("[Export] Failed to resolve export folder bookmark: \(error)")
            }
            return nil
        }
    }
}
