import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Rows
extension DeviceLibraryBrowserView {
    func songRow(_ song: DeviceManager.ExportableSongInfo) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                artworkView(for: song)

                if isSelectionMode {
                    Circle()
                        .fill(selectedIDs.contains(song.id) ? Color(red: 1.0, green: 0.27, blue: 0.42) : Color.black.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedIDs.contains(song.id)
                                    ? Color(red: 1.0, green: 0.27, blue: 0.42)
                                    : Color.white.opacity(0.22),
                                    lineWidth: 1.5
                                )
                        )
                        .overlay(
                            Image(systemName: selectedIDs.contains(song.id) ? "checkmark" : "circle.fill")
                                .font(.system(size: selectedIDs.contains(song.id) ? 10 : 7, weight: .bold))
                                .foregroundStyle(selectedIDs.contains(song.id) ? .white : Color.clear)
                        )
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    if isSelectionMode && selectedIDs.contains(song.id) {
                        Text("READY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.27, blue: 0.42).opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(1)
                Text(song.album)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear {
            loadArtworkIfNeeded(for: song)
        }
        .onTapGesture {
            if isSelectionMode {
                toggleSelection(song.id)
            } else {
                songForQualityAnalysis = song
            }
        }
        .contextMenu {
            if !isSelectionMode {
                Button {
                    beginEditing(song)
                } label: {
                    Label("Edit Metadata", systemImage: "pencil")
                }

                Button {
                    songForAudioReplace = song
                } label: {
                    Label("Replace Audio File", systemImage: "waveform.badge.exclamationmark")
                }

                Button(role: .destructive) {
                    songPendingDeletion = song
                } label: {
                    Label("Delete Song", systemImage: "trash")
                }
            }
        }
    }

    func artistRow(_ artist: ArtistEntry) -> some View {
        NavigationLink {
            groupedSongListView(
                title: artist.name,
                subtitle: "\(artist.songs.count) song\(artist.songs.count == 1 ? "" : "s")",
                songs: artist.songs
            )
        } label: {
            HStack(spacing: 10) {
                artistArtworkView(artist)

                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text("\(artist.songs.count) song\(artist.songs.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mutedTextColor.opacity(0.8))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if let firstSong = artist.songs.first {
                loadArtworkIfNeeded(for: firstSong)
            }
        }
    }

    func albumRow(_ album: AlbumEntry) -> some View {
        NavigationLink {
            groupedSongListView(
                title: album.name,
                subtitle: album.artist,
                songs: album.songs,
                onEdit: { editingAlbum = album },
                onAddSongs: { addingSongsToAlbum = album }
            )
        } label: {
            HStack(spacing: 10) {
                albumArtworkView(album)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor)
                        .lineLimit(1)
                    Text("\(album.songs.count) track\(album.songs.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor.opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mutedTextColor.opacity(0.8))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if let firstSong = album.songs.first {
                loadArtworkIfNeeded(for: firstSong)
            }
        }
    }

    func groupedSongListView(
        title: String,
        subtitle: String,
        songs: [DeviceManager.ExportableSongInfo],
        onEdit: (() -> Void)? = nil,
        onAddSongs: (() -> Void)? = nil
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(strongTextColor)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                    Text("\(songs.count) song\(songs.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                HStack(spacing: 12) {
                    Button {
                        if isSelectionMode {
                            isSelectionMode = false
                        } else {
                            isSelectionMode = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .semibold))
                            Text(isSelectionMode ? "Done" : "Select")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(strongTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Capsule()
                                .fill(controlFillColor)
                                .overlay(
                                    Capsule()
                                        .stroke(hairlineColor, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    if isSelectionMode {
                        Button {
                            selectAll(in: songs)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: areAllSelected(in: songs) ? "checkmark.circle.fill" : "checklist")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(areAllSelected(in: songs) ? "Clear All" : "Select All")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let onEdit {
                        Button(action: onEdit) {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Edit")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let onAddSongs {
                        Button(action: onAddSongs) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Add Songs")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        songRow(song)
                        if index < songs.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            for song in songs.prefix(18) {
                loadArtworkIfNeeded(for: song)
            }
        }
    }
}
