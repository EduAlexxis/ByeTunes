import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Playlists
extension DeviceLibraryBrowserView {
    func playlistRowContent(_ playlist: PlaylistEntry) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: 48, height: 48)
                if let cover = playlist.coverImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(mutedTextColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(playlist.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(strongTextColor)
                    if SmartPlaylistStore.record(forPid: playlist.pid) != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    }
                }
                Text("\(playlist.songs.count) songs")
                    .font(.subheadline)
                    .foregroundStyle(mutedTextColor)
            }
            Spacer()
            if isSelectionMode {
                if selectedPlaylistPids.contains(playlist.pid) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                } else {
                    Circle()
                        .stroke(mutedTextColor, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    func playlistListView() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Button {
                showingNewPlaylistPrompt = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("New Playlist")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().overlay(hairlineColor).padding(.leading, 64)

            Button {
                showingSmartPlaylistBuilder = true
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("New Smart Playlist")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().overlay(hairlineColor).padding(.leading, 64)

            ForEach(playlists) { playlist in
                Group {
                    if isSelectionMode {
                        Button {
                            togglePlaylistSelection(playlist.pid)
                        } label: {
                            playlistRowContent(playlist)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: playlistDetailView(playlist)) {
                            playlistRowContent(playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if manager.pinnedPlaylistPids.contains(playlist.pid) {
                                Button {
                                    applyPlaylistActions([.unpin(containerPid: playlist.pid)])
                                } label: {
                                    Label("Unpin from Music", systemImage: "pin.slash")
                                }
                            } else {
                                Button {
                                    applyPlaylistActions([.pin(containerPid: playlist.pid)])
                                } label: {
                                    Label("Pin to Music", systemImage: "pin")
                                }
                            }
                            if SmartPlaylistStore.record(forPid: playlist.pid) != nil {
                                Button {
                                    refreshSmartPlaylist(playlist)
                                } label: {
                                    Label("Refresh Smart Playlist", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            Button(role: .destructive) {
                                applyPlaylistActions([.delete(containerPid: playlist.pid)])
                            } label: {
                                Label("Delete Playlist", systemImage: "trash")
                            }
                        }
                    }
                }

                Divider()
                    .overlay(hairlineColor)
                    .padding(.leading, 64)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingNewPlaylistPrompt) {
            PlaylistNamingView(title: "New Playlist", icon: "music.note.list", iconTint: Color(red: 1.0, green: 0.27, blue: 0.42)) { name, coverImageData in
                guard !name.isEmpty else { return }
                applyPlaylistActions([.create(name: name)]) {
                    if let coverImageData, let matched = playlists.first(where: { $0.name == name }) {
                        applyPlaylistActions([.setCoverArtwork(containerPid: matched.pid, imageData: coverImageData)])
                    }
                }
            }
        }
        .sheet(isPresented: $showingSmartPlaylistBuilder) {
            SmartPlaylistBuilderView(songs: songs) { name, songPids, rule, coverImageData in
                applyPlaylistActions([.createWithSongs(name: name, songPids: songPids)]) {
                    guard let matched = playlists.first(where: { $0.name == name }) else { return }
                    SmartPlaylistStore.save(SmartPlaylistRecord(name: matched.name, containerPid: matched.pid, rule: rule))
                    if let coverImageData {
                        applyPlaylistActions([.setCoverArtwork(containerPid: matched.pid, imageData: coverImageData)])
                    }
                }
            }
        }
    }

    func refreshSmartPlaylist(_ playlist: PlaylistEntry) {
        guard let record = SmartPlaylistStore.record(forPid: playlist.pid) else { return }
        let matchingPids = Set(record.rule.matchingSongs(in: songs).map(\.itemPid))
        let currentPids = Set(playlist.songs.map(\.itemPid))
        guard matchingPids != currentPids else { return }

        var actions: [DeviceManager.PlaylistAction] = []
        let toAdd = Array(matchingPids.subtracting(currentPids))
        if !toAdd.isEmpty {
            actions.append(.addSongs(containerPid: playlist.pid, itemPids: toAdd))
        }
        for pid in currentPids.subtracting(matchingPids) {
            actions.append(.removeSong(containerPid: playlist.pid, itemPid: pid))
        }
        applyPlaylistActions(actions)
    }

    func applyPlaylistActions(_ actions: [DeviceManager.PlaylistAction], onSynced: (() -> Void)? = nil) {
        guard !actions.isEmpty else { return }

        for action in actions {
            switch action {
            case .create(let name):
                let newId = Int64.random(in: 1000...9000)
                playlists.append(PlaylistEntry(name: name, pid: newId, songs: []))
            case .createWithSongs(let name, let songPids):
                let newId = Int64.random(in: 1000...9000)
                let newSongs = songPids.compactMap { pid in songs.first(where: { $0.itemPid == pid }) }
                playlists.append(PlaylistEntry(name: name, pid: newId, songs: newSongs))
            case .delete(let containerPid):
                playlists.removeAll { $0.pid == containerPid }
                SmartPlaylistStore.remove(forPid: containerPid)
            case .rename(let containerPid, let newName):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].name = newName
                }
            case .removeSong(let containerPid, let itemPid):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].songs.removeAll { $0.itemPid == itemPid }
                }
            case .reorder(let containerPid, let orderedItemPids):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    let sortedSongs = orderedItemPids.compactMap { pid in
                        playlists[idx].songs.first(where: { $0.itemPid == pid })
                    }
                    if sortedSongs.count == playlists[idx].songs.count {
                        playlists[idx].songs = sortedSongs
                    }
                }
            case .addSongs(let containerPid, let itemPids):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    let newSongs = itemPids.compactMap { pid in songs.first(where: { $0.itemPid == pid }) }
                    playlists[idx].songs.append(contentsOf: newSongs)
                }
            case .setCoverArtwork(let containerPid, let imageData):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].coverImage = UIImage(data: imageData)
                }
            case .pin(let containerPid):
                manager.pinnedPlaylistPids.insert(containerPid)
            case .unpin(let containerPid):
                manager.pinnedPlaylistPids.remove(containerPid)
            }
        }
        
        isSyncingPlaylists = true
        manager.applyPlaylistEdits(actions: actions) { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSyncingPlaylists = false
                if success {
                    refreshSongs {
                        onSynced?()
                    }
                } else {
                    statusMessage = "Sync failed: \(error)"
                    refreshSongs()
                }
            }
        }
    }
    

    func playlistDetailView(_ playlist: PlaylistEntry) -> some View {
        let current = playlists.first(where: { $0.pid == playlist.pid }) ?? playlist

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(current.name)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(strongTextColor)
                            .lineLimit(1)

                        Button {
                            renamePlaylistPid = current.pid
                            renamePlaylistText = current.name
                            showingRenamePlaylistPrompt = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(mutedTextColor)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(current.songs.count) song\(current.songs.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                HStack(spacing: 12) {
                    Button {
                        addingToPlaylistPid = current.pid
                    } label: {
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

                    pinPlaylistButton(for: current)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(current.songs.enumerated()), id: \.element.id) { index, song in
                        playlistSongRow(song, playlist: current)
                        if index < current.songs.count - 1 {
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
        .sheet(item: Binding(
            get: { addingToPlaylistPid.map { AddSheetItem(pid: $0) } },
            set: { addingToPlaylistPid = $0?.pid }
        )) { item in
            AddSongsToPlaylistSheet(
                allSongs: songs,
                playlistPid: item.pid,
                onAdd: { itemPids in
                    applyPlaylistActions([.addSongs(containerPid: item.pid, itemPids: itemPids)])
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Rename Playlist", isPresented: $showingRenamePlaylistPrompt) {
            TextField("Name", text: $renamePlaylistText)
            Button("Cancel", role: .cancel) { renamePlaylistPid = nil }
            Button("Save") {
                if let pid = renamePlaylistPid, !renamePlaylistText.isEmpty {
                    applyPlaylistActions([.rename(containerPid: pid, newName: renamePlaylistText)])
                }
                renamePlaylistPid = nil
            }
        }
    }

    func pinPlaylistButton(for playlist: PlaylistEntry) -> some View {
        PlaylistPinButton(
            manager: manager,
            playlistPid: playlist.pid,
            isSyncing: $isSyncingPlaylists,
            textColor: strongTextColor,
            fillColor: controlFillColor,
            strokeColor: hairlineColor
        ) { isPinned in
            applyPlaylistActions([isPinned ? .unpin(containerPid: playlist.pid) : .pin(containerPid: playlist.pid)])
        }
    }

    struct AddSheetItem: Identifiable {
        let pid: Int64
        var id: Int64 { pid }
    }

    func playlistSongRow(_ song: DeviceManager.ExportableSongInfo, playlist: PlaylistEntry) -> some View {
        HStack(spacing: 14) {
            artworkView(for: song)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(strongTextColor)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear { loadArtworkIfNeeded(for: song) }
        .contextMenu {
            Button(role: .destructive) {
                applyPlaylistActions([.removeSong(containerPid: playlist.pid, itemPid: song.itemPid)])
            } label: {
                Label("Remove from Playlist", systemImage: "trash")
            }
        }
    }
}
