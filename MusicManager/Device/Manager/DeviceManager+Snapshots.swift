import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func removeSupersededSnapshots(in root: URL, keeping newest: URL, isFull: Bool) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for entry in entries where entry.hasDirectoryPath && entry.lastPathComponent.hasPrefix("snapshot_") && entry.standardizedFileURL != newest.standardizedFileURL {
            let entryIsFull = fm.fileExists(atPath: entry.appendingPathComponent(snapshotFullBackupDirectory).path)
            guard entryIsFull == isFull else { continue }
            try? fm.removeItem(at: entry)
            Logger.shared.log("[Backup] Removed older \(isFull ? "full" : "light") snapshot: \(entry.lastPathComponent)")
        }
    }

    func createDatabaseSnapshot(forceDbOnly: Bool = false, forceFullBackup: Bool = false, progress: SnapshotProgressHandler? = nil, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Creating database snapshot...")

        DispatchQueue.global(qos: .userInitiated).async {
            let root = self.snapshotsDirectoryURL
            let needsSecurityScope = root.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            progress?("Preparing backup...", nil)
            let fullBackupEnabled = forceDbOnly ? false : forceFullBackup
            if self.killMusicBeforeInjectEnabled {
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[Backup] Pre-snapshot Music kill \(killed ? "completed" : "skipped/failed")")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let stamp = formatter.string(from: Date())

            var folder = root.appendingPathComponent("snapshot_\(stamp)", isDirectory: true)
            var folderSuffix = 1
            while FileManager.default.fileExists(atPath: folder.path) {
                folder = root.appendingPathComponent("snapshot_\(stamp)-\(folderSuffix)", isDirectory: true)
                folderSuffix += 1
            }

            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[Backup] Failed creating snapshot folder: \(error)")
                completion(false, "Failed creating snapshot folder")
                return
            }
            
            let files: [(remote: String, local: String, required: Bool)] = [
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb", "MediaLibrary.sqlitedb", true),
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal", "MediaLibrary.sqlitedb-wal", false),
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm", "MediaLibrary.sqlitedb-shm", false),
                ("/iTunes_Control/Ringtones/Ringtones.plist", "Ringtones.plist", false)
            ]
            
            var saved: [String] = []
            for (index, item) in files.enumerated() {
                progress?("Backing up database files \(index + 1)/\(files.count)...", Double(index + 1) / Double(files.count) * 0.25)
                let localURL = folder.appendingPathComponent(item.local)
                let sem = DispatchSemaphore(value: 0)
                var success = false
                self.downloadFileFromDevice(remotePath: item.remote, localURL: localURL) { ok in
                    success = ok
                    sem.signal()
                }
                sem.waitForTransfer()
                
                if success {
                    saved.append(item.local)
                    Logger.shared.log("[Backup] Saved \(item.local)")
                } else if item.required {
                    Logger.shared.log("[Backup] Required file missing: \(item.remote)")
                    try? FileManager.default.removeItem(at: folder)
                    completion(false, "Failed: MediaLibrary.sqlitedb unavailable")
                    return
                }
            }
            
            if !saved.contains("MediaLibrary.sqlitedb") {
                Logger.shared.log("[Backup] Snapshot invalid (no DB file)")
                try? FileManager.default.removeItem(at: folder)
                completion(false, "Failed: DB file missing")
                return
            }
            
            let dbLocal = folder.appendingPathComponent("MediaLibrary.sqlitedb")
            progress?("Indexing music files...", fullBackupEnabled ? 0.28 : 0.45)
            let musicFiles = Array(self.musicFilenamesFromDatabase(dbLocal)).sorted()
            self.writeSnapshotManifest(musicFiles, to: folder.appendingPathComponent(self.snapshotMusicManifestName))
            Logger.shared.log("[Backup] Indexed \(musicFiles.count) music filenames for rollback safety")
            
            progress?("Indexing artwork...", fullBackupEnabled ? 0.32 : 0.55)
            let artworkPaths = self.artworkPathsFromDatabase(dbLocal)
            self.writeSnapshotManifest(artworkPaths, to: folder.appendingPathComponent(self.snapshotArtworkManifestName))
            Logger.shared.log("[Backup] Indexed \(artworkPaths.count) artwork paths")
            
            if fullBackupEnabled {
                Logger.shared.log("[Backup] Separate artwork backup skipped for full backup")
            } else {
                let artworkRoot = folder.appendingPathComponent(self.snapshotArtworkDirectory, isDirectory: true)
                var artworkSaved = 0
                if !artworkPaths.isEmpty {
                    FileManager.default.createDirectoryLogged(at: artworkRoot)
                    for (index, relativePath) in artworkPaths.enumerated() {
                        progress?("Backing up artwork \(index + 1)/\(artworkPaths.count)...", 0.58 + (Double(index + 1) / Double(artworkPaths.count) * 0.34))
                        let localURL = artworkRoot.appendingPathComponent(relativePath)
                        let localDir = localURL.deletingLastPathComponent()
                        FileManager.default.createDirectoryLogged(at: localDir)
                        
                        let remotePath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
                        let sem = DispatchSemaphore(value: 0)
                        var downloaded = false
                        self.downloadFileFromDevice(remotePath: remotePath, localURL: localURL) { ok in
                            downloaded = ok
                            sem.signal()
                        }
                        sem.waitForTransfer()
                        
                        if downloaded {
                            artworkSaved += 1
                        } else {
                            try? FileManager.default.removeItem(at: localURL)
                        }
                    }
                }
                Logger.shared.log("[Backup] Artwork saved: \(artworkSaved)/\(artworkPaths.count)")
            }

            if fullBackupEnabled {
                progress?("Scanning full iTunes folder...", 0.38)
                Logger.shared.log("[Backup] Full backup enabled, copying iTunes/Music folders...")
                let fullResult = self.createFullITunesBackupCopy(in: folder) { message, value in
                    progress?(message, value)
                }
                guard fullResult.success else {
                    Logger.shared.log("[Backup] Full backup failed: \(fullResult.message)")
                    completion(false, fullResult.message)
                    return
                }
                Logger.shared.log("[Backup] Full backup copy created: \(fullResult.message)")

                progress?("Writing playlist files...", 0.97)
                let playlistCount = self.generatePlaylistM3U8Files(in: folder)
                Logger.shared.log("[Backup] Full backup: wrote \(playlistCount) playlist file(s)")
            }

            self.removeSupersededSnapshots(in: root, keeping: folder, isFull: fullBackupEnabled)
            progress?("Backup complete.", 1)
            Logger.shared.log("[Backup] Snapshot complete: \(folder.lastPathComponent) (\(saved.count) files)")
            completion(true, fullBackupEnabled ? "Full snapshot created: \(folder.lastPathComponent)" : "Snapshot created: \(folder.lastPathComponent)")
        }
    }

    func restoreDatabaseSnapshot(named folderName: String, progress: SnapshotProgressHandler? = nil, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Restoring snapshot: \(folderName)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let root = self.snapshotsDirectoryURL
            let needsSecurityScope = root.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            let snapshotDir = root.appendingPathComponent(folderName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: snapshotDir.path) else {
                completion(false, "Snapshot not found")
                return
            }
            self.restoreSnapshotDirectory(snapshotDir, progress: progress, completion: completion)
        }
    }

    func restoreDatabaseSnapshot(from externalURL: URL, progress: SnapshotProgressHandler? = nil, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Restoring snapshot from imported folder: \(externalURL.lastPathComponent)")

        DispatchQueue.global(qos: .userInitiated).async {
            let needsSecurityScope = externalURL.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    externalURL.stopAccessingSecurityScopedResource()
                }
            }

            let fm = FileManager.default
            let dbLocal = externalURL.appendingPathComponent("MediaLibrary.sqlitedb")
            let fullBackupRoot = externalURL.appendingPathComponent(self.snapshotFullBackupDirectory, isDirectory: true)
            guard fm.fileExists(atPath: dbLocal.path) || fm.fileExists(atPath: fullBackupRoot.path) else {
                completion(false, "This doesn't look like a ByeTunes backup folder")
                return
            }

            self.restoreSnapshotDirectory(externalURL, progress: progress, completion: completion)
        }
    }

    func importExternalSnapshot(from externalURL: URL, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Importing external folder as local snapshot: \(externalURL.lastPathComponent)")

        DispatchQueue.global(qos: .userInitiated).async {
            let needsExternalScope = externalURL.startAccessingSecurityScopedResource()
            defer {
                if needsExternalScope {
                    externalURL.stopAccessingSecurityScopedResource()
                }
            }

            let fm = FileManager.default
            let dbLocal = externalURL.appendingPathComponent("MediaLibrary.sqlitedb")
            let fullBackupRoot = externalURL.appendingPathComponent(self.snapshotFullBackupDirectory, isDirectory: true)
            guard fm.fileExists(atPath: dbLocal.path) || fm.fileExists(atPath: fullBackupRoot.path) else {
                completion(false, "This doesn't look like a ByeTunes backup folder")
                return
            }

            let root = self.snapshotsDirectoryURL
            let needsRootScope = root.startAccessingSecurityScopedResource()
            defer {
                if needsRootScope {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                completion(false, "Failed preparing local backups folder")
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let stamp = formatter.string(from: Date())
            var destination = root.appendingPathComponent("snapshot_\(stamp)", isDirectory: true)
            var suffix = 1
            while fm.fileExists(atPath: destination.path) {
                destination = root.appendingPathComponent("snapshot_\(stamp)-\(suffix)", isDirectory: true)
                suffix += 1
            }

            do {
                try fm.copyItem(at: externalURL, to: destination)
            } catch {
                Logger.shared.log("[Backup] Failed importing snapshot: \(error)")
                completion(false, "Failed copying backup into local storage")
                return
            }

            Logger.shared.log("[Backup] Imported external folder into local snapshot: \(destination.lastPathComponent)")
            completion(true, "Library imported. Restore it from Database Snapshots when connected.")
        }
    }

    func deleteDatabaseSnapshot(named folderName: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let root = self.snapshotsDirectoryURL
            let needsSecurityScope = root.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            let path = root.appendingPathComponent(folderName, isDirectory: true)
            do {
                try FileManager.default.removeItem(at: path)
                self.setDisplayName(nil, for: folderName)
                Logger.shared.log("[Backup] Deleted snapshot: \(folderName)")
                completion(true, "Deleted: \(folderName)")
            } catch {
                Logger.shared.log("[Backup] Failed deleting snapshot \(folderName): \(error)")
                completion(false, "Delete failed")
            }
        }
    }
    
}
