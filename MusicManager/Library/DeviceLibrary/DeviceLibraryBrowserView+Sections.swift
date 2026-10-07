import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Sections
extension DeviceLibraryBrowserView {
    var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                topBarIconButton(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                refreshSongs()
            } label: {
                topBarIconButton(systemName: "arrow.clockwise", showsProgress: isLoading)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isExporting)
        }
    }

    var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryModeSwitcher

            if libraryMode == .playlists {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        actionCapsule(
                            title: isSelectionMode ? "Done" : "Select",
                            systemImage: "checklist",
                            isPrimary: false,
                            isDisabled: isLoading || playlists.isEmpty
                        ) {
                            isSelectionMode.toggle()
                            if !isSelectionMode { selectedPlaylistPids.removeAll() }
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: allPlaylistsSelected ? "Clear All" : "Select All",
                                systemImage: allPlaylistsSelected ? "checkmark.circle.fill" : "checklist",
                                isPrimary: false,
                                isDisabled: playlists.isEmpty
                            ) {
                                toggleAllPlaylistsSelection()
                            }

                            actionCapsule(
                                title: isExporting ? "Exporting..." : "Export",
                                systemImage: "square.and.arrow.up",
                                isPrimary: false,
                                isDisabled: selectedPlaylistPids.isEmpty || isLoading || isExporting
                            ) {
                                exportSelectedPlaylists()
                            }

                            actionCapsule(
                                title: "Delete",
                                systemImage: "trash",
                                isPrimary: false,
                                isDestructive: true,
                                isDisabled: selectedPlaylistPids.isEmpty
                            ) {
                                showingDeletePlaylistsConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else if libraryMode == .songs {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        actionCapsule(
                            title: isSelectionMode ? "Done" : "Select",
                            systemImage: "checklist",
                            isPrimary: false,
                            isDisabled: isLoading || filteredSongs.isEmpty || isExporting
                        ) {
                            if isSelectionMode {
                                isSelectionMode = false
                            } else {
                                isSelectionMode = true
                            }
                        }

                        actionCapsule(
                            title: isSelectionMode ? (allFilteredSongsSelected ? "Clear All" : "Select All") : "Folder",
                            systemImage: isSelectionMode ? (allFilteredSongsSelected ? "checkmark.circle.fill" : "checklist") : "folder",
                            isPrimary: false,
                            isDisabled: isExporting || (isSelectionMode && filteredSongs.isEmpty)
                        ) {
                            if isSelectionMode {
                                toggleVisibleSelection()
                            } else {
                                pendingExportAfterFolderSelection = false
                                showingFolderPicker = true
                            }
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: "Add to Playlist",
                                systemImage: "text.badge.plus",
                                isPrimary: false,
                                isDisabled: selectedIDs.isEmpty || playlists.isEmpty
                            ) {
                                showingAddToPlaylistSheet = true
                            }

                            actionCapsule(
                                title: "Add to Album",
                                systemImage: "square.stack.badge.plus",
                                isPrimary: false,
                                isDisabled: selectedIDs.isEmpty
                            ) {
                                showingAddToAlbumSheet = true
                            }
                        } else {
                            sortMenu

                            if availableGenres.count > 1 {
                                genreFilterMenu
                            }
                        }

                        actionCapsule(
                            title: isExporting ? "Exporting..." : "Export",
                            systemImage: "square.and.arrow.up",
                            isPrimary: false,
                            isDisabled: selectedIDs.isEmpty || isLoading || isExporting
                        ) {
                            exportSelectedSongs()
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: "Delete",
                                systemImage: "trash",
                                isPrimary: false,
                                isDestructive: true,
                                isDisabled: selectedIDs.isEmpty || isLoading || isExporting
                            ) {
                                showingBatchDeleteSongsConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            searchField

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(2)
            }
        }
    }

    var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(mutedTextColor)

            TextField("Search on-device songs", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(strongTextColor)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(mutedTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(hairlineColor, lineWidth: 1)
                )
        )
    }

    var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading library...")
                .font(.subheadline)
                .foregroundStyle(mutedTextColor)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.title3.weight(.semibold))
                .foregroundStyle(strongTextColor)

            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(mutedTextColor)
                Text("No Songs Found")
                    .font(.headline)
                    .foregroundStyle(strongTextColor)
                Text("Could not read any exportable songs from the device library.")
                    .font(.subheadline)
                    .foregroundStyle(mutedTextColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(24)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    var songsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(searchText.isEmpty ? libraryMode.rawValue : "Results")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                Spacer()
                Text(summaryCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mutedTextColor)
            }

            switch libraryMode {
            case .songs:
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(cachedGroupedSongs, id: \.key) { section in
                        if !section.key.isEmpty {
                            Text(section.key)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(strongTextColor)
                                .padding(.top, section.key == cachedGroupedSongs.first?.key ? 2 : 18)
                                .padding(.bottom, 8)
                        }

                        ForEach(Array(section.songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song)
                            if index < section.songs.count - 1 {
                                Divider()
                                    .overlay(hairlineColor)
                                    .padding(.leading, 64)
                            }
                        }
                    }
                }
                .id(cachedGroupedSongs.count)
            case .artists:
                LazyVStack(spacing: 0) {
                    ForEach(Array(cachedArtistEntries.enumerated()), id: \.element.id) { index, artist in
                        artistRow(artist)
                        if index < cachedArtistEntries.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
                .id(cachedArtistEntries.count)
            case .albums:
                LazyVStack(spacing: 0) {
                    ForEach(Array(cachedAlbumEntries.enumerated()), id: \.element.id) { index, album in
                        albumRow(album)
                        if index < cachedAlbumEntries.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
                .id(cachedAlbumEntries.count)
            case .playlists:
                playlistListView()
            }
        }
    }
}
