import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupRestoreView: View {
    @ObservedObject var manager: DeviceManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSnapshotBusy = false
    @State private var isCreatingSnapshot = false
    @State private var isCreatingFullBackup = false
    @State private var snapshotProgressTitle = "Working on Backup"
    @State private var snapshotProgressMessage = ""
    @State private var snapshotProgress: Double? = nil


    @State private var showingPlaylistSelector = false
    @State private var showingBackupFolderPicker = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    @State private var showToast = false

    @State private var infoAlertTitle = ""
    @State private var infoAlertMessage = ""
    @State private var showingInfoAlert = false

    private func showInfo(_ title: String, _ message: String) {
        infoAlertTitle = title
        infoAlertMessage = message
        showingInfoAlert = true
    }

    private var infoButton: some View {
        Image(systemName: "info.circle")
            .font(.body)
            .foregroundColor(.secondary)
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
                        Text("BACKUPS MANAGEMENT")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            NavigationLink {
                                ManageBackupsView(manager: manager)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(.body)
                                        .foregroundColor(.accentColor)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Manage Backups")
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)
                                        Text("View, restore, or delete snapshots and playlist backups.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemGray3))
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                            }
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("BACKUPS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            HStack {
                                Button {
                                    createSnapshotBackup(full: false)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "archivebox")
                                            .font(.body)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Light Backup")
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text("Database only. Fast and small.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isSnapshotBusy || !manager.heartbeatReady)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Light Backup",
                                        "Saves just the database: playlists, song metadata, and library structure. Fast and small. Restore it later from Manage Backups."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity(manager.heartbeatReady ? 1 : 0.55)

                            Divider().padding(.leading, 56)

                            HStack {
                                Button {
                                    createSnapshotBackup(full: true)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "archivebox.fill")
                                            .font(.body)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Full Backup")
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text("Includes song files. Takes more space and time.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isSnapshotBusy || !manager.heartbeatReady)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Full Backup",
                                        "Saves the database plus the actual song files, so a restore doesn't need you to re-download anything. Also bundles a playlist file for each of your playlists. Takes more space and time to create. Share it from Manage Backups if you want a copy in Files, iCloud Drive, or AirDrop."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity(manager.heartbeatReady ? 1 : 0.55)

                            Divider().padding(.leading, 56)

                            HStack {
                                Button {
                                    showingBackupFolderPicker = true
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.body)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Backup Folder")
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text(backupFolderSubtitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Backup Folder",
                                        "Choose where new database snapshots are saved on this device. Existing backups stay where they are."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showingBackupFolderPicker = true
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemGray3))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYLIST BACKUPS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .tracking(0.8)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            HStack {
                                Button {
                                    showingPlaylistSelector = true
                                } label: {
                                    HStack {
                                        Image(systemName: "music.note.list")
                                            .font(.body)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Backup Playlists")
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)
                                            Text("Select and back up playlists to shareable files.")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!manager.heartbeatReady)

                                Spacer()

                                Button {
                                    showInfo(
                                        "Backup Playlists",
                                        "Exports the songs in a chosen playlist to a portable file you can restore later or share with someone else. Doesn't touch your database, just the playlist's track list."
                                    )
                                } label: {
                                    infoButton
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showingPlaylistSelector = true
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemGray3))
                                }
                                .buttonStyle(.plain)
                                .disabled(!manager.heartbeatReady)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity(manager.heartbeatReady ? 1 : 0.55)
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {

        }
        .sheet(isPresented: $showingPlaylistSelector) {
            PlaylistBackupSelectorSheet(manager: manager) { successMsg, _ in
                showToastMessage(title: successMsg, icon: "checkmark.circle.fill")
            }
        }
        .sheet(isPresented: $showingBackupFolderPicker) {
            DocumentPicker(types: [.folder], asCopy: false) { url in
                handleBackupFolderSelection(url: url)
            }
        }
        .alert(infoAlertTitle, isPresented: $showingInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoAlertMessage)
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

            if isSnapshotBusy && isCreatingSnapshot {
                snapshotProgressPopup
            }


        }
    }

    // MARK: - Snapshot Helpers
    private func createSnapshotBackup(full: Bool) {
        isSnapshotBusy = true
        isCreatingSnapshot = true
        isCreatingFullBackup = full
        updateSnapshotProgress(title: full ? "Creating Full Backup" : "Creating Backup", message: "Preparing backup...", progress: nil)

        manager.createDatabaseSnapshot(forceDbOnly: !full, forceFullBackup: full) { message, progress in
            DispatchQueue.main.async {
                self.updateSnapshotProgress(title: full ? "Creating Full Backup" : "Creating Backup", message: message, progress: progress)
            }
        } completion: { success, message in
            DispatchQueue.main.async {
                self.isSnapshotBusy = false
                self.isCreatingSnapshot = false
                self.updateSnapshotProgress(title: full ? "Creating Full Backup" : "Creating Backup", message: message, progress: success ? 1 : nil)
                self.showToastMessage(
                    title: success ? message : "Backup Failed: \(message)",
                    icon: success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
            }
        }
    }

    private func updateSnapshotProgress(title: String, message: String, progress: Double?) {
        snapshotProgressTitle = title
        snapshotProgressMessage = message.isEmpty ? "Working..." : message
        snapshotProgress = progress.map { min(max($0, 0), 1) }
    }

    private var backupFolderSubtitle: String {
        if let custom = manager.customSnapshotsDirectory() {
            return custom.lastPathComponent
        }
        return "App Folder"
    }

    private func handleBackupFolderSelection(url: URL?) {
        guard let url else { return }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "backupsFolderBookmark")
            showToastMessage(title: "Backup Folder Updated", icon: "folder.badge.checkmark")
        } catch {
            showToastMessage(title: "Folder Selection Failed", icon: "exclamationmark.triangle.fill")
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

    // MARK: - Relocated Popups
    private var snapshotProgressPopup: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 6) {
                    Text(snapshotProgressTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(isCreatingFullBackup ? "Hang tight, full backups can take some time." : "Hang tight, this could take some time.")
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

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

