import SwiftUI

extension DeviceLibraryBrowserView {
    func playlistsInFolder(_ folder: PlaylistFolderInfo) -> [PlaylistEntry] {
        playlists.filter { manager.playlistParents[$0.pid] == folder.pid }
    }

    @ViewBuilder
    func playlistFolderRows() -> some View {
        ForEach(manager.playlistFolders) { folder in
            NavigationLink(destination: playlistFolderDetailView(folder)) {
                folderRow(folder)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    renameFolderPid = folder.pid
                    renameFolderText = folder.name
                    showingRenameFolderPrompt = true
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    applyPlaylistActions([.deleteFolder(containerPid: folder.pid)])
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
            Divider().overlay(hairlineColor).padding(.leading, 64)
        }
    }

    private func folderRow(_ folder: PlaylistFolderInfo) -> some View {
        let count = playlistsInFolder(folder).count
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: 48, height: 48)
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(mutedTextColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                Text("\(count) playlist\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(mutedTextColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    var newFolderButton: some View {
        Button {
            newFolderName = ""
            showingNewFolderPrompt = true
        } label: {
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("New Folder")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func moveToFolderMenu(for playlist: PlaylistEntry) -> some View {
        let currentFolder = manager.playlistParents[playlist.pid]
        if !manager.playlistFolders.isEmpty || currentFolder != nil {
            Menu {
                ForEach(manager.playlistFolders.filter { $0.pid != currentFolder }) { folder in
                    Button {
                        applyPlaylistActions([.movePlaylist(containerPid: playlist.pid, folderPid: folder.pid)])
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
                if currentFolder != nil {
                    Button {
                        applyPlaylistActions([.movePlaylist(containerPid: playlist.pid, folderPid: 0)])
                    } label: {
                        Label("Remove from Folder", systemImage: "folder.badge.minus")
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
    }

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        applyPlaylistActions([.createFolder(containerPid: pid, name: trimmed)])
    }

    func playlistFolderDetailView(_ folder: PlaylistFolderInfo) -> some View {
        let current = manager.playlistFolders.first(where: { $0.pid == folder.pid }) ?? folder
        let contents = playlistsInFolder(current)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(current.name)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(strongTextColor)
                            .lineLimit(1)
                        Button {
                            renameFolderPid = current.pid
                            renameFolderText = current.name
                            showingRenameFolderPrompt = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(mutedTextColor)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(contents.count) playlist\(contents.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                if contents.isEmpty {
                    Text("This folder is empty. Press and hold a playlist and choose Move to Folder.")
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(contents) { playlist in
                        NavigationLink(destination: playlistDetailView(playlist)) {
                            playlistRowContent(playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            moveToFolderMenu(for: playlist)
                        }
                        Divider().overlay(hairlineColor).padding(.leading, 64)
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
    }
}
