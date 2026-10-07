import SwiftUI

struct PlaylistBackupSelectorSheet: View {
    @ObservedObject var manager: DeviceManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var onCompletion: (String, [URL]) -> Void
    
    @State private var isLoading = false
    @State private var playlists: [ExportablePlaylist] = []
    @State private var deviceSongs: [DeviceManager.ExportableSongInfo] = []
    @State private var selectedPids = Set<Int64>()
    @State private var searchText = ""

    private var pageBackground: Color { Color(.systemGroupedBackground) }
    private var cardBackground: Color { Color(.secondarySystemGroupedBackground) }

    struct ExportablePlaylist: Identifiable, Equatable {
        let name: String
        let pid: Int64
        let songPids: [Int64]
        var id: Int64 { pid }
    }

    var filteredPlaylists: [ExportablePlaylist] {
        if searchText.isEmpty { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search Playlists", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if isLoading {
                        Spacer()
                        ProgressView("Loading device playlists...")
                        Spacer()
                    } else if playlists.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No playlists found on this device.")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        HStack {
                            Button("Select All") {
                                selectedPids = Set(filteredPlaylists.map(\.pid))
                            }
                            .font(.subheadline)
                            
                            Spacer()
                            
                            Button("Deselect All") {
                                selectedPids.removeAll()
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(filteredPlaylists) { playlist in
                                    Button {
                                        if selectedPids.contains(playlist.pid) {
                                            selectedPids.remove(playlist.pid)
                                        } else {
                                            selectedPids.insert(playlist.pid)
                                        }
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: selectedPids.contains(playlist.pid) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundColor(selectedPids.contains(playlist.pid) ? .accentColor : .secondary)
                                                .frame(width: 24)

                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.secondary)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(playlist.name)
                                                    .font(.body.weight(.medium))
                                                    .foregroundColor(.primary)
                                                Text("\(playlist.songPids.count) tracks")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                    }
                                    
                                    if playlist.id != filteredPlaylists.last?.id {
                                        Divider().padding(.leading, 54)
                                    }
                                }
                            }
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            performBackup()
                        } label: {
                            Text(selectedPids.isEmpty ? "Select Playlists" : "Back Up \(selectedPids.count) Playlists")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(selectedPids.isEmpty ? Color.secondary : Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedPids.isEmpty)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Backup Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchPlaylists()
            }

        }
    }

    private func fetchPlaylists() {
        isLoading = true
        manager.fetchExportableSongs { fetchedSongs in
            self.deviceSongs = fetchedSongs
            manager.fetchExportablePlaylists { fetchedPlaylists in
                DispatchQueue.main.async {
                    self.playlists = fetchedPlaylists.map { p in
                        ExportablePlaylist(name: p.name, pid: p.pid, songPids: p.songPids)
                    }
                    self.isLoading = false
                }
            }
        }
    }

    private func performBackup() {
        var exportedURLs: [URL] = []
        let backupsDir = URL.documentsDirectory.appendingPathComponent("PlaylistBackups", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        for playlist in playlists where selectedPids.contains(playlist.pid) {
            let pSongs = playlist.songPids.compactMap { pid in
                deviceSongs.first(where: { $0.itemPid == pid })
            }
            
            var m3uContent = "#EXTM3U\n"
            m3uContent += "#EXT-BYETUNES-PLAYLIST:name=\(playlist.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? playlist.name)\n"
            
            for song in pSongs {
                let metaLine = encodeMetadata(
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    durationMs: song.durationMs,
                    fileSize: song.fileSize,
                    remoteFilename: song.suggestedFilename
                )
                m3uContent += "\(metaLine)\n"
                
                let durationInSeconds = song.durationMs / 1000
                m3uContent += "#EXTINF:\(durationInSeconds),\(song.artist) - \(song.title)\n"
                m3uContent += "\(song.suggestedFilename)\n"
            }
            
            let sanitizedName = DeviceManager.sanitizedExportFilenameBase(playlist.name)
            let fileURL = backupsDir.appendingPathComponent("\(sanitizedName).m3u")
            
            do {
                try m3uContent.write(to: fileURL, atomically: true, encoding: .utf8)
                exportedURLs.append(fileURL)
            } catch {
                Logger.shared.log("[PlaylistBackupSelectorSheet] Failed to write playlist backup \(playlist.name): \(error.localizedDescription)")
            }
        }

        if !exportedURLs.isEmpty {
            let text = "Successfully backed up \(exportedURLs.count) playlist(s) locally."
            onCompletion(text, exportedURLs)
            dismiss()
        }
    }

    private func encodeMetadata(title: String, artist: String, album: String, durationMs: Int, fileSize: Int, remoteFilename: String) -> String {
        let t = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let a = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let al = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let f = remoteFilename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "#EXT-BYETUNES-METADATA:title=\(t)&artist=\(a)&album=\(al)&durationMs=\(durationMs)&fileSize=\(fileSize)&remoteFilename=\(f)"
    }
}
