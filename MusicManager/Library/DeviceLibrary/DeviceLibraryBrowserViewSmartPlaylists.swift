import SwiftUI

extension DeviceLibraryBrowserView {
    private var savedOnlySmartPlaylists: [NativeSmartPlaylist] {
        let devicePids = Set(manager.nativeSmartPlaylists.map(\.pid))
        return SmartPlaylistStore.loadAll().compactMap { record in
            guard let criteria = record.criteria, !devicePids.contains(record.containerPid) else { return nil }
            return NativeSmartPlaylist(pid: record.containerPid, name: record.name, criteria: criteria, limit: record.limit ?? SmartPlaylistLimit())
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isSavedInByeTunes(_ pid: Int64) -> Bool {
        SmartPlaylistStore.record(forPid: pid)?.criteria != nil
    }

    @ViewBuilder
    func nativeSmartPlaylistRows() -> some View {
        ForEach(manager.nativeSmartPlaylists) { smart in
            NavigationLink(destination: nativeSmartPlaylistDetailView(smart, isOnDevice: true)) {
                nativeSmartPlaylistRow(smart, subtitle: "Smart playlist · updates automatically")
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !isSavedInByeTunes(smart.pid) {
                    Button {
                        importNativeSmartPlaylist(smart)
                    } label: {
                        Label("Save to ByeTunes", systemImage: "square.and.arrow.down")
                    }
                }
                Button {
                    exportSmartPlaylists([smart], fileName: smart.name)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    manager.nativeSmartPlaylists.removeAll { $0.pid == smart.pid }
                    applyPlaylistActions([.delete(containerPid: smart.pid)])
                } label: {
                    Label("Delete Playlist", systemImage: "trash")
                }
            }
            Divider().overlay(hairlineColor).padding(.leading, 64)
        }
        ForEach(savedOnlySmartPlaylists) { smart in
            NavigationLink(destination: nativeSmartPlaylistDetailView(smart, isOnDevice: false)) {
                nativeSmartPlaylistRow(smart, subtitle: "Saved in ByeTunes · not on this device")
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    exportSavedSmartPlaylist(smart)
                } label: {
                    Label("Add to Device", systemImage: "iphone.and.arrow.forward")
                }
                Button {
                    exportSmartPlaylists([smart], fileName: smart.name)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    SmartPlaylistStore.remove(forPid: smart.pid)
                    refreshSmartPlaylistList += 1
                } label: {
                    Label("Remove from ByeTunes", systemImage: "trash")
                }
            }
            Divider().overlay(hairlineColor).padding(.leading, 64)
        }
    }

    private func nativeSmartPlaylistRow(_ smart: NativeSmartPlaylist, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: 48, height: 48)
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(smart.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                Text(subtitle)
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

    func nativeSmartPlaylistDetailView(_ smart: NativeSmartPlaylist, isOnDevice: Bool) -> some View {
        let preview = smart.criteria.matchingSongs(in: songs)
        let lines = smart.criteria.summaryLines()
        let shown = smart.limit.isLimited ? Array(preview.songs.prefix(smart.limit.value)) : preview.songs
        let countText = "\(shown.count)\(preview.isComplete ? "" : "+") song\(shown.count == 1 ? "" : "s")"

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(smart.name)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(2)
                    Text("\(countText) · \(isOnDevice ? "Smart playlist" : "Saved in ByeTunes")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                        Text("RULES")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(mutedTextColor)
                            .tracking(0.5)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if smart.limit.isLimited {
                        Text("Limited to \(smart.limit.value) items")
                            .font(.footnote)
                            .foregroundStyle(mutedTextColor)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(controlFillColor))

                if isOnDevice && !isSavedInByeTunes(smart.pid) {
                    smartPlaylistActionButton("Save to ByeTunes", icon: "square.and.arrow.down") {
                        importNativeSmartPlaylist(smart)
                    }
                }
                if !isOnDevice {
                    smartPlaylistActionButton("Add to Device", icon: "iphone.and.arrow.forward") {
                        exportSavedSmartPlaylist(smart)
                    }
                }

                if !preview.isComplete {
                    Text("Some rules, like plays or favorites, can only be checked by Music, so the real playlist may have more songs.")
                        .font(.footnote)
                        .foregroundStyle(mutedTextColor)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, song in
                        smartPlaylistSongRow(song)
                        if index < shown.count - 1 {
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
    }

    private func smartPlaylistActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(strongTextColor)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(Capsule().stroke(hairlineColor, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func smartPlaylistSongRow(_ song: DeviceManager.ExportableSongInfo) -> some View {
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
    }

    var smartPlaylistFilesButton: some View {
        Menu {
            Button {
                smartImportFromDatabase = false
                showingSmartImporter = true
            } label: {
                Label("Import from File…", systemImage: "doc")
            }
            Button {
                smartImportFromDatabase = true
                showingSmartImporter = true
            } label: {
                Label("Import from a Library Database…", systemImage: "externaldrive")
            }
            Button {
                exportSmartPlaylists(allKnownSmartPlaylists, fileName: "Smart Playlists")
            } label: {
                Label("Export All Smart Playlists…", systemImage: "square.and.arrow.up")
            }
            .disabled(allKnownSmartPlaylists.isEmpty)
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Smart Playlist Files")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }
            .padding(.vertical, 14)
        }
    }

    private var allKnownSmartPlaylists: [NativeSmartPlaylist] {
        manager.nativeSmartPlaylists + savedOnlySmartPlaylists
    }

    func exportSmartPlaylists(_ playlists: [NativeSmartPlaylist], fileName: String) {
        guard let url = SmartPlaylistFile.writeTemporaryFile(playlists, fileName: fileName) else {
            statusMessage = "Could not create the export file."
            return
        }
        ShareSheetHelper.share(items: [url])
    }

    func handleSmartPlaylistImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let found: [NativeSmartPlaylist]
        if smartImportFromDatabase {
            found = SmartPlaylistFile.readDatabase(at: url)
        } else if let data = try? Data(contentsOf: url) {
            found = SmartPlaylistFile.decode(data)
        } else {
            found = []
        }

        guard !found.isEmpty else {
            statusMessage = smartImportFromDatabase ? "No smart playlists found in that database." : "No smart playlists found in that file."
            return
        }

        let existing = SmartPlaylistStore.loadAll()
        var added = 0
        for playlist in found {
            let isDuplicate = existing.contains { $0.name == playlist.name && $0.criteria == playlist.criteria }
                || manager.nativeSmartPlaylists.contains { $0.name == playlist.name && $0.criteria == playlist.criteria }
            if isDuplicate { continue }
            SmartPlaylistStore.save(SmartPlaylistRecord(name: playlist.name, containerPid: playlist.pid, rule: nil, criteria: playlist.criteria, limit: playlist.limit))
            added += 1
        }
        refreshSmartPlaylistList += 1
        statusMessage = added == 0 ? "Those smart playlists are already here." : "Imported \(added) smart playlist\(added == 1 ? "" : "s"). Open one and tap Add to Device."
    }

    func importNativeSmartPlaylist(_ smart: NativeSmartPlaylist) {
        SmartPlaylistStore.save(SmartPlaylistRecord(name: smart.name, containerPid: smart.pid, rule: nil, criteria: smart.criteria, limit: smart.limit))
        refreshSmartPlaylistList += 1
        statusMessage = "Saved \"\(smart.name)\" to ByeTunes."
    }

    func exportSavedSmartPlaylist(_ smart: NativeSmartPlaylist) {
        applyPlaylistActions([.createNativeSmart(containerPid: smart.pid, name: smart.name, criteria: smart.criteria, limit: smart.limit)])
    }

    func convertToNativeSmartPlaylist(_ playlist: PlaylistEntry) {
        guard let rule = SmartPlaylistStore.record(forPid: playlist.pid)?.rule, let criteria = rule.criteria() else {
            statusMessage = "This smart playlist can't be converted."
            return
        }
        let newPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        applyPlaylistActions([
            .createNativeSmart(containerPid: newPid, name: playlist.name, criteria: criteria, limit: SmartPlaylistLimit()),
            .delete(containerPid: playlist.pid)
        ])
    }
}
