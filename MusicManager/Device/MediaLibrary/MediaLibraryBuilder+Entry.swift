import Foundation
import SQLite3
import CommonCrypto
import UIKit

// MARK: - Entry
extension MediaLibraryBuilder {
    // MARK: - Version-Aware Database Generation
    static func createDatabase(songs: [SongMetadata], version: DatabaseVersion, playlistName: String? = nil) throws -> (dbURL: URL, artworkInfo: [ArtworkInfo], pids: [Int64]) {
        Logger.shared.log("[MediaLibraryBuilder] ====== createDatabase CALLED for \(version.description) ======")
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
        
        
        try? FileManager.default.removeItem(at: dbPath)
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw MediaLibraryError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }
        
        
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, &errMsg)
        sqlite3_exec(db, "PRAGMA encoding='UTF-8';", nil, nil, &errMsg)
        sqlite3_exec(db, "PRAGMA user_version = \(version.userVersion);", nil, nil, &errMsg)
        
        
        try createSchema(db: db, version: version)
        
        
        try insertBaseData(db: db)
        
        
        let insertResult = try insertSongsWithExisting(
            db: db,
            songs: songs,
            existingArtists: [:],
            existingAlbums: [String: (pid: Int64, year: Int)](),
            existingGenres: [:],
            existingAlbumArtists: [:],
            version: version,
            reorderSortMap: true
        )
        let songPids = insertResult.pids
        let artworkInfo = insertResult.artworkInfo
        
        
        if let playlistName = playlistName, !playlistName.isEmpty {
            try createPlaylist(db: db, playlistName: playlistName, songPids: songPids)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Database created: \(dbPath.path)")
        
        
        return (dbPath, artworkInfo, songPids)
    }
    
    
    static func addSongsToExistingDatabase(
        existingDbData: Data,
        walData: Data? = nil,
        shmData: Data? = nil,
        newSongs: [SongMetadata],
        playlistName: String? = nil,
        targetPlaylistPid: Int64? = nil,
        existingOnDeviceFiles: Set<String>? = nil,
        version: DatabaseVersion = .unknown
    ) throws -> (dbURL: URL, existingFiles: Set<String>, artworkInfo: [ArtworkInfo], pids: [Int64]) {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
        
        
        try? FileManager.default.removeItem(at: dbPath)
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
        
        
        try existingDbData.write(to: dbPath)
        
        
        if let wal = walData {
            try wal.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
        }
        if let shm = shmData {
            try shm.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw MediaLibraryError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }
        
        
        
        if walData != nil {
            Logger.shared.log("[MediaLibraryBuilder] Checkpointing WAL to apply iOS changes...")
            var errorMsg: UnsafeMutablePointer<CChar>?
            let checkpointResult = sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
            if checkpointResult != SQLITE_OK {
                if let msg = errorMsg {
                    Logger.shared.log("[MediaLibraryBuilder] Checkpoint warning: \(String(cString: msg))")
                    sqlite3_free(errorMsg)
                }
            } else {
                Logger.shared.log("[MediaLibraryBuilder] WAL checkpoint successful - iOS changes applied")
            }
        }
        
        
        var integrityStmt: OpaquePointer?
        var integrityOK = false
        var integrityResult = "unknown"
        if sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &integrityStmt, nil) == SQLITE_OK {
            if sqlite3_step(integrityStmt) == SQLITE_ROW {
                if let resultText = sqlite3_column_text(integrityStmt, 0) {
                    integrityResult = String(cString: resultText)
                    integrityOK = integrityResult == "ok"
                    Logger.shared.log("[MediaLibraryBuilder] Database integrity check: \(integrityOK ? "PASSED" : "FAILED")")
                }
            }
        }
        sqlite3_finalize(integrityStmt)

        if !integrityOK {
            Logger.shared.log("[MediaLibraryBuilder] Database integrity check failed (\(integrityResult)) — aborting merge instead of writing on top of a corrupt database.")
            throw MediaLibraryError.integrityCheckFailed(integrityResult)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Ensuring base_location 3840/3900 exist...")
        try? executeSQL(db, "INSERT OR IGNORE INTO base_location (base_location_id, path) VALUES (3840, 'iTunes_Control/Music/F00')")
        try? executeSQL(db, "INSERT OR IGNORE INTO base_location (base_location_id, path) VALUES (3900, 'iTunes_Control/Ringtones')")
        
        
        
        if let onDeviceFiles = existingOnDeviceFiles {
            cleanupGhostRecords(db: db, existingOnDeviceFiles: onDeviceFiles)
        }
        
        
        let existingFiles = getExistingFilenames(db: db)
        Logger.shared.log("[MediaLibraryBuilder] Found \(existingFiles.count) existing songs in database")
        
        
        let existingArtists = getExistingArtists(db: db)
        let existingAlbums = getExistingAlbums(db: db)
        let existingGenres = getExistingGenres(db: db)
        let existingAlbumArtists = getExistingAlbumArtists(db: db)
        
        
        let insertResult = try insertSongsWithExisting(
            db: db,
            songs: newSongs,
            existingArtists: existingArtists,
            existingAlbums: existingAlbums,
            existingGenres: existingGenres,
            existingAlbumArtists: existingAlbumArtists,
            version: version,
            reorderSortMap: false
        )
        let songPids = insertResult.pids
        let artworkInfo = insertResult.artworkInfo
        
        
        if let targetPid = targetPlaylistPid {
            try addToPlaylist(db: db, containerPid: targetPid, songPids: songPids)
        } else if let playlistName = playlistName, !playlistName.isEmpty {
            try createPlaylist(db: db, playlistName: playlistName, songPids: songPids)
        }
        
        
        
        var errorMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
        if let msg = errorMsg {
            Logger.shared.log("[MediaLibraryBuilder] Final checkpoint warning: \(String(cString: msg))")
            sqlite3_free(errorMsg)
        }
        
        
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        
        Logger.shared.log("[MediaLibraryBuilder] Merged database saved: \(dbPath.path)")
        return (dbPath, existingFiles, artworkInfo, songPids)
    }

    static func repairAlphabeticalOrdering(db: OpaquePointer?) throws {
        Logger.shared.log("[MediaLibraryBuilder] 🔧 SORT FIX: Reordering sort_map alphabetically...")

        try executeSQL(db, """
            UPDATE sort_map SET name_section =
                CASE
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 65 AND 90
                    THEN UNICODE(UPPER(SUBSTR(name, 1, 1))) - 65
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 192 AND 197 THEN 0
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) = 199 THEN 2
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 200 AND 203 THEN 4
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 204 AND 207 THEN 8
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) = 209 THEN 13
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 210 AND 214 THEN 14
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) BETWEEN 217 AND 220 THEN 20
                    WHEN UNICODE(UPPER(SUBSTR(name, 1, 1))) = 221 THEN 24
                    ELSE 26
                END
        """)

        try executeSQL(db, "DROP TABLE IF EXISTS _sort_reorder")
        try executeSQL(db, """
            CREATE TEMP TABLE _sort_reorder AS
            SELECT name, name_order AS old_order, name_section,
                   ROW_NUMBER() OVER (ORDER BY
                       CASE name_section WHEN 26 THEN -1 ELSE name_section END ASC,
                       sort_key ASC
                   ) AS new_order
            FROM sort_map
        """)

        try executeSQL(db, """
            UPDATE item SET
                title_order = COALESCE((SELECT new_order FROM _sort_reorder WHERE old_order = item.title_order), title_order),
                title_order_section = COALESCE((SELECT name_section FROM _sort_reorder WHERE old_order = item.title_order), title_order_section),
                item_artist_order = COALESCE((SELECT new_order FROM _sort_reorder WHERE old_order = item.item_artist_order), item_artist_order),
                item_artist_order_section = COALESCE((SELECT name_section FROM _sort_reorder WHERE old_order = item.item_artist_order), item_artist_order_section),
                album_order = COALESCE((SELECT new_order FROM _sort_reorder WHERE old_order = item.album_order), album_order),
                album_order_section = COALESCE((SELECT name_section FROM _sort_reorder WHERE old_order = item.album_order), album_order_section),
                album_artist_order = COALESCE((SELECT new_order FROM _sort_reorder WHERE old_order = item.album_artist_order), album_artist_order),
                album_artist_order_section = COALESCE((SELECT name_section FROM _sort_reorder WHERE old_order = item.album_artist_order), album_artist_order_section),
                genre_order = COALESCE((SELECT new_order FROM _sort_reorder WHERE old_order = item.genre_order), genre_order),
                genre_order_section = COALESCE((SELECT name_section FROM _sort_reorder WHERE old_order = item.genre_order), genre_order_section)
        """)

        try executeSQL(db, "UPDATE sort_map SET name_order = -(name_order + 1)")
        try executeSQL(db, """
            UPDATE sort_map SET name_order = (
                SELECT new_order FROM _sort_reorder WHERE _sort_reorder.name = sort_map.name
            )
        """)

        try executeSQL(db, """
            UPDATE item_search SET
                search_title = (SELECT title_order FROM item WHERE item.item_pid = item_search.item_pid),
                search_album = (SELECT album_order FROM item WHERE item.item_pid = item_search.item_pid),
                search_artist = (SELECT item_artist_order FROM item WHERE item.item_pid = item_search.item_pid),
                search_album_artist = (SELECT album_artist_order FROM item WHERE item.item_pid = item_search.item_pid)
        """)

        try executeSQL(db, "DROP TABLE IF EXISTS _sort_reorder")
        Logger.shared.log("[MediaLibraryBuilder] ✅ Sort reorder complete")
    }

    static func getExistingFilenames(db: OpaquePointer?) -> Set<String> {
        var filenames = Set<String>()
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT location FROM item_extra", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let filenamePtr = sqlite3_column_text(stmt, 0) {
                    filenames.insert(String(cString: filenamePtr))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return filenames
    }
    
    
    static func cleanupGhostRecords(db: OpaquePointer?, existingOnDeviceFiles: Set<String>) {
        Logger.shared.log("[MediaLibraryBuilder] Starting Ghost Record Cleanup...")
        var pidsToDelete: [Int64] = []
        var stmt: OpaquePointer?
        
        
        
        let query = """
            SELECT item.item_pid, item_extra.location 
            FROM item 
            JOIN item_extra ON item.item_pid = item_extra.item_pid 
            WHERE item.base_location_id = 3840
        """
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pid = sqlite3_column_int64(stmt, 0)
                if let locPtr = sqlite3_column_text(stmt, 1) {
                    let location = String(cString: locPtr)
                    let filename = (location as NSString).lastPathComponent
                    
                    
                    if !location.isEmpty && !existingOnDeviceFiles.contains(filename) {
                        Logger.shared.log("[MediaLibraryBuilder] Found GHOST record: PID \(pid), file '\(filename)' missing from device")
                        pidsToDelete.append(pid)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        if pidsToDelete.isEmpty {
            Logger.shared.log("[MediaLibraryBuilder] No ghost records found.")
            return
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Deleting \(pidsToDelete.count) ghost records...")
        
        for pid in pidsToDelete {
            deleteItemRows(db: db, pid: pid)
        }
    }

    static func getExistingArtists(db: OpaquePointer?) -> [String: Int64] {
        var artists: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT item_artist, item_artist_pid FROM item_artist", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    artists[name] = pid
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return artists
    }
    
    
    static func getExistingAlbums(db: OpaquePointer?) -> [String: (pid: Int64, year: Int)] {
        var albums: [String: (pid: Int64, year: Int)] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT album, album_pid, album_year FROM album", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    let year = sqlite3_column_int(stmt, 2)
                    albums[name] = (pid, Int(year))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return albums
    }
    
    
    static func getExistingGenres(db: OpaquePointer?) -> [String: Int64] {
        var genres: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT genre, genre_id FROM genre", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    genres[name] = pid
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return genres
    }
    
    
    static func getExistingAlbumArtists(db: OpaquePointer?) -> [String: Int64] {
        var albumArtists: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT album_artist, album_artist_pid FROM album_artist", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    albumArtists[name] = pid
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return albumArtists
    }
    
    
    static func getExistingSongSignatures(db: OpaquePointer?) -> [String: Int64] {
        var signatures: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        
        let query = """
            SELECT item.item_pid, item_extra.title, item_artist.item_artist, album.album 
            FROM item 
            LEFT JOIN item_extra ON item.item_pid = item_extra.item_pid 
            LEFT JOIN item_artist ON item.item_artist_pid = item_artist.item_artist_pid 
            LEFT JOIN album ON item.album_pid = album.album_pid
            WHERE item.media_type = 8
        """
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pid = sqlite3_column_int64(stmt, 0)
                
                let titlePtr = sqlite3_column_text(stmt, 1)
                let artistPtr = sqlite3_column_text(stmt, 2)
                let albumPtr = sqlite3_column_text(stmt, 3)
                
                let title = titlePtr != nil ? String(cString: titlePtr!) : ""
                let artist = artistPtr != nil ? String(cString: artistPtr!) : ""
                let album = albumPtr != nil ? String(cString: albumPtr!) : ""
                
                if !title.isEmpty {
                    let signature = "\(title)|\(artist)|\(album)"
                    signatures[signature] = pid
                }
            }
        }
        sqlite3_finalize(stmt)
        return signatures
    }

    

    
    static func fileDateAdded(for url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return nil
        }
        guard let date = values.creationDate ?? values.contentModificationDate else {
            return nil
        }
        return Int(date.timeIntervalSince1970)
    }
}
