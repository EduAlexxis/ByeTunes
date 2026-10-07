import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ManageBackupsView: View {
    @ObservedObject var manager: DeviceManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var snapshots: [DeviceManager.DatabaseSnapshotInfo] = []
    @State private var fullBackupFlags: [String: Bool] = [:]
    @State private var isSnapshotBusy = false
    @State private var isCreatingSnapshot = false
    @State private var isRestoringSnapshot = false
    @State private var snapshotProgressTitle = "Working on Backup"
    @State private var snapshotProgressMessage = ""
    @State private var snapshotProgress: Double? = nil
    @State private var snapshotPendingDeletion: DeviceManager.DatabaseSnapshotInfo?
    @State private var snapshotPendingRename: DeviceManager.DatabaseSnapshotInfo?
    @State private var renameText = ""
    @State private var showingRenameAlert = false
    @State private var showingImportPicker = false
    @State private var isImportingLibrary = false

    @State private var playlistBackups: [LocalPlaylistBackup] = []
    @State private var deviceSongs: [DeviceManager.ExportableSongInfo] = []
    @State private var existingPlaylists: [(name: String, pid: Int64)] = []
    @State private var isRestoringPlaylistAction = false
    @State private var playlistBackupPendingDeletion: LocalPlaylistBackup?
    


    @State private var showingRestoreConfirmationAlert = false
    @State private var pendingRestorePlaylistName = ""
    @State private var pendingRestoreSongPids: [Int64] = []
    @State private var pendingRestoreExistingPid: Int64? = nil
    @State private var pendingRestoreMissingCount = 0
    @State private var pendingRestoreTotalCount = 0
    @State private var pendingRestoreMissingSongs: [String] = []

    @State private var toastTitle = ""
    @State private var toastIcon = ""
    @State private var showToast = false

    private let playlistBackupsFolderName = "PlaylistBackups"

    struct LocalPlaylistBackup: Identifiable, Equatable {
        let id: UUID = UUID()
        let name: String
        let fileURL: URL
        let trackCount: Int
        let createdAt: Date
    }

    struct DecodedSongMetadata {
        var title: String
        var artist: String
        var album: String = ""
        var durationMs: Int = 0
        var fileSize: Int = 0
        var remoteFilename: String = ""
        var altTitle: String? = nil
        var altArtist: String? = nil
    }

    private var pageBackground: Color { Color(.systemGroupedBackground) }
    private var cardBackground: Color { Color(.secondarySystemGroupedBackground) }

    var body: some View {
        ZStack {
            pageBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DATABASE SNAPSHOTS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        if snapshots.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "externaldrive.badge.xmark")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No database snapshots found.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(snapshots) { snap in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(snap.displayName ?? formatSnapshotDate(snap.createdAt))
                                                    .font(.body.weight(.medium))
                                                    .foregroundColor(.primary)

                                                let isFull = fullBackupFlags[snap.folderName] ?? false
                                                Text(isFull ? "FULL" : "LIGHT")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue)
                                                    .cornerRadius(4)
                                            }

                                            Text(snapshotSubtitle(snap))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 12) {
                                            Button {
                                                restoreSnapshot(named: snap.folderName)
                                            } label: {
                                                Text("Restore")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.accentColor)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(!manager.heartbeatReady)
                                            .opacity(manager.heartbeatReady ? 1 : 0.4)

                                            Button {
                                                let root = manager.snapshotsDirectoryURL
                                                let folderURL = root.appendingPathComponent(snap.folderName, isDirectory: true)
                                                let needsSecurityScope = root.startAccessingSecurityScopedResource()
                                                ShareSheetHelper.share(items: [folderURL]) {
                                                    if needsSecurityScope {
                                                        root.stopAccessingSecurityScopedResource()
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.caption)
                                                    .foregroundColor(.accentColor)
                                                    .padding(8)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)

                                            Button {
                                                snapshotPendingDeletion = snap
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .contextMenu {
                                        Button {
                                            renameText = snap.displayName ?? ""
                                            snapshotPendingRename = snap
                                            showingRenameAlert = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                    }

                                    if snap.id != snapshots.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYLIST BACKUPS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        if playlistBackups.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("No local playlist backups found.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(playlistBackups) { backup in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(backup.name)
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)

                                            Text("\(backup.trackCount) tracks • \(formatSnapshotDate(backup.createdAt))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 12) {
                                            Button {
                                                restorePlaylist(from: backup.fileURL)
                                            } label: {
                                                Text("Restore")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.accentColor)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(isRestoringPlaylistAction || !manager.heartbeatReady)
                                            .opacity(manager.heartbeatReady ? 1 : 0.4)

                                            Button {
                                                ShareSheetHelper.share(items: [backup.fileURL])
                                            } label: {
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.caption)
                                                    .foregroundColor(.accentColor)
                                                    .padding(8)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)

                                            Button {
                                                playlistBackupPendingDeletion = backup
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .contextMenu {
                                        Button {
                                            ShareSheetHelper.share(items: [backup.fileURL])
                                        } label: {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }

                                        Button(role: .destructive) {
                                            playlistBackupPendingDeletion = backup
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                    if backup.id != playlistBackups.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Manage Backups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingImportPicker = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(isImportingLibrary)
            }
        }
        .sheet(isPresented: $showingImportPicker) {
            DocumentPicker(types: importablePickerTypes, asCopy: false) { url in
                handleImportSelection(url: url)
            }
        }
        .onAppear {
            refreshSnapshots()
            loadPlaylistBackups()
            loadDeviceSongsAndPlaylists()
        }
        .alert("Delete Database Backup?", isPresented: Binding(
            get: { snapshotPendingDeletion != nil },
            set: { if !$0 { snapshotPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                snapshotPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                guard let snapshot = snapshotPendingDeletion else { return }
                snapshotPendingDeletion = nil
                deleteSnapshot(named: snapshot.folderName)
            }
        } message: {
            Text(snapshotPendingDeletion.map { "Delete the backup from \(formatSnapshotDate($0.createdAt))? This cannot be undone." } ?? "")
        }
        .alert("Rename Backup", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                snapshotPendingRename = nil
                renameText = ""
            }
            Button("Save") {
                guard let snapshot = snapshotPendingRename else { return }
                manager.setDisplayName(renameText, for: snapshot.folderName)
                snapshotPendingRename = nil
                renameText = ""
                refreshSnapshots()
            }
        }
        .alert("Delete Playlist Backup?", isPresented: Binding(
            get: { playlistBackupPendingDeletion != nil },
            set: { if !$0 { playlistBackupPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                playlistBackupPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                guard let backup = playlistBackupPendingDeletion else { return }
                playlistBackupPendingDeletion = nil
                deletePlaylistBackup(backup)
            }
        } message: {
            Text(playlistBackupPendingDeletion.map { "Delete '\($0.name)'? This cannot be undone." } ?? "")
        }

        .alert("Restore Playlist", isPresented: $showingRestoreConfirmationAlert) {
            if pendingRestoreMissingCount == 0 {
                Button("Restore", role: .none) {
                    if let existingPid = pendingRestoreExistingPid {
                        executeRestorePlaylist(actions: [
                            .delete(containerPid: existingPid),
                            .createWithSongs(name: pendingRestorePlaylistName, songPids: pendingRestoreSongPids)
                        ])
                    } else {
                        executeRestorePlaylist(actions: [
                            .createWithSongs(name: pendingRestorePlaylistName, songPids: pendingRestoreSongPids)
                        ])
                    }
                }
            } else {
                Button("Restore Matched Tracks", role: .none) {
                    if let existingPid = pendingRestoreExistingPid {
                        executeRestorePlaylist(actions: [
                            .delete(containerPid: existingPid),
                            .createWithSongs(name: pendingRestorePlaylistName, songPids: pendingRestoreSongPids)
                        ])
                    } else {
                        executeRestorePlaylist(actions: [
                            .createWithSongs(name: pendingRestorePlaylistName, songPids: pendingRestoreSongPids)
                        ])
                    }
                }
            }

            if pendingRestoreExistingPid != nil {
                Button("Restore as New Copy", role: .none) {
                    executeRestorePlaylist(actions: [
                        .createWithSongs(name: "\(pendingRestorePlaylistName) (Restored)", songPids: pendingRestoreSongPids)
                    ])
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingRestoreMissingCount == 0 {
                Text("Ready to restore '\(pendingRestorePlaylistName)' with all \(pendingRestoreTotalCount) tracks.")
            } else {
                let matched = pendingRestoreTotalCount - pendingRestoreMissingCount
                let shown = pendingRestoreMissingSongs.prefix(5).joined(separator: "\n")
                let extra = pendingRestoreMissingSongs.count - min(5, pendingRestoreMissingSongs.count)
                let extraLine = extra > 0 ? "\n+\(extra) more" : ""
                Text("Matched \(matched) out of \(pendingRestoreTotalCount) tracks. \(pendingRestoreMissingCount) track\(pendingRestoreMissingCount == 1 ? "" : "s") couldn't be matched and won't be restored:\n\(shown)\(extraLine)")
            }
        }
        .overlay {
            if showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: toastIcon)
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)

                        Text(toastTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: showToast)
            }

            if isSnapshotBusy && (isCreatingSnapshot || isRestoringSnapshot) {
                snapshotProgressPopup
            }
        }
    }

    private func restoreSnapshot(named folderName: String) {
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = true
        updateSnapshotProgress(title: "Restoring Backup", message: "Preparing restore...", progress: nil)
        
        manager.restoreDatabaseSnapshot(named: folderName) { message, progress in
            DispatchQueue.main.async {
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: progress)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.isRestoringSnapshot = false
                self.updateSnapshotProgress(title: "Restoring Backup", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? message : "Restore Failed: \(message)",
                    icon: success ? "arrow.counterclockwise.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private var importablePickerTypes: [UTType] {
        [.folder, UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8")].compactMap { $0 }
    }

    private func handleImportSelection(url: URL?) {
        guard let url else { return }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            handleImportLibrarySelection(url: url)
        } else {
            handleImportPlaylistFileSelection(url: url)
        }
    }

    private func handleImportLibrarySelection(url: URL) {
        isImportingLibrary = true
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = true
        updateSnapshotProgress(title: "Importing Library", message: "Copying backup...", progress: nil)

        manager.importExternalSnapshot(from: url) { success, message in
            DispatchQueue.main.async {
                self.isImportingLibrary = false
                self.isSnapshotBusy = false
                self.isRestoringSnapshot = false
                self.updateSnapshotProgress(title: "Importing Library", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? "Library Imported" : "Import Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                if success {
                    self.refreshSnapshots()
                }
            }
        }
    }

    private func handleImportPlaylistFileSelection(url: URL) {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        let backupsDir = URL.documentsDirectory.appendingPathComponent(playlistBackupsFolderName, isDirectory: true)
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        var destination = backupsDir.appendingPathComponent(url.lastPathComponent)
        var suffix = 1
        while fm.fileExists(atPath: destination.path) {
            let base = url.deletingPathExtension().lastPathComponent
            destination = backupsDir.appendingPathComponent("\(base)-\(suffix).\(url.pathExtension)")
            suffix += 1
        }

        do {
            try fm.copyItem(at: url, to: destination)
            showToastMessage(title: "Playlist Imported", icon: "checkmark.circle.fill")
            loadPlaylistBackups()
        } catch {
            showToastMessage(title: "Import Failed: \(error.localizedDescription)", icon: "xmark.circle.fill")
        }
    }

    private func deleteSnapshot(named folderName: String) {
        isSnapshotBusy = true
        isCreatingSnapshot = false
        isRestoringSnapshot = false
        
        manager.deleteDatabaseSnapshot(named: folderName) { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.showToastMessage(
                    title: success ? message : "Delete Failed: \(message)",
                    icon: success ? "trash.circle.fill" : "xmark.circle.fill"
                )
                self.refreshSnapshots()
            }
        }
    }

    private func refreshSnapshots() {
        manager.fetchDatabaseSnapshots { list in
            DispatchQueue.main.async {
                self.snapshots = list

                manager.withSnapshotsDirectoryAccess {
                    let fm = FileManager.default
                    let root = manager.snapshotsDirectoryURL
                    var flags: [String: Bool] = [:]
                    for snap in list {
                        let fullMarker = root.appendingPathComponent(snap.folderName).appendingPathComponent(".iTunesFullBackup")
                        flags[snap.folderName] = fm.fileExists(atPath: fullMarker.path)
                    }
                    self.fullBackupFlags = flags
                }
            }
        }
    }

    // MARK: - Snapshot Helpers
    private func updateSnapshotProgress(title: String, message: String, progress: Double?) {
        snapshotProgressTitle = title
        snapshotProgressMessage = message.isEmpty ? "Working..." : message
        snapshotProgress = progress.map { min(max($0, 0), 1) }
    }

    private func formatSnapshotDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func snapshotSubtitle(_ snap: DeviceManager.DatabaseSnapshotInfo) -> String {
        let base = "\(snap.songCount) songs • \(formattedSize(snap.sizeBytes))"
        if snap.displayName != nil {
            return "\(base) • \(formatSnapshotDate(snap.createdAt))"
        }
        return "\(base) • \(snap.folderName)"
    }

    // MARK: - Playlist Backups Loading & Restoring
    private func loadPlaylistBackups() {
        let fm = FileManager.default
        let backupsDir = URL.documentsDirectory.appendingPathComponent(playlistBackupsFolderName, isDirectory: true)
        let hiddenDir = URL.documentsDirectory.appendingPathComponent(".playlist_backups", isDirectory: true)
        
        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: hiddenDir.path) {
            if let files = try? fm.contentsOfDirectory(at: hiddenDir, includingPropertiesForKeys: nil) {
                for file in files {
                    let dest = backupsDir.appendingPathComponent(file.lastPathComponent)
                    try? fm.removeItem(at: dest)
                    try? fm.moveItem(at: file, to: dest)
                }
            }
            try? fm.removeItem(at: hiddenDir)
        }

        let legacyDir = URL.documentsDirectory.appendingPathComponent("Playlist Backups", isDirectory: true)
        if fm.fileExists(atPath: legacyDir.path) {
            if !fm.fileExists(atPath: backupsDir.path) {
                try? fm.moveItem(at: legacyDir, to: backupsDir)
            } else {
                if let files = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) {
                    for file in files {
                        let dest = backupsDir.appendingPathComponent(file.lastPathComponent)
                        try? fm.removeItem(at: dest)
                        try? fm.moveItem(at: file, to: dest)
                    }
                }
                try? fm.removeItem(at: legacyDir)
            }
        }

        guard let files = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
            self.playlistBackups = []
            return
        }
        
        var list: [LocalPlaylistBackup] = []
        for file in files where ["m3u", "m3u8"].contains(file.pathExtension.lowercased()) {
            let name = file.deletingPathExtension().lastPathComponent
            let vals = try? file.resourceValues(forKeys: [.creationDateKey])
            let date = vals?.creationDate ?? Date.distantPast

            if let content = try? String(contentsOf: file, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                let trackCount = lines.filter { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty && !trimmed.hasPrefix("#")
                }.count
                
                list.append(LocalPlaylistBackup(name: name, fileURL: file, trackCount: trackCount, createdAt: date))
            }
        }
        
        list.sort { $0.createdAt > $1.createdAt }
        self.playlistBackups = list
    }

    private func deletePlaylistBackup(_ backup: LocalPlaylistBackup) {
        do {
            try FileManager.default.removeItem(at: backup.fileURL)
            showToastMessage(title: "Playlist backup deleted.", icon: "trash.circle.fill")
            loadPlaylistBackups()
        } catch {
            showToastMessage(title: "Failed to delete: \(error.localizedDescription)", icon: "xmark.circle")
        }
    }

    private func loadDeviceSongsAndPlaylists() {
        manager.fetchExportableSongs { fetchedSongs in
            self.deviceSongs = fetchedSongs
            manager.fetchPlaylists { fetchedPlaylists in
                DispatchQueue.main.async {
                    self.existingPlaylists = fetchedPlaylists
                }
            }
        }
    }

    private func decodeMetadata(_ line: String) -> (title: String, artist: String, album: String, durationMs: Int, fileSize: Int, remoteFilename: String)? {
        guard line.hasPrefix("#EXT-BYETUNES-METADATA:") else { return nil }
        let query = String(line.dropFirst("#EXT-BYETUNES-METADATA:".count))
        var dict: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                dict[key] = val
            }
        }
        guard let title = dict["title"], let artist = dict["artist"] else { return nil }
        let album = dict["album"] ?? ""
        let durationMs = Int(dict["durationMs"] ?? "0") ?? 0
        let fileSize = Int(dict["fileSize"] ?? "0") ?? 0
        let remoteFilename = dict["remoteFilename"] ?? ""
        return (title, artist, album, durationMs, fileSize, remoteFilename)
    }

    private func filenameStem(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
    }

    private func normalizedForMatching(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{201B}\u{FF07}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\u{201C}\u{201D}\u{FF02}]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restorePlaylist(from url: URL) {
        do {
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            
            var playlistName = ""
            var parsedSongs: [DecodedSongMetadata] = []
            var currentInfoLine: String? = nil
            var currentMetadataLine: String? = nil

            let lines = fileContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }

                if trimmed.hasPrefix("#EXT-BYETUNES-PLAYLIST:") {
                    let query = String(trimmed.dropFirst("#EXT-BYETUNES-PLAYLIST:".count))
                    let parts = query.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 && parts[0] == "name" {
                        playlistName = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    }
                } else if trimmed.hasPrefix("#EXT-BYETUNES-METADATA:") {
                    currentMetadataLine = trimmed
                } else if trimmed.hasPrefix("#EXTINF:") {
                    currentInfoLine = trimmed
                } else if trimmed.hasPrefix("#") {
                } else {
                    var song = DecodedSongMetadata(title: "", artist: "", remoteFilename: trimmed)
                    
                    if let metaLine = currentMetadataLine,
                       let decoded = decodeMetadata(metaLine) {
                        song.title = decoded.title
                        song.artist = decoded.artist
                        song.album = decoded.album
                        song.durationMs = decoded.durationMs
                        song.fileSize = decoded.fileSize
                        song.remoteFilename = decoded.remoteFilename.isEmpty ? trimmed : decoded.remoteFilename
                    } else if let infoLine = currentInfoLine {
                        let commaParts = infoLine.split(separator: ",", maxSplits: 1)
                        if commaParts.count == 2 {
                            let info = commaParts[1]
                            let dashParts = info.split(separator: "-", maxSplits: 1)
                            if dashParts.count == 2 {
                                let part1 = dashParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                                let part2 = dashParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                                song.artist = part1
                                song.title = part2
                                song.altArtist = part2
                                song.altTitle = part1
                            } else {
                                song.title = String(info).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                    
                    parsedSongs.append(song)
                    currentInfoLine = nil
                    currentMetadataLine = nil
                }
            }
            
            if playlistName.isEmpty {
                playlistName = url.deletingPathExtension().lastPathComponent
            }
            
            if parsedSongs.isEmpty {
                showToastMessage(title: "Invalid or empty playlist file.", icon: "xmark.circle.fill")
                return
            }
            
            var matchedPids: [Int64] = []
            var missingSongsCount = 0
            var missingSongLabels: [String] = []

            for parsedSong in parsedSongs {
                var match = deviceSongs.first { song in
                    !song.remoteFilename.isEmpty && !parsedSong.remoteFilename.isEmpty &&
                    filenameStem(song.remoteFilename) == filenameStem(parsedSong.remoteFilename)
                }

                if match == nil {
                    match = deviceSongs.first { song in
                        filenameStem(song.suggestedFilename) == filenameStem(parsedSong.remoteFilename)
                    }
                }

                if match == nil {
                    match = deviceSongs.first { song in
                        normalizedForMatching(song.title) == normalizedForMatching(parsedSong.title) &&
                        normalizedForMatching(song.artist) == normalizedForMatching(parsedSong.artist) &&
                        normalizedForMatching(song.album) == normalizedForMatching(parsedSong.album)
                    }
                }

                if match == nil {
                    match = deviceSongs.first { song in
                        normalizedForMatching(song.title) == normalizedForMatching(parsedSong.title) &&
                        normalizedForMatching(song.artist) == normalizedForMatching(parsedSong.artist)
                    }
                }

                if match == nil, let altTitle = parsedSong.altTitle, let altArtist = parsedSong.altArtist {
                    match = deviceSongs.first { song in
                        normalizedForMatching(song.title) == normalizedForMatching(altTitle) &&
                        normalizedForMatching(song.artist) == normalizedForMatching(altArtist)
                    }
                }

                if match == nil {
                    match = deviceSongs.first { song in
                        normalizedForMatching(song.title) == normalizedForMatching(parsedSong.title)
                    }
                }

                if match == nil, let altTitle = parsedSong.altTitle {
                    match = deviceSongs.first { song in
                        normalizedForMatching(song.title) == normalizedForMatching(altTitle)
                    }
                }

                if let match {
                    matchedPids.append(match.itemPid)
                } else {
                    missingSongsCount += 1
                    let title = parsedSong.title.isEmpty ? (parsedSong.altTitle ?? "Unknown Title") : parsedSong.title
                    let artist = parsedSong.artist.isEmpty ? (parsedSong.altArtist ?? "") : parsedSong.artist
                    missingSongLabels.append(artist.isEmpty ? title : "\(title) — \(artist)")
                }
            }

            let existingPlaylist = existingPlaylists.first { $0.name.lowercased() == playlistName.lowercased() }

            self.pendingRestorePlaylistName = playlistName
            self.pendingRestoreSongPids = matchedPids
            self.pendingRestoreExistingPid = existingPlaylist?.pid
            self.pendingRestoreMissingCount = missingSongsCount
            self.pendingRestoreTotalCount = parsedSongs.count
            self.pendingRestoreMissingSongs = missingSongLabels
            
            DispatchQueue.main.async {
                self.showingRestoreConfirmationAlert = true
            }
            
        } catch {
            showToastMessage(title: "Failed to read file: \(error.localizedDescription)", icon: "xmark.circle.fill")
        }
    }

    private func executeRestorePlaylist(actions: [DeviceManager.PlaylistAction]) {
        isRestoringPlaylistAction = true
        manager.applyPlaylistEdits(actions: actions) { success, message in
            DispatchQueue.main.async {
                self.isRestoringPlaylistAction = false
                if success {
                    self.showToastMessage(title: "Playlist restored!", icon: "checkmark.circle.fill")
                    self.loadDeviceSongsAndPlaylists()
                } else {
                    self.showToastMessage(title: "Restore failed: \(message)", icon: "xmark.circle.fill")
                }
            }
        }
    }

    private func showToastMessage(title: String, icon: String) {
        withAnimation(.spring()) {
            self.toastTitle = title
            self.toastIcon = icon
            self.showToast = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.showToast = false
            }
        }
    }

    // MARK: - Snapshot Progress Popup
    private var snapshotProgressPopup: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 6) {
                    Text(snapshotProgressTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Hang tight, this could take some time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    if let snapshotProgress {
                        ProgressView(value: snapshotProgress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                    }

                    Text(snapshotProgressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
