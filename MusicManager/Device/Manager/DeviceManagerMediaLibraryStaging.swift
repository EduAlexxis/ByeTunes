import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Media Library Staging
extension DeviceManager {
    func stageCurrentMediaLibraryForMutation(label: String) -> (tempDir: URL, dbURL: URL, musicDir: String)? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("\(label)_\(UUID().uuidString)", isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")

        let semDb = DispatchSemaphore(value: 0)
        var dbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            semDb.signal()
        }
        semDb.waitForTransfer()

        let semWal = DispatchSemaphore(value: 0)
        var walData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            walData = data
            semWal.signal()
        }
        semWal.waitForTransfer()

        let semShm = DispatchSemaphore(value: 0)
        var shmData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            shmData = data
            semShm.signal()
        }
        semShm.waitForTransfer()

        guard self.hasUsableExistingLibrary(dbData: dbData, walData: walData, shmData: shmData),
              let dbData else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try dbData.write(to: dbURL)
            if let walData, !walData.isEmpty {
                try walData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
            }
            if let shmData, !shmData.isEmpty {
                try shmData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
            }
        } catch {
            Logger.shared.log("[DeviceManager] Failed to stage MediaLibrary for \(label): \(error)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }

        return (tempDir, dbURL, self.resolvePrimaryMusicDirectory())
    }

    func commitStagedMediaLibrary(localDbURL: URL) -> Bool {
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"

        let semUpload = DispatchSemaphore(value: 0)
        var uploaded = false
        self.uploadFileToDevice(localURL: localDbURL, remotePath: tempDBPath) { ok in
            uploaded = ok
            semUpload.signal()
        }
        semUpload.waitForTransfer()

        guard uploaded else { return false }

        var afc: AfcClientHandle?
        self.connectAfcClient(&afc)
        guard let afc else { return false }
        defer { afc_client_free(afc) }

        return replaceRemoteMediaLibrary(tempDBPath: tempDBPath, afc: afc, logContext: "[DeviceManager]")
    }

    func replaceRemoteMediaLibrary(
        tempDBPath: String = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp",
        finalDBPath: String = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb",
        shmPath: String = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm",
        walPath: String = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal",
        afc: AfcClientHandle,
        logContext: String
    ) -> Bool {
        let backupDBPath = finalDBPath + ".backup"

        _ = afc_remove_path(afc, shmPath)
        _ = afc_remove_path(afc, walPath)
        _ = afc_remove_path(afc, backupDBPath)

        var info = AfcFileInfo()
        let hasExistingFinal = afc_get_file_info(afc, finalDBPath, &info) == nil
        if hasExistingFinal {
            afc_file_info_free(&info)
        }

        if hasExistingFinal {
            let backupRenameErr = afc_rename_path(afc, finalDBPath, backupDBPath)
            if backupRenameErr != nil {
                Logger.shared.log("\(logContext) ERROR: Failed to move current database aside for protected swap")
                _ = afc_remove_path(afc, tempDBPath)
                return false
            }
        }

        let renameErr = afc_rename_path(afc, tempDBPath, finalDBPath)
        if renameErr == nil {
            if hasExistingFinal {
                _ = afc_remove_path(afc, backupDBPath)
            }
            return true
        }

        Logger.shared.log("\(logContext) ERROR: Failed to activate staged database")
        if hasExistingFinal {
            let restoreErr = afc_rename_path(afc, backupDBPath, finalDBPath)
            if restoreErr == nil {
                Logger.shared.log("\(logContext) Restored previous database after swap failure")
            } else {
                Logger.shared.log("\(logContext) ERROR: Failed to restore previous database after swap failure")
            }
        }
        _ = afc_remove_path(afc, tempDBPath)
        return false
    }
    

    func resolvePrimaryMusicDirectory() -> String {
        let fallback = "/iTunes_Control/Music/F00"
        var dbData: Data?
        var walData: Data?
        var shmData: Data?

        let sem = DispatchSemaphore(value: 0)
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            sem.signal()
        }
        sem.waitForTransfer()

        let semWal = DispatchSemaphore(value: 0)
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            walData = data
            semWal.signal()
        }
        semWal.waitForTransfer()

        let semShm = DispatchSemaphore(value: 0)
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            shmData = data
            semShm.signal()
        }
        semShm.waitForTransfer()

        guard dbData != nil else {
            Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (no DB)")
            return fallback
        }

        let resolved: String? = withStagedMediaLibrary(dbData: dbData, walData: walData, shmData: shmData, label: "music_dir_probe") { dbURL in
            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return nil
            }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            let sql = "SELECT path FROM base_location WHERE base_location_id = 3840 LIMIT 1"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                if stmt != nil { sqlite3_finalize(stmt) }
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW, let pathPtr = sqlite3_column_text(stmt, 0) else {
                return nil
            }

            let rawPath = String(cString: pathPtr)
            let normalized = self.normalizeITunesControlPath(rawPath)
            return normalized.hasPrefix("/iTunes_Control/Music/") ? normalized : nil
        }

        if let resolved {
            Logger.shared.log("[DeviceManager] Music dir resolved from base_location(3840): \(resolved)")
            return resolved
        }

        Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (base_location missing/invalid)")
        return fallback
    }

    func normalizeITunesControlPath(_ raw: String) -> String {
        var path = raw
        if !path.hasPrefix("/") { path = "/" + path }
        if path == "/iTunes_Control" || path.hasPrefix("/iTunes_Control/") {
            return path
        }
        return "/iTunes_Control" + path
    }

    func withStagedMediaLibrary<T>(
        dbData: Data?,
        walData: Data?,
        shmData: Data?,
        label: String,
        _ body: (URL) -> T?
    ) -> T? {
        guard let dbData, !dbData.isEmpty else { return nil }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("\(label)_\(UUID().uuidString)", isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
        let walURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal")
        let shmURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm")

        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try dbData.write(to: dbURL)
            if let walData, !walData.isEmpty {
                try walData.write(to: walURL)
            }
            if let shmData, !shmData.isEmpty {
                try shmData.write(to: shmURL)
            }
            let result = body(dbURL)
            try? fileManager.removeItem(at: tempDir)
            return result
        } catch {
            Logger.shared.log("[DeviceManager] Failed to stage media library for \(label): \(error)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }

    func hasUsableExistingLibrary(dbData: Data?, walData: Data?, shmData: Data?) -> Bool {
        withStagedMediaLibrary(dbData: dbData, walData: walData, shmData: shmData, label: "library_probe") { dbURL in
            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return false
            }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master", -1, &stmt, nil) == SQLITE_OK else {
                if stmt != nil { sqlite3_finalize(stmt) }
                return false
            }
            defer { sqlite3_finalize(stmt) }

            return sqlite3_step(stmt) == SQLITE_ROW
        } ?? false
    }
    
    func cleanUpOrphanedFiles(validFilenames: Set<String>, musicDir: String, completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] GC: Failed to connect AFC")
                completion(0)
                return
            }
            
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, musicDir, &entries, &count)
            
            var deletedCount = 0
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let filename = String(cString: ptr)
                        if filename != "." && filename != ".." {
                            if !validFilenames.contains(filename) {
                                let path = "\(musicDir)/\(filename)"
                                Logger.shared.log("[DeviceManager] GC: Deleting orphan -> \(filename)")
                                afc_remove_path(afc, path)
                                deletedCount += 1
                            }
                        }
                    }
                }
                free(entries)
            }
            
            afc_client_free(afc)
            completion(deletedCount)
        }
    }
    
    func writeDownloadedData(_ data: Data, to localURL: URL) throws {
        let parentDirectory = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: localURL, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    func downloadFileFromDevice(remotePath: String, localURL: URL, completion: @escaping (Bool) -> Void) {
        self.downloadFileFromDevice(remotePath: remotePath) { data in
            guard let data = data else {
                completion(false)
                return
            }
            do {
                try self.writeDownloadedData(data, to: localURL)
                completion(true)
            } catch {
                Logger.shared.log("[DeviceManager] Error writing downloaded file: \(error)")
                completion(false)
            }
        }
    }
}
