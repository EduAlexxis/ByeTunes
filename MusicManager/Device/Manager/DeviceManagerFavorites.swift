import Foundation
import SQLite3

enum FavoritesPlaylistResult {
    case created
    case replaced(refreshed: Int)
    case alreadyExists
    case failed(String)
}

// MARK: - Favorites Playlist
extension DeviceManager {
    func createFavoritesPlaylist(replaceExisting: Bool, progress: @escaping (String) -> Void, completion: @escaping (FavoritesPlaylistResult) -> Void) {
        let operationToken = beginRepairOperation()
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "creating the favorites playlist") else {
                completion(.failed("Device connection unavailable."))
                return
            }

            progress("Preparing favorites playlist...")
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill for favorites playlist \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "favorites_playlist") else {
                completion(.failed("Could not stage MediaLibrary.sqlitedb."))
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            if self.isRepairOperationCancelled(operationToken) {
                completion(.failed("Cancelled."))
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(.failed("Could not open MediaLibrary.sqlitedb."))
                return
            }

            let hadExisting = MediaLibraryBuilder.hasFavoritesPlaylist(db: db)
            if hadExisting && !replaceExisting {
                sqlite3_close(db)
                completion(.alreadyExists)
                return
            }

            progress("Creating favorites playlist...")
            var refreshed = 0
            do {
                if hadExisting {
                    try MediaLibraryBuilder.deleteFavoritesPlaylist(db: db)
                }
                try MediaLibraryBuilder.createFavoritesPlaylist(db: db)
                if hadExisting {
                    progress("Refreshing favorited songs...")
                    refreshed = try MediaLibraryBuilder.refreshLocalFavorites(db: db)
                }
                _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
                _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
                sqlite3_close(db)
            } catch {
                sqlite3_close(db)
                Logger.shared.log("[DeviceManager] Favorites playlist creation failed: \(error)")
                completion(.failed("Could not create the favorites playlist."))
                return
            }

            progress("Uploading library...")
            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(.failed("Failed to upload the library."))
                return
            }

            self.sendSyncFinishedNotification()
            completion(hadExisting ? .replaced(refreshed: refreshed) : .created)
        }
    }

    func fixMissingFavorites(progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        let operationToken = beginRepairOperation()
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "fixing missing favorites") else {
                completion(false, "Device connection unavailable.")
                return
            }

            progress("Preparing favorites fix...")
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill for favorites fix \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "favorites_fix") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            if self.isRepairOperationCancelled(operationToken) {
                completion(false, "Cancelled.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            progress("Fixing favorited songs...")
            var fixed = 0
            do {
                fixed = try MediaLibraryBuilder.fixFavoritedLocalSongs(db: db)
                _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
                _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
                sqlite3_close(db)
            } catch {
                sqlite3_close(db)
                Logger.shared.log("[DeviceManager] Favorites fix failed: \(error)")
                completion(false, "Could not fix the favorites.")
                return
            }

            guard fixed > 0 else {
                completion(true, "No favorites needed fixing.")
                return
            }

            progress("Uploading library...")
            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the library.")
                return
            }

            self.sendSyncFinishedNotification()
            completion(true, "Fixed \(fixed) favorited song\(fixed == 1 ? "" : "s").")
        }
    }

    func deleteFavoritesPlaylist(progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        let operationToken = beginRepairOperation()
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "deleting the favorites playlist") else {
                completion(false, "Device connection unavailable.")
                return
            }

            progress("Preparing to delete favorites playlist...")
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill for favorites deletion \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "favorites_delete") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            if self.isRepairOperationCancelled(operationToken) {
                completion(false, "Cancelled.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            guard MediaLibraryBuilder.hasFavoritesPlaylist(db: db) else {
                sqlite3_close(db)
                completion(true, "No favorites playlist found.")
                return
            }

            progress("Deleting favorites playlist...")
            do {
                try MediaLibraryBuilder.deleteFavoritesPlaylist(db: db)
                _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
                _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
                sqlite3_close(db)
            } catch {
                sqlite3_close(db)
                Logger.shared.log("[DeviceManager] Favorites playlist deletion failed: \(error)")
                completion(false, "Could not delete the favorites playlist.")
                return
            }

            progress("Uploading library...")
            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the library.")
                return
            }

            self.sendSyncFinishedNotification()
            completion(true, "Favorites playlist deleted.")
        }
    }
}
