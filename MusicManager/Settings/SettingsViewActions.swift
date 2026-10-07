import SwiftUI
import UniformTypeIdentifiers

// MARK: - Actions
extension SettingsView {

    // MARK: - Supporters
    func fetchSupporters() async {
        guard !supportersLoaded || supporters.isEmpty else { return }

        let timestamp = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://raw.githubusercontent.com/EduAlexxis/EduAlexxis-Altstore-Repo/main/supporters.json?t=\(timestamp)") else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Response: Decodable { let supporters: [String] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            await MainActor.run {
                supporters = decoded.supporters
                supportersLoaded = true
            }
        } catch {
            Logger.shared.log("[Settings] Failed to fetch supporters: \(error)")
            await MainActor.run {
                supportersLoaded = true
            }
        }
    }

    func exportDatabase() {
        isExportingDb = true

        let tmp = FileManager.default.temporaryDirectory
        let files: [(remote: String, local: URL)] = [
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb")),
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb-shm")),
            ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal",
             tmp.appendingPathComponent("MediaLibrary.sqlitedb-wal")),
            ("/iTunes_Control/Ringtones/Ringtones.plist",
             tmp.appendingPathComponent("Ringtones.plist"))
        ]

        var downloaded: [URL] = []

        func downloadNext(_ index: Int) {
            guard index < files.count else {
                DispatchQueue.main.async {
                    self.isExportingDb = false
                    if downloaded.isEmpty {
                        self.showToastMessage(title: "Export Failed", icon: "xmark.circle.fill")
                    } else {
                        self.exportedDbURLs = downloaded
                        self.showingDbExportSheet = true
                    }
                }
                return
            }

            let file = files[index]
            manager.downloadFileFromDevice(remotePath: file.remote, localURL: file.local) { success in
                if success {
                    downloaded.append(file.local)
                }
                downloadNext(index + 1)
            }
        }

        downloadNext(0)
    }

    func checkForSettingsUpdate() {
        isCheckingForUpdate = true
        Task {
            do {
                let update = try await AppUpdateChecker.checkForUpdate()
                await MainActor.run {
                    self.isCheckingForUpdate = false
                    self.settingsUpdate = update
                    if let update {
                        self.showToastMessage(title: "ByeTunes \(update.version) is available", icon: "arrow.down.circle.fill")
                    } else {
                        self.showToastMessage(title: "ByeTunes is up to date", icon: "checkmark.circle.fill")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCheckingForUpdate = false
                    self.showToastMessage(title: "Update Check Failed", icon: "xmark.circle.fill")
                }
                Logger.shared.log("[Update] Settings version check failed: \(error.localizedDescription)")
            }
        }
    }

    func showToastMessage(title: String, icon: String) {
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

    func handlePairingImport(url: URL?) {
        guard let url = url else { return }

        do {
            try manager.importPairingFile(from: url)
            status = "\(manager.expectedPairingFileTitle) imported"

            manager.startHeartbeat()
        } catch {
            status = error.localizedDescription
        }
    }

    var downloadFolderSubtitle: String {
        let directory = SongMetadata.persistentDownloadsDirectory()
        if SongMetadata.customPersistentDownloadsDirectory() != nil {
            return directory.lastPathComponent
        }
        return "App Folder"
    }

    func handleDownloadFolderSelection(url: URL?) {
        guard let url else { return }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "downloadedSongsFolderBookmark")
            showToastMessage(title: "Download Folder Updated", icon: "folder.badge.checkmark")
        } catch {
            showToastMessage(title: "Folder Selection Failed", icon: "exclamationmark.triangle.fill")
        }
    }
}
