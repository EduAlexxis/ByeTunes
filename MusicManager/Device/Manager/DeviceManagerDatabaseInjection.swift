import Foundation
import SQLite3

// MARK: - Database Injection
extension DeviceManager {
    func injectDatabase(from fileURL: URL, progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        let operationToken = beginRepairOperation()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory.appendingPathComponent("db_inject_\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: tempDir) }

            let needsScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if needsScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            progress("Checking database...")
            let stagedURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
            do {
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: stagedURL)
            } catch {
                completion(false, "Could not read the selected file.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(stagedURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "The selected file is not a database.")
                return
            }
            let itemCount = self.firstInt64Query(db: db, sql: "SELECT COUNT(*) FROM item")
            let hasContainers = self.firstInt64Query(db: db, sql: "SELECT COUNT(*) FROM container") != nil
            guard let itemCount, hasContainers else {
                sqlite3_close(db)
                completion(false, "The selected file is not a Music library database.")
                return
            }
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)
            Logger.shared.log("[DeviceManager] Injecting database with \(itemCount) songs")

            guard self.ensureActiveTransport(reason: "injecting a database") else {
                completion(false, "Device connection unavailable.")
                return
            }

            if self.isRepairOperationCancelled(operationToken) {
                completion(false, "Cancelled.")
                return
            }

            progress("Preparing device...")
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill for database injection \(killed ? "completed" : "skipped/failed")")

            progress("Uploading database...")
            guard self.commitStagedMediaLibrary(localDbURL: stagedURL) else {
                completion(false, "Failed to upload the database.")
                return
            }

            self.sendSyncFinishedNotification()
            completion(true, "Database injected (\(itemCount) songs).")
        }
    }
}
