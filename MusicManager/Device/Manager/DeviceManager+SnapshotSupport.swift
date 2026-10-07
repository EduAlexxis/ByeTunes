import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Snapshot Support
extension DeviceManager {
    func restoreSnapshotDirectory(_ snapshotDir: URL, progress: SnapshotProgressHandler? = nil, completion: @escaping (Bool, String) -> Void) {
        progress?("Preparing restore...", nil)
        let fm = FileManager.default
        let dbLocal = snapshotDir.appendingPathComponent("MediaLibrary.sqlitedb")
        let fullBackupRoot = snapshotDir.appendingPathComponent(snapshotFullBackupDirectory, isDirectory: true)

        if fm.fileExists(atPath: fullBackupRoot.path) {
            restoreFullITunesBackupCopy(fullBackupRoot, progress: progress, completion: completion)
            return
        }

        guard fm.fileExists(atPath: dbLocal.path) else {
            completion(false, "Snapshot missing MediaLibrary.sqlitedb")
            return
        }
        
        if self.killMusicBeforeInjectEnabled {
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[Backup] Pre-restore Music kill \(killed ? "completed" : "skipped/failed")")
        }
        
        var afc: AfcClientHandle?
        self.connectAfcClient(&afc)
        guard let afc else {
            completion(false, "AFC connection failed")
            return
        }
        defer { afc_client_free(afc) }
        
        let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
        let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
        let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
        let ringtonePath = "/iTunes_Control/Ringtones/Ringtones.plist"
        
        progress?("Uploading database...", 0.25)
        _ = afc_make_directory(afc, "/iTunes_Control/iTunes")
        _ = afc_make_directory(afc, "/iTunes_Control/Ringtones")
        
        let semUploadDB = DispatchSemaphore(value: 0)
        var dbUploadOK = false
        self.uploadFileToDevice(localURL: dbLocal, remotePath: tempDBPath) { ok in
            dbUploadOK = ok
            semUploadDB.signal()
        }
        semUploadDB.waitForTransfer()
        
        guard dbUploadOK else {
            completion(false, "Failed uploading snapshot DB")
            return
        }
        
        progress?("Swapping database...", 0.55)
        guard self.replaceRemoteMediaLibrary(
            tempDBPath: tempDBPath,
            finalDBPath: finalDBPath,
            shmPath: shmPath,
            walPath: walPath,
            afc: afc,
            logContext: "[Backup]"
        ) else {
            Logger.shared.log("[Backup] Rename failed while restoring DB")
            completion(false, "Failed swapping restored DB")
            return
        }
        
        let ringtoneLocal = snapshotDir.appendingPathComponent("Ringtones.plist")
        if fm.fileExists(atPath: ringtoneLocal.path) {
            progress?("Restoring ringtones...", 0.65)
            let semRingtone = DispatchSemaphore(value: 0)
            self.uploadFileToDevice(localURL: ringtoneLocal, remotePath: ringtonePath) { _ in
                semRingtone.signal()
            }
            semRingtone.waitForTransfer()
        }
        
        let artworkRoot = snapshotDir.appendingPathComponent(snapshotArtworkDirectory, isDirectory: true)
        var restoredArtwork = 0
        if fm.fileExists(atPath: artworkRoot.path) {
            _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
            _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            
            if let enumerator = fm.enumerator(at: artworkRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    
                    let relative = fileURL.path.replacingOccurrences(of: artworkRoot.path + "/", with: "")
                    guard !relative.isEmpty else { continue }
                    
                    progress?("Restoring artwork \(restoredArtwork + 1)...", nil)
                    let remote = "/iTunes_Control/iTunes/Artwork/Originals/\(relative)"
                    let semArt = DispatchSemaphore(value: 0)
                    self.uploadFileToDevice(localURL: fileURL, remotePath: remote) { ok in
                        if ok {
                            restoredArtwork += 1
                        }
                        semArt.signal()
                    }
                    semArt.waitForTransfer()
                }
            }
        }
        Logger.shared.log("[Backup] Restored artwork files: \(restoredArtwork)")
        
        progress?("Restore complete.", 1)
        self.sendSyncFinishedNotification()
        Logger.shared.log("[Backup] Restore complete from \(snapshotDir.lastPathComponent)")
        completion(true, "Restored: \(snapshotDir.lastPathComponent)")
    }

    func createFullITunesBackupCopy(in snapshotDir: URL, progress: SnapshotProgressHandler? = nil) -> (success: Bool, message: String) {
        let fm = FileManager.default
        let backupRoot = snapshotDir.appendingPathComponent(snapshotFullBackupDirectory, isDirectory: true)

        try? fm.removeItem(at: backupRoot)

        do {
            try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        } catch {
            return (false, "Failed creating full backup folder")
        }

        var afc: AfcClientHandle?
        self.connectAfcClient(&afc)
        guard let afc else {
            try? fm.removeItem(at: backupRoot)
            return (false, "AFC unavailable for full backup")
        }
        defer { afc_client_free(afc) }

        let roots = [
            "/iTunes_Control/iTunes",
            "/iTunes_Control/Music",
            "/iTunes_Control/Ringtones"
        ]

        var remoteFiles: [String] = []
        for remoteRoot in roots {
            remoteFiles.append(contentsOf: listRemoteFilesForBackup(afc: afc, remotePath: remoteRoot))
        }

        guard !remoteFiles.isEmpty else {
            try? fm.removeItem(at: backupRoot)
            return (false, "No files found for full backup")
        }

        var copied = 0
        for (index, remotePath) in remoteFiles.enumerated() {
            progress?("Copying full backup files \(index + 1)/\(remoteFiles.count)...", 0.48 + (Double(index + 1) / Double(remoteFiles.count) * 0.48))
            let relative = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let localURL = backupRoot.appendingPathComponent(relative)
            copied += copyRemoteFileToLocal(afc: afc, remotePath: remotePath, localURL: localURL)
        }

        guard copied > 0 else {
            try? fm.removeItem(at: backupRoot)
            return (false, "No files found for full backup")
        }

        progress?("Full backup copy saved.", 0.98)
        let size = directorySize(backupRoot)
        return (true, "Full backup saved (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
    }

    func restoreFullITunesBackupCopy(_ backupRoot: URL, progress: SnapshotProgressHandler? = nil, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Restoring full backup copy...")
        progress?("Preparing full backup restore...", 0.12)

        if self.killMusicBeforeInjectEnabled {
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[Backup] Pre-full-restore Music kill \(killed ? "completed" : "skipped/failed")")
        }

        var afc: AfcClientHandle?
        self.connectAfcClient(&afc)
        guard let afc else {
            completion(false, "AFC unavailable for full restore")
            return
        }
        defer { afc_client_free(afc) }

        progress?("Clearing device iTunes folders...", 0.28)
        for path in ["/iTunes_Control/iTunes", "/iTunes_Control/Music", "/iTunes_Control/Ringtones"] {
            _ = afc_remove_path_and_contents(afc, path)
        }
        _ = afc_make_directory(afc, "/iTunes_Control")

        let localITunesControl = backupRoot.appendingPathComponent("iTunes_Control", isDirectory: true)
        let filesToRestore = localFilesForBackupRestore(under: localITunesControl)
        let restored = uploadLocalTreeToRemote(
            afc: afc,
            localURL: localITunesControl,
            remotePath: "/iTunes_Control",
            progress: { uploaded, _ in
                let total = max(filesToRestore.count, 1)
                progress?("Restoring full backup files \(min(uploaded, total))/\(total)...", 0.34 + (Double(min(uploaded, total)) / Double(total) * 0.58))
            }
        )

        guard restored > 0 else {
            completion(false, "No files restored from full backup")
            return
        }

        self.sendSyncFinishedNotification()
        progress?("Full restore complete.", 1)
        Logger.shared.log("[Backup] Full restore complete, restored \(restored) files")
        completion(true, "Full snapshot restored. Restart Music if it is still cached.")
    }

    func listRemoteFilesForBackup(afc: AfcClientHandle, remotePath: String) -> [String] {
        var info = AfcFileInfo()
        let infoErr = afc_get_file_info(afc, remotePath, &info)
        guard infoErr == nil else {
            return []
        }
        defer { afc_file_info_free(&info) }

        let type = info.st_ifmt.map { String(cString: $0) } ?? ""
        guard type == "S_IFDIR" else {
            return [remotePath]
        }

        var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count: Int = 0
        let listErr = afc_list_directory(afc, remotePath, &entries, &count)
        guard listErr == nil, let entries else {
            return []
        }
        defer { free(entries) }

        var files: [String] = []
        for index in 0..<count {
            guard let ptr = entries[index] else { continue }
            let name = String(cString: ptr)
            guard name != "." && name != ".." else { continue }
            files.append(contentsOf: listRemoteFilesForBackup(afc: afc, remotePath: "\(remotePath)/\(name)"))
        }
        return files
    }

    func copyRemoteFileToLocal(afc: AfcClientHandle, remotePath: String, localURL: URL) -> Int {
        let fm = FileManager.default

        var file: AfcFileHandle?
        afc_file_open(afc, remotePath, AfcRdOnly, &file)
        guard let file else {
            return 0
        }
        defer { afc_file_close(file) }

        var dataPtr: UnsafeMutablePointer<UInt8>?
        var length: Int = 0
        let readErr = afc_file_read_entire(file, &dataPtr, &length)
        guard readErr == nil, let dataPtr, length > 0 else {
            return 0
        }
        defer { afc_file_read_data_free(dataPtr, length) }

        do {
            try fm.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes: dataPtr, count: length).write(to: localURL)
            return 1
        } catch {
            Logger.shared.log("[Backup] Failed saving \(remotePath): \(error)")
            return 0
        }
    }

    func uploadLocalTreeToRemote(afc: AfcClientHandle, localURL: URL, remotePath: String, progress: ((Int, String) -> Void)? = nil) -> Int {
        var uploadedCount = 0
        return uploadLocalTreeToRemote(afc: afc, localURL: localURL, remotePath: remotePath, progress: progress, uploadedCount: &uploadedCount)
    }

    func uploadLocalTreeToRemote(afc: AfcClientHandle, localURL: URL, remotePath: String, progress: ((Int, String) -> Void)?, uploadedCount: inout Int) -> Int {
        let fm = FileManager.default
        guard let values = try? localURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return 0
        }

        if values.isDirectory == true {
            _ = afc_make_directory(afc, remotePath)
            guard let entries = try? fm.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
                return 0
            }

            var uploaded = 0
            for entry in entries {
                uploaded += uploadLocalTreeToRemote(
                    afc: afc,
                    localURL: entry,
                    remotePath: "\(remotePath)/\(entry.lastPathComponent)",
                    progress: progress,
                    uploadedCount: &uploadedCount
                )
            }
            return uploaded
        }

        guard values.isRegularFile == true,
              let data = try? Data(contentsOf: localURL) else {
            return 0
        }

        _ = afc_make_directory(afc, (remotePath as NSString).deletingLastPathComponent)
        _ = afc_remove_path(afc, remotePath)

        var file: AfcFileHandle?
        afc_file_open(afc, remotePath, AfcWrOnly, &file)
        guard let file else {
            return 0
        }
        defer { afc_file_close(file) }

        data.withUnsafeBytes { buffer in
            if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                afc_file_write(file, base, data.count)
            }
        }

        uploadedCount += 1
        progress?(uploadedCount, remotePath)
        return 1
    }

    func localFilesForBackupRestore(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    func directorySize(_ root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += values.fileSize ?? 0
        }
        return total
    }

    func countSongsInSnapshotDB(_ dbURL: URL) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item WHERE media_type = 8", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
            if count > 0 { return count }
        } else if stmt != nil {
            sqlite3_finalize(stmt)
        }
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        return count
    }
    
    func musicFilenamesFromDatabase(_ dbURL: URL) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var names = Set<String>()
        
        let sql = """
        SELECT item_extra.location
        FROM item
        INNER JOIN item_extra ON item.item_pid = item_extra.item_pid
        WHERE item.media_type = 8
          AND item_extra.location != ''
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let location = String(cString: ptr)
                    let filename = (location as NSString).lastPathComponent
                    if !filename.isEmpty {
                        names.insert(filename)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        if !names.isEmpty {
            return names
        }
        
        if sqlite3_prepare_v2(db, "SELECT location FROM item_extra WHERE location != ''", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let location = String(cString: ptr)
                    let filename = (location as NSString).lastPathComponent
                    if !filename.isEmpty {
                        names.insert(filename)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        return names
    }
    
    func artworkPathsFromDatabase(_ dbURL: URL) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var paths = Set<String>()
        if sqlite3_prepare_v2(db, "SELECT relative_path FROM artwork WHERE relative_path != ''", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let rel = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rel.isEmpty {
                        paths.insert(rel)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        return paths.sorted()
    }
    
    func writeSnapshotManifest(_ lines: [String], to manifestURL: URL) {
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.shared.log("[Backup] Failed to write snapshot manifest: \(error.localizedDescription)")
        }
    }

    func playlistsFromDatabase(_ dbURL: URL) -> [(name: String, pid: Int64, songPids: [Int64])] {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var playlists: [(name: String, pid: Int64, songPids: [Int64])] = []
        let getPlaylistsQuery = "SELECT name, container_pid FROM container WHERE contained_media_type = 8 AND distinguished_kind = 0 ORDER BY name"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, getPlaylistsQuery, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
                let name = String(cString: namePtr)
                let pid = sqlite3_column_int64(stmt, 1)

                var pids: [Int64] = []
                let getPidsQuery = "SELECT item_pid FROM container_item WHERE container_pid = ? ORDER BY position ASC"
                var pidStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, getPidsQuery, -1, &pidStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(pidStmt, 1, pid)
                    while sqlite3_step(pidStmt) == SQLITE_ROW {
                        pids.append(sqlite3_column_int64(pidStmt, 0))
                    }
                }
                sqlite3_finalize(pidStmt)
                playlists.append((name, pid, pids))
            }
        }
        sqlite3_finalize(stmt)
        return playlists
    }

    func generatePlaylistM3U8Files(in snapshotDir: URL) -> Int {
        let dbURL = snapshotDir.appendingPathComponent("MediaLibrary.sqlitedb")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return 0 }

        let playlists = playlistsFromDatabase(dbURL)
        guard !playlists.isEmpty else { return 0 }

        let metadataByFilename = carrySongMetadataMapFromDatabase(dbURL)
        var metadataByItemPid: [Int64: CarrySongDBMetadata] = [:]
        for (filename, meta) in metadataByFilename {
            metadataByItemPid[meta.itemPid] = meta
            _ = filename
        }

        let playlistsDir = snapshotDir.appendingPathComponent("Playlists", isDirectory: true)
        FileManager.default.createDirectoryLogged(at: playlistsDir)

        var written = 0
        for playlist in playlists {
            let songs = playlist.songPids.compactMap { metadataByItemPid[$0] }
            guard !songs.isEmpty else { continue }

            var m3uContent = "#EXTM3U\n"
            m3uContent += "#EXT-BYETUNES-PLAYLIST:name=\(playlist.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? playlist.name)\n"

            for song in songs {
                let filename = metadataByFilename.first(where: { $0.value.itemPid == song.itemPid })?.key ?? "\(song.title).m4a"
                let t = song.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let a = song.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let al = song.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let f = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                m3uContent += "#EXT-BYETUNES-METADATA:title=\(t)&artist=\(a)&album=\(al)&durationMs=\(song.durationMs)&fileSize=\(song.fileSize)&remoteFilename=\(f)\n"

                let durationInSeconds = song.durationMs / 1000
                m3uContent += "#EXTINF:\(durationInSeconds),\(song.artist) - \(song.title)\n"
                m3uContent += "\(filename)\n"
            }

            let sanitizedName = Self.sanitizedExportFilenameBase(playlist.name)
            let fileURL = playlistsDir.appendingPathComponent("\(sanitizedName).m3u8")
            do {
                try m3uContent.write(to: fileURL, atomically: true, encoding: .utf8)
                written += 1
            } catch {
                Logger.shared.log("[Backup] Failed to write playlist file \(playlist.name): \(error.localizedDescription)")
            }
        }

        return written
    }
    
    func loadSnapshotMusicFilenames(snapshotDir: URL) -> Set<String> {
        let manifestURL = snapshotDir.appendingPathComponent(snapshotMusicManifestName)
        if
            let content = try? String(contentsOf: manifestURL, encoding: .utf8),
            !content.isEmpty
        {
            let set = Set(
                content
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            if !set.isEmpty {
                return set
            }
        }
        
        let dbURL = snapshotDir.appendingPathComponent("MediaLibrary.sqlitedb")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [] }
        return musicFilenamesFromDatabase(dbURL)
    }
    
    func protectedFilenamesFromAllSnapshots() -> Set<String> {
        let fm = FileManager.default
        let root = snapshotsDirectoryURL
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var protectedSet = Set<String>()
        for dir in entries where dir.hasDirectoryPath && dir.lastPathComponent.hasPrefix("snapshot_") {
            let names = loadSnapshotMusicFilenames(snapshotDir: dir)
            if !names.isEmpty {
                protectedSet.formUnion(names)
            }
        }
        return protectedSet
    }
    
    struct CarrySongDBMetadata {
        let itemPid: Int64
        let title: String
        let artist: String
        let album: String
        let albumPid: Int64
        let albumArtist: String
        let genre: String
        let year: Int
        let durationMs: Int
        let fileSize: Int
        let trackNumber: Int?
        let lyrics: String?
        let explicitRating: Int
        let artworkRelativePath: String?
    }
    
    func firstStringQuery(db: OpaquePointer?, sql: String, itemPid: Int64) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, itemPid)
        if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) {
            let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }
    
    func artworkPathForItemPid(db: OpaquePointer?, itemPid: Int64) -> String? {
        let candidates = [
            """
            SELECT aw.relative_path
            FROM best_artwork_token bat
            JOIN artwork aw ON aw.artwork_token = bat.available_artwork_token
            WHERE bat.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """,
            """
            SELECT aw.relative_path
            FROM best_artwork_token bat
            JOIN artwork aw ON aw.artwork_token = bat.fetchable_artwork_token
            WHERE bat.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """,
            """
            SELECT aw.relative_path
            FROM artwork_token atok
            JOIN artwork aw ON aw.artwork_token = atok.artwork_token
            WHERE atok.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """
        ]
        
        for sql in candidates {
            if let rel = firstStringQuery(db: db, sql: sql, itemPid: itemPid) {
                return rel
            }
        }
        return nil
    }
    
    func carrySongMetadataMapFromDatabase(_ dbURL: URL) -> [String: CarrySongDBMetadata] {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }
        
        let sql = """
        SELECT
            i.item_pid,
            ie.location,
            ie.title,
            IFNULL(ia.item_artist, ''),
            IFNULL(al.album, ''),
            i.album_pid,
            IFNULL(aa.album_artist, ''),
            IFNULL(ge.genre, ''),
            ie.year,
            CAST(ie.total_time_ms AS INTEGER),
            ie.file_size,
            i.track_number,
            ie.content_rating
        FROM item i
        JOIN item_extra ie ON ie.item_pid = i.item_pid
        LEFT JOIN item_artist ia ON ia.item_artist_pid = i.item_artist_pid
        LEFT JOIN album al ON al.album_pid = i.album_pid
        LEFT JOIN album_artist aa ON aa.album_artist_pid = al.album_artist_pid
        LEFT JOIN genre ge ON ge.genre_id = i.genre_id
        WHERE ie.location != ''
        """
        
        var stmt: OpaquePointer?
        var map: [String: CarrySongDBMetadata] = [:]
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemPid = sqlite3_column_int64(stmt, 0)
            guard let locPtr = sqlite3_column_text(stmt, 1) else { continue }
            let location = String(cString: locPtr)
            let filename = (location as NSString).lastPathComponent
            if filename.isEmpty { continue }
            
            let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let artist = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "Unknown Artist"
            let album = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "Unknown Album"
            let albumPid = sqlite3_column_int64(stmt, 5)
            let albumArtist = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let genre = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "Music"
            let year = Int(sqlite3_column_int(stmt, 8))
            let durationMs = Int(sqlite3_column_int(stmt, 9))
            let fileSize = Int(sqlite3_column_int(stmt, 10))
            let trackNumber = Int(sqlite3_column_int(stmt, 11))
            let explicitRating = Int(sqlite3_column_int(stmt, 12))
            let lyrics = firstStringQuery(
                db: db,
                sql: "SELECT lyrics FROM lyrics WHERE item_pid = ? LIMIT 1",
                itemPid: itemPid
            )
            let artworkRelativePath = artworkPathForItemPid(db: db, itemPid: itemPid)

            map[filename] = CarrySongDBMetadata(
                itemPid: itemPid,
                title: title.isEmpty ? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent : title,
                artist: artist.isEmpty ? "Unknown Artist" : artist,
                album: album.isEmpty ? "Unknown Album" : album,
                albumPid: albumPid,
                albumArtist: albumArtist.isEmpty ? (artist.isEmpty ? "Unknown Artist" : artist) : albumArtist,
                genre: genre.isEmpty ? "Music" : genre,
                year: year > 0 ? year : Calendar.current.component(.year, from: Date()),
                durationMs: max(0, durationMs),
                fileSize: max(0, fileSize),
                trackNumber: trackNumber > 0 ? trackNumber : nil,
                lyrics: lyrics,
                explicitRating: explicitRating,
                artworkRelativePath: (artworkRelativePath?.isEmpty == false) ? artworkRelativePath : nil
            )
        }
        
        Logger.shared.log("[Backup] Carry-over metadata map loaded for \(map.count) songs")
        return map
    }
    
}
