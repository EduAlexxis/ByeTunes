import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func runDatabaseRepairDoctor(progress: @escaping (String, Double?) -> Void, completion: @escaping (Bool, String) -> Void) {
        let token = beginRepairOperation()
        progress("Connecting to device...", 0.05)
        startHeartbeat(forceReconnect: true) { success in
            if self.isRepairOperationCancelled(token) {
                completion(false, "Repair cancelled.")
                return
            }
            guard success else {
                completion(false, "Connection failed. Please check pairing file.")
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.executeDatabaseRepairDoctor(operationToken: token, progress: progress, completion: completion)
            }
        }
    }

    func fixAlphabeticalOrdering(progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        let operationToken = beginRepairOperation()
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "repairing alphabetical song ordering") else {
                completion(false, "Device connection unavailable.")
                return
            }

            progress("Preparing alphabetical order repair...")
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill for alphabetical repair \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "alphabetical_sort_fix") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            if self.isRepairOperationCancelled(operationToken) {
                completion(false, "Repair cancelled.")
                return
            }

            progress("Rebuilding alphabetical order...")
            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            do {
                try MediaLibraryBuilder.repairAlphabeticalOrdering(db: db)
                _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
                _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
                sqlite3_close(db)
            } catch {
                sqlite3_close(db)
                Logger.shared.log("[DeviceManager] Alphabetical repair failed: \(error)")
                completion(false, "Could not rebuild alphabetical ordering.")
                return
            }

            progress("Uploading repaired library...")
            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the repaired library.")
                return
            }

            self.sendSyncFinishedNotification()
            completion(true, "Alphabetical order repaired.")
        }
    }

    func repairAlphabeticalOrderingInLocalDatabase(_ dbURL: URL, logContext: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            Logger.shared.log("\(logContext) Automatic alphabetical repair failed: could not open staged database")
            return false
        }

        do {
            try MediaLibraryBuilder.repairAlphabeticalOrdering(db: db)
            _ = sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)
            Logger.shared.log("\(logContext) Automatic alphabetical repair complete")
            return true
        } catch {
            sqlite3_close(db)
            Logger.shared.log("\(logContext) Automatic alphabetical repair failed: \(error)")
            return false
        }
    }
    
    func executeDatabaseRepairDoctor(operationToken: UUID, progress: @escaping (String, Double?) -> Void, completion: @escaping (Bool, String) -> Void) {
        progress("Creating database backup...", 0.1)
        
        let backupSem = DispatchSemaphore(value: 0)
        var backupMsg = ""
        var backupSuccess = false
        self.createDatabaseSnapshot(forceDbOnly: true, progress: { status, prog in
            progress("Backup: \(status)", prog != nil ? 0.1 + (prog! * 0.1) : nil)
        }) { ok, msg in
            backupSuccess = ok
            backupMsg = msg
            backupSem.signal()
        }
        backupSem.waitForTransfer()
        
        guard backupSuccess else {
            completion(false, "Backup failed: \(backupMsg). Aborting repair for safety.")
            return
        }

        if isRepairOperationCancelled(operationToken) {
            completion(false, "Repair cancelled.")
            return
        }

        progress("Downloading library database...", 0.25)
        var dbData: Data?
        var walData: Data?
        var shmData: Data?
        
        let semDownload = DispatchSemaphore(value: 0)
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            semDownload.signal()
        }
        semDownload.waitForTransfer()
        
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
        
        guard let databaseData = dbData else {
            completion(false, "Failed to download MediaLibrary.sqlitedb from device.")
            return
        }
        
        progress("Analyzing music library index...", 0.35)
        var dbFilenames = Set<String>()
        var dbArtworkPaths = Set<String>()
        var dbArtworkTokens = Set<String>()
        var itemLocations: [Int64: String] = [:]
        var artworkPathsByToken: [String: String] = [:]
        
        let querySuccess = self.withStagedMediaLibrary(dbData: databaseData, walData: walData, shmData: shmData, label: "repair_doctor_query") { localDBURL -> Bool in
            var db: OpaquePointer?
            guard sqlite3_open(localDBURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return false
            }
            defer { sqlite3_close(db) }
            
            var errorMsg: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
            if errorMsg != nil {
                sqlite3_free(errorMsg)
            }
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT item_pid, location FROM item_extra WHERE location != ''", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let pid = sqlite3_column_int64(stmt, 0)
                    if let ptr = sqlite3_column_text(stmt, 1) {
                        let loc = String(cString: ptr)
                        itemLocations[pid] = loc
                        let filename = (loc as NSString).lastPathComponent
                        dbFilenames.insert(filename)
                    }
                }
            }
            if stmt != nil { sqlite3_finalize(stmt) }
            
            if sqlite3_prepare_v2(db, "SELECT artwork_token, relative_path FROM artwork WHERE relative_path != ''", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let tokenPtr = sqlite3_column_text(stmt, 0), let pathPtr = sqlite3_column_text(stmt, 1) {
                        let token = String(cString: tokenPtr)
                        let path = String(cString: pathPtr)
                        artworkPathsByToken[token] = path
                        dbArtworkPaths.insert(path)
                        dbArtworkTokens.insert(token)
                    }
                }
            }
            if stmt != nil { sqlite3_finalize(stmt) }
            
            return true
        }
        
        guard querySuccess == true else {
            completion(false, "Failed to parse database records.")
            return
        }

        if isRepairOperationCancelled(operationToken) {
            completion(false, "Repair cancelled.")
            return
        }

        progress("Scanning device folders...", 0.5)
        var afc: AfcClientHandle?
        self.connectAfcClient(&afc)
        guard afc != nil else {
            completion(false, "Failed to establish AFC filesystem session.")
            return
        }
        defer {
            if let a = afc {
                afc_client_free(a)
            }
        }
        
        var deviceAudioFiles: [String: String] = [:]
        var subfolders: [String] = []
        var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count = 0
        
        if afc_list_directory(afc, "/iTunes_Control/Music", &entries, &count) == nil, let list = entries {
            for i in 0..<count {
                if let ptr = list[i] {
                    let name = String(cString: ptr)
                    if name != "." && name != ".." && name.hasPrefix("F") {
                        subfolders.append("/iTunes_Control/Music/\(name)")
                    }
                }
            }
            free(entries)
        }
        
        if subfolders.isEmpty {
            subfolders.append(self.resolvePrimaryMusicDirectory())
        }
        
        for folder in subfolders {
            var fEntries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var fCount = 0
            if afc_list_directory(afc, folder, &fEntries, &fCount) == nil, let list = fEntries {
                for i in 0..<fCount {
                    if let ptr = list[i] {
                        let file = String(cString: ptr)
                        if file != "." && file != ".." && file != ".DS_Store" {
                            deviceAudioFiles[file] = "\(folder)/\(file)"
                        }
                    }
                }
                free(fEntries)
            }
        }
        
        var deviceArtworkFiles: [String: String] = [:]
        var artworkSubfolders: [String] = []
        var artEntries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var artCount = 0
        
        if afc_list_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals", &artEntries, &artCount) == nil, let list = artEntries {
            for i in 0..<artCount {
                if let ptr = list[i] {
                    let name = String(cString: ptr)
                    if name != "." && name != ".." && name.count == 2 {
                        artworkSubfolders.append(name)
                    }
                }
            }
            free(artEntries)
        }
        
        for sub in artworkSubfolders {
            let artFolder = "/iTunes_Control/iTunes/Artwork/Originals/\(sub)"
            var subEntries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var subCount = 0
            if afc_list_directory(afc, artFolder, &subEntries, &subCount) == nil, let list = subEntries {
                for i in 0..<subCount {
                    if let ptr = list[i] {
                        let file = String(cString: ptr)
                        if file != "." && file != ".." {
                            let rel = "\(sub)/\(file)"
                            deviceArtworkFiles[rel] = "\(artFolder)/\(file)"
                        }
                    }
                }
                free(subEntries)
            }
        }
        
        progress("Finding mismatched files...", 0.65)
        var orphanedAudioPaths: [String] = []
        for (filename, fullPath) in deviceAudioFiles {
            if !dbFilenames.contains(filename) {
                orphanedAudioPaths.append(fullPath)
            }
        }
        
        var ghostItemPids: [Int64] = []
        for (pid, location) in itemLocations {
            let filename = (location as NSString).lastPathComponent
            if !filename.isEmpty && deviceAudioFiles[filename] == nil {
                ghostItemPids.append(pid)
            }
        }
        
        var orphanedArtworkPaths: [String] = []
        for (relPath, fullPath) in deviceArtworkFiles {
            if !dbArtworkPaths.contains(relPath) {
                orphanedArtworkPaths.append(fullPath)
            }
        }
        
        var invalidArtworkTokens: [String] = []
        for (token, relPath) in artworkPathsByToken {
            if deviceArtworkFiles[relPath] == nil {
                invalidArtworkTokens.append(token)
            }
        }
        
        if isRepairOperationCancelled(operationToken) {
            completion(false, "Repair cancelled.")
            return
        }

        progress("Cleaning orphaned storage...", 0.75)
        var deletedOrphanAudio = 0
        for path in orphanedAudioPaths {
            let err = afc_remove_path(afc, path)
            if err == nil { deletedOrphanAudio += 1 }
            else { idevice_error_free(err) }
        }
        
        var deletedOrphanArtwork = 0
        for path in orphanedArtworkPaths {
            let err = afc_remove_path(afc, path)
            if err == nil { deletedOrphanArtwork += 1 }
            else { idevice_error_free(err) }
        }
        
        progress("Cleaning database records...", 0.85)
        var repairedDBData: Data? = nil
        let repairResult = self.withStagedMediaLibrary(dbData: databaseData, walData: walData, shmData: shmData, label: "repair_doctor_write") { localDBURL -> Bool in
            var db: OpaquePointer?
            guard sqlite3_open(localDBURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return false
            }
            defer {
                if db != nil { sqlite3_close(db) }
            }
            
            
            for pid in ghostItemPids {
                Logger.shared.log("[Doctor] DB Delete: Ghost PID \(pid)")
                MediaLibraryBuilder.deleteItemRows(db: db, pid: pid)
            }

            for token in invalidArtworkTokens {
                Logger.shared.log("[Doctor] DB Delete: Invalid Artwork Token \(token)")
                for table in ["artwork", "artwork_token"] {
                    var tokenStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE artwork_token = ?", -1, &tokenStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(tokenStmt, 1, token, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        if sqlite3_step(tokenStmt) != SQLITE_DONE {
                            Logger.shared.log("[Doctor] SQL Error deleting token from \(table): \(String(cString: sqlite3_errmsg(db)))")
                        }
                    }
                    sqlite3_finalize(tokenStmt)
                }
            }

            var errorMsg: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
            if errorMsg != nil {
                sqlite3_free(errorMsg)
            }
            sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
            
            sqlite3_close(db)
            db = nil
            
            repairedDBData = try? Data(contentsOf: localDBURL)
            return repairedDBData != nil
        }
        
        guard repairResult == true, let repairedData = repairedDBData else {
            completion(false, "Failed to compile repaired database.")
            return
        }
        
        progress("Staging database update...", 0.9)
        let localTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("repairedMediaLibrary.sqlitedb")
        try? FileManager.default.removeItem(at: localTempURL)
        do {
            try repairedData.write(to: localTempURL)
        } catch {
            completion(false, "Failed to write local database copy.")
            return
        }
        defer { try? FileManager.default.removeItem(at: localTempURL) }
        
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
        let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
        let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
        
        let dbUploadSuccess = self.uploadFileToDeviceWithReconnect(localURL: localTempURL, remotePath: tempDBPath, afc: &afc)
        guard dbUploadSuccess else {
            completion(false, "Failed to upload staged database.")
            return
        }
        
        guard let finalAfc = afc, self.replaceRemoteMediaLibrary(
            tempDBPath: tempDBPath,
            finalDBPath: finalDBPath,
            shmPath: shmPath,
            walPath: walPath,
            afc: finalAfc,
            logContext: "[Doctor]"
        ) else {
            completion(false, "Failed to swap database on device.")
            return
        }
        
        progress("Swapping databases...", 0.95)
        self.sendSyncFinishedNotification()
        
        let summary = "Cleaned up \(deletedOrphanAudio) orphaned audio files, \(deletedOrphanArtwork) orphaned cover arts, \(ghostItemPids.count) ghost songs, and \(invalidArtworkTokens.count) broken artwork entries."
        completion(true, summary)
    }
    
}
