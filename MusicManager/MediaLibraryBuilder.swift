import Foundation
import SQLite3
import CommonCrypto

/// Compute SHA1 hash of data and return as lowercase hex string
private func computeSHA1(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
        _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}

/// Search iTunes API for artwork URL (synchronous for use in DB building)
/// Returns a high-resolution (1200x1200) artwork URL if found, nil otherwise
private func fetchArtworkURLFromiTunes(title: String, artist: String) -> String? {
    // Build search query
    let searchQuery = "\(artist) \(title)"
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    guard let url = URL(string: "https://itunes.apple.com/search?term=\(searchQuery)&entity=song&limit=5") else {
        return nil
    }
    
    // Synchronous request (running in background thread anyway)
    let semaphore = DispatchSemaphore(value: 0)
    var artworkURL: String?
    
    URLSession.shared.dataTask(with: url) { data, response, error in
        defer { semaphore.signal() }
        
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first,
              let artworkUrl100 = firstResult["artworkUrl100"] as? String else {
            return
        }
        
        // Convert 100x100 URL to 1200x1200 for high resolution
        artworkURL = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
    }.resume()
    
    _ = semaphore.wait(timeout: .now() + 5)  // 5 second timeout
    return artworkURL
}


class MediaLibraryBuilder {
    
    // MARK: - Artwork Info for ArtworkDB
    
    /// Holds info needed to generate ArtworkDB entries
    struct ArtworkInfo {
        let itemPid: Int64        // item_pid from MediaLibrary
        let artworkHash: String   // SHA1 hash path like "ab/cdef1234..."
        let artworkToken: String  // The token used in MediaLibrary (e.g. "1001")
        let fileSize: UInt32      // Size of the artwork file in bytes
    }
    
    // MARK: - Integrity Helper
    
    /// Generates the SQL Hex Literal for the integrity blob.
    private static func generateIntegrityHex(filename: String) -> String {
        
        return "X''"
        /*
        let pathKey = "iTunes_Control/Music/F00/\(filename)"
        guard let data = pathKey.data(using: .utf8) else { return "X''" }
        let hex = data.map { String(format: "%02X", $0) }.joined()
        return "X'\(hex)'"
        */
    }
    
    // MARK: - Audio Format Helpers
    
    /// Convert a four-character code string (e.g. "flac") into an integer
    private static func fourCC(_ str: String) -> Int {
        // Convert up to 4 ASCII bytes into a 32-bit integer, big-endian packing.
        let padded = Array(str.utf8) + Array(repeating: 0x20, count: max(0, 4 - str.utf8.count))
        var val = 0
        for i in 0..<4 {
            val = (val << 8) | Int(padded[i])
        }
        return val
    }

    /// Map file extension to item_playback.audio_format
    /// Supports: MP3, FLAC, M4A, AAC, ALAC, WAV
    private static func audioFormatForExtension(_ ext: String) -> Int {
        switch ext.lowercased() {
        case "mp3":
            return 301
        case "flac":
            return fourCC("fLaC")  // FLAC FourCC
        case "m4a", "aac", "m4r":
            return fourCC("aac ")  // AAC container
        case "alac":
            return fourCC("alac") // Apple Lossless
        case "wav", "wave":
            return fourCC("WAVE") // WAV format
        default:
            return 0  // Unknown format
        }
    }
    
    /// Create a new database with the songs - RENAMED TO v104 TO FORCE REBUILD
    static func createDatabase_v104(songs: [SongMetadata], playlistName: String? = nil) throws -> (dbURL: URL, artworkInfo: [ArtworkInfo], pids: [Int64]) {
        Logger.shared.log("[MediaLibraryBuilder] ====== createDatabase_v104 CALLED ======")
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
        
        // Remover el archivo si ya existe
        try? FileManager.default.removeItem(at: dbPath)
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw MediaLibraryError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }
        
        
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, &errMsg)
        sqlite3_exec(db, "PRAGMA encoding='UTF-8';", nil, nil, &errMsg)
        sqlite3_exec(db, "PRAGMA user_version = 2320030;", nil, nil, &errMsg)
        
        // Crear todas las tablas con el schema completo
        try createSchema(db: db)
        
        // Insertar data basica
        try insertBaseData(db: db)
        
        // Meter las canciones y sus entities usando la logica unificada (que tiene los fixes de Album Artist)
        let insertResult = try insertSongsWithExisting(
            db: db,
            songs: songs,
            existingArtists: [:],
            existingAlbums: [:],
            existingGenres: [:],
            existingAlbumArtists: [:]
        )
        let songPids = insertResult.pids
        let artworkInfo = insertResult.artworkInfo
        
        // Create playlist if name provided
        if let playlistName = playlistName, !playlistName.isEmpty {
            try createPlaylist(db: db, playlistName: playlistName, songPids: songPids)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Database creada: \(dbPath.path)")
        // Logger.shared.log("[MediaLibraryBuilder] Size: \((try? FileManager.default.attributesOfItem(atPath: dbPath.path)[.size]) ?? 0) bytes")
        
        return (dbPath, artworkInfo, songPids)
    }
    
    
    static func addSongsToExistingDatabase(
        existingDbData: Data,
        walData: Data? = nil,
        shmData: Data? = nil,
        newSongs: [SongMetadata],
        playlistName: String? = nil,
        targetPlaylistPid: Int64? = nil,
        existingOnDeviceFiles: Set<String>? = nil
    ) throws -> (dbURL: URL, existingFiles: Set<String>, artworkInfo: [ArtworkInfo], pids: [Int64]) {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
        
        // Remove old files
        try? FileManager.default.removeItem(at: dbPath)
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
        
        // Write main DB
        try existingDbData.write(to: dbPath)
        
        // Write WAL/SHM if present
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
        
        // CRITICAL: Checkpoint WAL FIRST to merge any pending iOS changes (like song deletions)
        // This ensures we're working with a fully consistent database state
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
        
        // Run integrity check to verify database is usable
        var integrityStmt: OpaquePointer?
        var integrityOK = false
        if sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &integrityStmt, nil) == SQLITE_OK {
            if sqlite3_step(integrityStmt) == SQLITE_ROW {
                if let resultText = sqlite3_column_text(integrityStmt, 0) {
                    integrityOK = String(cString: resultText) == "ok"
                    Logger.shared.log("[MediaLibraryBuilder] Database integrity check: \(integrityOK ? "PASSED" : "FAILED")")
                }
            }
        }
        sqlite3_finalize(integrityStmt)
        
        if !integrityOK {
            Logger.shared.log("[MediaLibraryBuilder] WARNING: Database integrity check failed, but continuing...")
        }
        
        // CLEANUP GHOST RECORDS
        // If we know what files are actually on the device, we can delete DB records that point to nothing.
        if let onDeviceFiles = existingOnDeviceFiles {
            cleanupGhostRecords(db: db, existingOnDeviceFiles: onDeviceFiles)
        }
        
        // Checar filenames existentes pa no re-uploadear
        let existingFiles = getExistingFilenames(db: db)
        Logger.shared.log("[MediaLibraryBuilder] Found \(existingFiles.count) existing songs in database")
        
        // Get existing entities to avoid duplicates
        let existingArtists = getExistingArtists(db: db)
        let existingAlbums = getExistingAlbums(db: db)
        let existingGenres = getExistingGenres(db: db)
        let existingAlbumArtists = getExistingAlbumArtists(db: db)
        
        // Insert new songs with entity reuse and collect pids
        let insertResult = try insertSongsWithExisting(
            db: db, 
            songs: newSongs,
            existingArtists: existingArtists,
            existingAlbums: existingAlbums,
            existingGenres: existingGenres,
            existingAlbumArtists: existingAlbumArtists
        )
        let songPids = insertResult.pids
        let artworkInfo = insertResult.artworkInfo
        
        // Handle playlist assignment
        if let targetPid = targetPlaylistPid {
            try addToPlaylist(db: db, containerPid: targetPid, songPids: songPids)
        } else if let playlistName = playlistName, !playlistName.isEmpty {
            try createPlaylist(db: db, playlistName: playlistName, songPids: songPids)
        }
        
        // Final checkpoint to ensure all changes are written to the main DB file
        // We use DELETE mode to remove WAL/SHM files for cleaner upload
        var errorMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
        if let msg = errorMsg {
            Logger.shared.log("[MediaLibraryBuilder] Final checkpoint warning: \(String(cString: msg))")
            sqlite3_free(errorMsg)
        }
        
        // Switch to DELETE journal mode for the final file (cleaner for upload)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        
        Logger.shared.log("[MediaLibraryBuilder] Merged database saved: \(dbPath.path)")
        return (dbPath, existingFiles, artworkInfo, songPids)
    }
    
    /// Agarrar los filenames que ya existen en la base
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
    
    /// Remove database records that point to files that do not exist on the device
    private static func cleanupGhostRecords(db: OpaquePointer?, existingOnDeviceFiles: Set<String>) {
        Logger.shared.log("[MediaLibraryBuilder] Starting Ghost Record Cleanup...")
        var pidsToDelete: [Int64] = []
        var stmt: OpaquePointer?
        
        // Only check items with base_location_id = 3840 (Synched media) to avoid touching Cloud/System items
        // Join with item_extra to get the filename (location)
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
                    
                    // If the file mentioned in DB is NOT in the list of actual files -> DELETE IT
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
            // Delete from all relevant tables
            try? executeSQL(db, "DELETE FROM item WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_extra WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_playback WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_stats WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_store WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_video WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM item_search WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM lyrics WHERE item_pid=\(pid)")
            try? executeSQL(db, "DELETE FROM chapter WHERE item_pid=\(pid)")
            
            
        }
    }
    
    /// Get existing artists from database
    private static func getExistingArtists(db: OpaquePointer?) -> [String: Int64] {
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
    
    /// Get existing albums from database
    private static func getExistingAlbums(db: OpaquePointer?) -> [String: Int64] {
        var albums: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, "SELECT album, album_pid FROM album", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    albums[name] = pid
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return albums
    }
    
    /// Get existing genres from database
    private static func getExistingGenres(db: OpaquePointer?) -> [String: Int64] {
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
    
    /// Get existing album artists from database
    private static func getExistingAlbumArtists(db: OpaquePointer?) -> [String: Int64] {
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
    
    /// Get existing song signatures for duplicate detection
    private static func getExistingSongSignatures(db: OpaquePointer?) -> [String: Int64] {
        var signatures: [String: Int64] = [:]
        var stmt: OpaquePointer?
        
        // Join tables to get Title, Artist, Album for each song
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

    

    /// Insert songs while reusing existing entities
    @discardableResult
    private static func insertSongsWithExisting(
        db: OpaquePointer?,
        songs: [SongMetadata],
        existingArtists: [String: Int64],
        existingAlbums: [String: Int64],
        existingGenres: [String: Int64],
        existingAlbumArtists: [String: Int64]
    ) throws -> (pids: [Int64], artworkInfo: [ArtworkInfo]) {
        let now = Int(Date().timeIntervalSince1970)
        
        // Get max track count (for sequential artwork tokens)
        var maxTrackNum = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxTrackNum = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        var trackNum = maxTrackNum + 1
        
        // Mutable copies for tracking new entities
        var artists = existingArtists
        var albums = existingAlbums
        var genres = existingGenres
        var albumArtists = existingAlbumArtists
        
        // Track new entities to insert
        var newArtists: [String: Int64] = [:]
        var newAlbums: [String: Int64] = [:]
        var newGenres: [String: Int64] = [:]
        var newAlbumArtists: [String: Int64] = [:]
        
        // Track representative_item_pid for NEW entities only
        var artistRepItem: [String: Int64] = [:]
        var albumRepItem: [String: Int64] = [:]
        var genreRepItem: [String: Int64] = [:]
        var albumArtistRepItem: [String: Int64] = [:]
        
        // Track processed albums for artwork optimization
        var processedAlbumArtworkPids = Set<Int64>()
        
        var insertedPids: [Int64] = []
        var collectedArtworkInfo: [ArtworkInfo] = []
        
        // Detect existing songs to reuse PIDs (Ghost Song Fix)
        // Map "Title|Artist|Album" -> PID
        let existingSignatures = getExistingSongSignatures(db: db)
        Logger.shared.log("[MediaLibraryBuilder] Found \(existingSignatures.count) existing song signatures for duplicate checking")
        
        for song in songs {
            // Check if song already exists
            let signature = "\(song.title)|\(song.artist)|\(song.album)"
            
            let itemPid: Int64
            if let existingPid = existingSignatures[signature] {
                itemPid = existingPid
                Logger.shared.log("[MediaLibraryBuilder] Resurrecting existing song PID \(itemPid): \(song.title)")
            } else {
                itemPid = SongMetadata.generatePersistentId()
            }
            
            insertedPids.append(itemPid)
            
            // Get or create artist - track first item as representative for NEW entities
            let artistPid: Int64
            if let existing = artists[song.artist] {
                artistPid = existing
            } else {
                let newPid = SongMetadata.generatePersistentId()
                artists[song.artist] = newPid
                newArtists[song.artist] = newPid
                artistRepItem[song.artist] = itemPid  // First song for this NEW artist
                artistPid = newPid
            }
            
            
            let effectiveAlbumArtistName = song.albumArtist ?? song.artist
            let albumArtistPid: Int64
            if let existing = albumArtists[effectiveAlbumArtistName] {
                albumArtistPid = existing
            } else {
                let newPid = SongMetadata.generatePersistentId()
                albumArtists[effectiveAlbumArtistName] = newPid
                newAlbumArtists[effectiveAlbumArtistName] = newPid
                albumArtistRepItem[effectiveAlbumArtistName] = itemPid  // First song for this NEW album artist
                albumArtistPid = newPid
            }
            
            // Get or create album - track first item as representative for NEW entities
            let albumPid: Int64
            if let existing = albums[song.album] {
                albumPid = existing
            } else {
                let newPid = SongMetadata.generatePersistentId()
                albums[song.album] = newPid
                newAlbums[song.album] = newPid
                albumRepItem[song.album] = itemPid  // First song for this NEW album
                albumPid = newPid
            }
            
            // Get or create genre - track first item as representative for NEW entities
            let genreId: Int64
            if let existing = genres[song.genre] {
                genreId = existing
            } else {
                let newPid = SongMetadata.generatePersistentId()
                genres[song.genre] = newPid
                newGenres[song.genre] = newPid
                genreRepItem[song.genre] = itemPid  // First song for this NEW genre
                genreId = newPid
            }
            
            // Generate sort orders by inserting into sort_map - CRITICAL for Albums/Artists to appear in lists
            let titleOrder = insertSortMap(db: db, name: song.title)
            let artistOrder = insertSortMap(db: db, name: song.artist)
            let albumOrder = insertSortMap(db: db, name: song.album)
            let genreOrder = insertSortMap(db: db, name: song.genre)
            // Ensure Album Artist is also in sort map
             _ = insertSortMap(db: db, name: effectiveAlbumArtistName)
            
            Logger.shared.log("[MediaLibraryBuilder] Merging: \(song.title) -> \(song.remoteFilename)")
            
            // Resolve metadata with fallbacks
            let dbTrackNum = song.trackNumber ?? trackNum
            let dbTrackCount = song.trackCount ?? 1
            let dbDiscNum = song.discNumber ?? 1
            let dbDiscCount = song.discCount ?? 1
            
            // Explicitly DELETE to ensure stale data (like bad years) is removed
            // INSERT OR REPLACE *should* work, but let's be nuclear to fix the persistence issue.
            try? executeSQL(db, "DELETE FROM item WHERE item_pid = \(itemPid)")
            try? executeSQL(db, "DELETE FROM item_extra WHERE item_pid = \(itemPid)")
            try? executeSQL(db, "DELETE FROM item_playback WHERE item_pid = \(itemPid)")
            try? executeSQL(db, "DELETE FROM item_stats WHERE item_pid = \(itemPid)")
            try? executeSQL(db, "DELETE FROM item_store WHERE item_pid = \(itemPid)")
            try? executeSQL(db, "DELETE FROM item_search WHERE item_pid = \(itemPid)")
            
            // INSERT into item table
            try executeSQL(db, """
                INSERT INTO item (
                    item_pid, media_type, title_order, title_order_section,
                    item_artist_pid, item_artist_order, item_artist_order_section,
                    series_name_order, series_name_order_section,
                    album_pid, album_order, album_order_section,
                    album_artist_pid, album_artist_order, album_artist_order_section,
                    composer_pid, composer_order, composer_order_section,
                    genre_id, genre_order, genre_order_section,
                    disc_number, track_number, episode_sort_id,
                    base_location_id, remote_location_id,
                    exclude_from_shuffle, keep_local, keep_local_status, keep_local_status_reason, keep_local_constraints,
                    in_my_library, is_compilation, date_added, show_composer, is_music_show, date_downloaded, download_source_container_pid
                ) VALUES (
                    \(itemPid), 8, \(titleOrder), 1,
                    \(artistPid), \(artistOrder), 1,
                    0, 27,
                    \(albumPid), \(albumOrder), 1,
                    \(albumArtistPid), \(artistOrder), 1,
                    0, 0, 27,
                    \(genreId), \(genreOrder), 1,
                    \(dbDiscNum), \(dbTrackNum), 1,
                    3840, 0,
                    0, 1, 2, 0, 0,
                    1, 0, \(now), 0, 0, \(now), 0
                )
            """)
            
            // INSERT into item_extra
            let escapedTitle = song.title.replacingOccurrences(of: "'", with: "''")
            let escapedFilename = song.remoteFilename.replacingOccurrences(of: "'", with: "''")
            try executeSQL(db, """
                INSERT INTO item_extra (
                    item_pid, title, sort_title, disc_count, track_count, total_time_ms, year,
                    location, file_size, integrity, is_audible_audio_book, date_modified,
                    media_kind, content_rating, content_rating_level, is_user_disabled, bpm, genius_id,
                    location_kind_id
                ) VALUES (
                    \(itemPid), '\(escapedTitle)', '\(escapedTitle)', \(dbDiscCount), \(dbTrackCount), \(song.durationMs), \(song.year),
                    '\(escapedFilename)', \(song.fileSize), \(MediaLibraryBuilder.generateIntegrityHex(filename: song.remoteFilename)), 0, \(now),
                    1, 0, 0, 0, 0, 0,
                    42
                )
            """)
            
            // INSERT into item_playback
            let audioFmt = audioFormatForExtension(URL(fileURLWithPath: song.remoteFilename).pathExtension)
            try executeSQL(db, """
                INSERT INTO item_playback (
                    item_pid, audio_format, bit_rate, codec_type, codec_subtype, data_kind,
                    duration, has_video, relative_volume, sample_rate
                ) VALUES (
                    \(itemPid), \(audioFmt), 320, 0, 0, 0,
                    0, 0, 0, 44100.0
                )
            """)
            
            // INSERT into item_stats
            try executeSQL(db, "INSERT OR REPLACE INTO item_stats (item_pid, date_accessed) VALUES (\(itemPid), \(now))")
            
            // INSERT into item_store
            // Re-enabling as disabling it caused 'Ghost Albums' (Songs hidden)
            let syncId = SongMetadata.generatePersistentId()
            try executeSQL(db, "INSERT OR REPLACE INTO item_store (item_pid, sync_id, sync_in_my_library) VALUES (\(itemPid), \(syncId), 1)")
            
            // INSERT into item_video
            try executeSQL(db, "INSERT OR REPLACE INTO item_video (item_pid) VALUES (\(itemPid))")
            
            // INSERT into item_search
            try executeSQL(db, """
                INSERT OR REPLACE INTO item_search (item_pid, search_title, search_album, search_artist, search_composer, search_album_artist)
                VALUES (\(itemPid), \(titleOrder), \(albumOrder), \(artistOrder), 0, \(artistOrder))
            """)
            
            // INSERT into lyrics
            try executeSQL(db, "INSERT OR REPLACE INTO lyrics (item_pid) VALUES (\(itemPid))")
            
            // INSERT into chapter
            try executeSQL(db, "INSERT OR REPLACE INTO chapter (item_pid) VALUES (\(itemPid))")
            
            // ARTWORK DATABASE with CORRECT HASH ALGORITHM
            // iOS computes artwork path as SHA1(artwork_token), NOT SHA1(image_data)!
            // The artwork_token can be any unique string - we use a numeric token.
            // relative_path = SHA1(artwork_token) split as "XX/rest_of_hash"
            if song.artworkData != nil {
                // Use a simple numeric token based on the track number
                let artToken = "100\(trackNum)"
                
                // CORRECT ALGORITHM: Hash the TOKEN, not the image data
                var sha1Hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                let tokenData = artToken.data(using: .utf8)!
                tokenData.withUnsafeBytes { bytes in
                    _ = CC_SHA1(bytes.baseAddress, CC_LONG(tokenData.count), &sha1Hash)
                }
                let hashString = sha1Hash.map { String(format: "%02x", $0) }.joined()
                let folderName = String(hashString.prefix(2))
                let fileName = String(hashString.dropFirst(2))
                let relativePath = "\(folderName)/\(fileName)"
                
                print("[MediaLibraryBuilder] ARTWORK (correct algorithm):")
                print("  -> Token: \(artToken)")
                print("  -> SHA1(token): \(hashString)")
                print("  -> relativePath: \(relativePath)")
                
                // Collect for artwork file upload (using image data, but stored at token-based path)
                collectedArtworkInfo.append(ArtworkInfo(
                    itemPid: itemPid, 
                    artworkHash: relativePath, 
                    artworkToken: artToken, 
                    fileSize: UInt32(song.artworkData!.count)
                ))
                
                // 1. Insert into artwork table with ColorAnalysis (required for album artwork display)
                // ColorAnalysis provides background/text colors for album view - stored in interest_data column
                let colorAnalysis = """
                {"ColorAnalysis":{"1":{"primaryTextColorLight":"NO","secondaryTextColorLight":"NO","secondaryTextColor":"#FFFFFF","tertiaryTextColorLight":"NO","primaryTextColor":"#FFFFFF","tertiaryTextColor":"#CCCCCC","backgroundColorLight":"NO","backgroundColor":"#333333"}}}
                """
                try executeSQL(db, """
                    INSERT OR REPLACE INTO artwork (
                        artwork_token, artwork_source_type, relative_path, artwork_type, 
                        interest_data, artwork_variant_type
                    ) VALUES (
                        '\(artToken)', 1, '\(relativePath)', 1,
                        '\(colorAnalysis)', 0
                    )
                """)
                
                // 2. Insert into artwork_token table (link to item, album, artist)
                try executeSQL(db, """
                    INSERT OR REPLACE INTO artwork_token (
                        artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                    ) VALUES (
                        '\(artToken)', 1, 1, \(itemPid), 0, 0
                    )
                """)
                // entity_type=1 for album table reference
                try executeSQL(db, """
                    INSERT OR REPLACE INTO artwork_token (
                        artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                    ) VALUES (
                        '\(artToken)', 1, 1, \(albumPid), 1, 0
                    )
                """)
                // entity_type=4 for album artwork in library view (iOS uses this!)
                try executeSQL(db, """
                    INSERT OR REPLACE INTO artwork_token (
                        artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                    ) VALUES (
                        '\(artToken)', 1, 1, \(albumPid), 4, 0
                    )
                """)
                try executeSQL(db, """
                    INSERT OR REPLACE INTO artwork_token (
                        artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                    ) VALUES (
                        '\(artToken)', 1, 1, \(artistPid), 2, 0
                    )
                """)
                
                // 3. Insert into best_artwork_token table
                // fetchable_artwork_token should be EMPTY for local artwork (not fetched remotely)
                try executeSQL(db, """
                    INSERT OR REPLACE INTO best_artwork_token (
                        entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                        fetchable_artwork_source_type, artwork_variant_type
                    ) VALUES (
                        \(itemPid), 0, 1, '\(artToken)', '', 0, 0
                    )
                """)
                if !processedAlbumArtworkPids.contains(albumPid) {
                    // entity_type=1 for album table reference
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(albumPid), 1, 1, '\(artToken)', '', 0, 0
                        )
                    """)
                    // entity_type=4 for album artwork in library view
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(albumPid), 4, 1, '\(artToken)', '', 0, 0
                        )
                    """)
                    processedAlbumArtworkPids.insert(albumPid)
                }
                try executeSQL(db, """
                    INSERT OR REPLACE INTO best_artwork_token (
                        entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                        fetchable_artwork_source_type, artwork_variant_type
                    ) VALUES (
                        \(artistPid), 2, 1, '\(artToken)', '', 0, 0
                    )
                """)
            }
            
            trackNum += 1
        }
        
        // Insertar artistas nuevos
        for (artistName, artistPid) in newArtists {
            let escapedName = artistName.replacingOccurrences(of: "'", with: "''")
            let groupingKey = SongMetadata.generateGroupingKey(artistName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let syncId = SongMetadata.generatePersistentId()
            let repItem = artistRepItem[artistName] ?? 0
            try executeSQL(db, """
                INSERT INTO item_artist (item_artist_pid, item_artist, sort_item_artist, series_name, grouping_key, sync_id, keep_local, representative_item_pid)
                VALUES (\(artistPid), '\(escapedName)', '\(escapedName)', '', X'\(groupingHex)', \(syncId), 1, \(repItem))
            """)
        }
        
        // Insertar album artistas nuevos - incluye el sort/name order pal Artists view
        for (artistName, aaPid) in newAlbumArtists {
            let escapedName = artistName.replacingOccurrences(of: "'", with: "''")
            let groupingKey = SongMetadata.generateGroupingKey(artistName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let syncId = SongMetadata.generatePersistentId()
            let repItem = albumArtistRepItem[artistName] ?? 0
            // Get/create sort_map entry for this artist - needed for Artists list view
            let nameOrder = insertSortMap(db: db, name: artistName)
            // Calculate section (first letter: A=1, B=2, etc., non-alpha=27)
            var sortOrderSection = 27
            if let firstChar = artistName.uppercased().first {
                let charValue = Int(firstChar.asciiValue ?? 0)
                if charValue >= 65 && charValue <= 90 { // A-Z
                    sortOrderSection = charValue - 64 // A=1, B=2, etc.
                }
            }
            try executeSQL(db, """
                INSERT INTO album_artist (album_artist_pid, album_artist, sort_album_artist, grouping_key, sync_id, keep_local, representative_item_pid, sort_order, sort_order_section, name_order)
                VALUES (\(aaPid), '\(escapedName)', '\(escapedName)', X'\(groupingHex)', \(syncId), 1, \(repItem), \(nameOrder), \(sortOrderSection), \(nameOrder))
            """)
        }
        
        // INSERT new albums only
        for (albumName, albumPid) in newAlbums {
            let escapedName = albumName.replacingOccurrences(of: "'", with: "''")
            let groupingKey = SongMetadata.generateGroupingKey(albumName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            if let song = songs.first(where: { $0.album == albumName }) {
               
                let effectiveName = song.albumArtist ?? song.artist
                let aaPid = albumArtists[effectiveName] ?? 0
                
                let syncId = SongMetadata.generatePersistentId()
                let repItem = albumRepItem[albumName] ?? 0
                try executeSQL(db, """
                    INSERT INTO album (album_pid, album, sort_album, album_artist_pid, grouping_key, album_year, keep_local, sync_id, representative_item_pid)
                    VALUES (\(albumPid), '\(escapedName)', '\(escapedName)', \(aaPid), X'\(groupingHex)', \(song.year), 1, \(syncId), \(repItem))
                """)
            }
        }
        
        // INSERT new genres only
        for (genreName, genreId) in newGenres {
            let escapedName = genreName.replacingOccurrences(of: "'", with: "''")
            let groupingKey = SongMetadata.generateGroupingKey(genreName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let repItem = genreRepItem[genreName] ?? 0
            try executeSQL(db, """
                INSERT INTO genre (genre_id, genre, grouping_key, representative_item_pid)
                VALUES (\(genreId), '\(escapedName)', X'\(groupingHex)', \(repItem))
            """)
        }
        
        // FIX EXISTING RECORDS - Update sync_id and keep_local for all albums/artists that don't have it
        print("[MediaLibraryBuilder] Fixing existing records without sync_id...")
        
        // Update all albums that have sync_id = 0
        try executeSQL(db, """
            UPDATE album SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        // Update all album_artists that have sync_id = 0
        try executeSQL(db, """
            UPDATE album_artist SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        // Update all item_artists that have sync_id = 0
        try executeSQL(db, """
            UPDATE item_artist SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        print("[MediaLibraryBuilder] Merged \(songs.count) new songs, \(collectedArtworkInfo.count) with artwork")
        return (insertedPids, collectedArtworkInfo)
    }
    
    // MARK: - Schema Creation
    
    private static func createSchema(db: OpaquePointer?) throws {
        let schema = """
        CREATE TABLE _MLDatabaseProperties (key TEXT PRIMARY KEY, value TEXT);
        
        CREATE TABLE account (dsid INTEGER PRIMARY KEY, apple_id TEXT NOT NULL DEFAULT '', alt_dsid TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE album (album_pid INTEGER PRIMARY KEY, album TEXT NOT NULL DEFAULT '', sort_album TEXT, album_artist_pid INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, user_rating INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, all_compilations INTEGER NOT NULL DEFAULT 0, feed_url TEXT, season_number INTEGER NOT NULL DEFAULT 0, album_year INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, contains_classical_work INTEGER NOT NULL DEFAULT 0, date_played_local INTEGER NOT NULL DEFAULT 0, user_rating_is_derived INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, classical_experience_available INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, cloud_library_id TEXT NOT NULL DEFAULT '', liked_state_changed_date INTEGER NOT NULL DEFAULT 0, editorial_notes TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE album_artist (album_artist_pid INTEGER PRIMARY KEY, album_artist TEXT NOT NULL DEFAULT '', sort_album_artist TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, sync_id INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', classical_experience_available INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0, sort_order_section INTEGER NOT NULL DEFAULT 0, name_order INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE artwork (artwork_token TEXT NOT NULL DEFAULT '', artwork_source_type INTEGER NOT NULL DEFAULT 0, relative_path TEXT NOT NULL DEFAULT '', artwork_type INTEGER NOT NULL DEFAULT 0, interest_data BLOB, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (artwork_token, artwork_source_type, artwork_variant_type));
        
        CREATE TABLE artwork_token (artwork_token TEXT NOT NULL DEFAULT '', artwork_source_type INTEGER NOT NULL DEFAULT 0, artwork_type INTEGER NOT NULL DEFAULT 0, entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type));
        
        CREATE TABLE base_location (base_location_id INTEGER PRIMARY KEY, path TEXT NOT NULL);
        
        CREATE TABLE best_artwork_token (entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, artwork_type INTEGER NOT NULL DEFAULT 0, available_artwork_token TEXT NOT NULL DEFAULT '', fetchable_artwork_token TEXT NOT NULL DEFAULT '', fetchable_artwork_source_type INTEGER NOT NULL DEFAULT 0, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (entity_pid, entity_type, artwork_type, artwork_variant_type));
        
        CREATE TABLE booklet (booklet_pid INTEGER PRIMARY KEY, item_pid INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '', store_item_id INTEGER NOT NULL DEFAULT 0, redownload_params TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE category (category_id INTEGER PRIMARY KEY, category TEXT NOT NULL UNIQUE);
        
        CREATE TABLE chapter (item_pid INTEGER PRIMARY KEY, chapter_data BLOB);
        
        CREATE TABLE cloud_kvs (key TEXT PRIMARY KEY, play_count_user INTEGER NOT NULL DEFAULT 0, has_been_played INTEGER NOT NULL DEFAULT 0, bookmark_time_ms REAL NOT NULL DEFAULT 0, bookmark_sync_timestamp INTEGER NOT NULL DEFAULT 0, bookmark_sync_revision INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE composer (composer_pid INTEGER PRIMARY KEY, composer TEXT NOT NULL DEFAULT '', sort_composer TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE container (container_pid INTEGER PRIMARY KEY, distinguished_kind INTEGER NOT NULL DEFAULT 0, date_created INTEGER NOT NULL DEFAULT 0, date_modified INTEGER NOT NULL DEFAULT 0, date_played INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '', name_order INTEGER NOT NULL DEFAULT 0, is_owner INTEGER NOT NULL DEFAULT 1, is_editable INTEGER NOT NULL DEFAULT 0, parent_pid INTEGER NOT NULL DEFAULT 0, contained_media_type INTEGER NOT NULL DEFAULT 0, workout_template_id INTEGER NOT NULL DEFAULT 0, is_hidden INTEGER NOT NULL DEFAULT 0, is_ignorable_itunes_playlist INTEGER NOT NULL DEFAULT 0, description TEXT, play_count_user INTEGER NOT NULL DEFAULT 0, play_count_recent INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, smart_evaluation_order INTEGER NOT NULL DEFAULT 0, smart_is_folder INTEGER NOT NULL DEFAULT 0, smart_is_dynamic INTEGER NOT NULL DEFAULT 0, smart_is_filtered INTEGER NOT NULL DEFAULT 0, smart_is_genius INTEGER NOT NULL DEFAULT 0, smart_enabled_only INTEGER NOT NULL DEFAULT 0, smart_is_limited INTEGER NOT NULL DEFAULT 0, smart_limit_kind INTEGER NOT NULL DEFAULT 0, smart_limit_order INTEGER NOT NULL DEFAULT 0, smart_limit_value INTEGER NOT NULL DEFAULT 0, smart_reverse_limit_order INTEGER NOT NULL DEFAULT 0, smart_criteria BLOB, play_order INTEGER NOT NULL DEFAULT 0, is_reversed INTEGER NOT NULL DEFAULT 0, album_field_order INTEGER NOT NULL DEFAULT 0, repeat_mode INTEGER NOT NULL DEFAULT 0, shuffle_items INTEGER NOT NULL DEFAULT 0, has_been_shuffled INTEGER NOT NULL DEFAULT 0, filepath TEXT NOT NULL DEFAULT '', is_saveable INTEGER NOT NULL DEFAULT 0, is_src_remote INTEGER NOT NULL DEFAULT 0, is_ignored_syncing INTEGER NOT NULL DEFAULT 0, container_type INTEGER NOT NULL DEFAULT 0, is_container_type_active_target INTEGER NOT NULL DEFAULT 0, orig_date_modified INTEGER NOT NULL DEFAULT 0, store_cloud_id INTEGER NOT NULL DEFAULT 0, has_cloud_play_order INTEGER NOT NULL DEFAULT 0, cloud_global_id TEXT NOT NULL DEFAULT '', cloud_share_url TEXT NOT NULL DEFAULT '', cloud_is_public INTEGER NOT NULL DEFAULT 0, cloud_is_visible INTEGER NOT NULL DEFAULT 0, cloud_is_subscribed INTEGER NOT NULL DEFAULT 0, cloud_is_curator_playlist INTEGER NOT NULL DEFAULT 0, cloud_author_store_id INTEGER NOT NULL DEFAULT 0, cloud_author_display_name TEXT NOT NULL DEFAULT '', cloud_author_store_url TEXT NOT NULL DEFAULT '', cloud_min_refresh_interval INTEGER NOT NULL DEFAULT 0, cloud_last_update_time INTEGER NOT NULL DEFAULT 0, cloud_user_count INTEGER NOT NULL DEFAULT 0, cloud_global_play_count INTEGER NOT NULL DEFAULT 0, cloud_global_like_count INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, external_vendor_identifier TEXT NOT NULL DEFAULT '', external_vendor_display_name TEXT NOT NULL DEFAULT '', external_vendor_container_tag TEXT NOT NULL DEFAULT '', is_external_vendor_playlist INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, cloud_is_sharing_disabled INTEGER NOT NULL DEFAULT 0, cloud_version_hash TEXT NOT NULL DEFAULT '', date_played_local INTEGER NOT NULL DEFAULT 0, cloud_author_handle TEXT NOT NULL DEFAULT '', cloud_universal_library_id TEXT NOT NULL DEFAULT '', should_display_index INTEGER NOT NULL DEFAULT 0, date_downloaded INTEGER NOT NULL DEFAULT 0, category_type_mask INTEGER NOT NULL DEFAULT 0, grouping_sort_key TEXT NOT NULL DEFAULT '', traits INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0, is_collaborative INTEGER NOT NULL DEFAULT 0, collaborator_invite_options INTEGER NOT NULL DEFAULT 0, collaborator_permissions INTEGER NOT NULL DEFAULT 0, collaboration_invitation_link TEXT NOT NULL DEFAULT '', cover_artwork_recipe TEXT NOT NULL DEFAULT '', collaboration_invitation_url_expiration_date INTEGER NOT NULL DEFAULT 0, collaboration_join_request_pending INTEGER NOT NULL DEFAULT 0, collaborator_status INTEGER NOT NULL DEFAULT 0, edit_session_id TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE container_author (container_author_pid INTEGER PRIMARY KEY, container_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, role INTEGER NOT NULL DEFAULT 0, is_pending INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, UNIQUE (container_pid, person_pid));
        
        CREATE TABLE container_item (container_item_pid INTEGER PRIMARY KEY, container_pid INTEGER NOT NULL DEFAULT 0, item_pid INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, uuid TEXT NOT NULL DEFAULT '', position_uuid TEXT NOT NULL DEFAULT '', occurrence_id TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE container_item_media_type (container_pid INTEGER PRIMARY KEY, media_type INTEGER NOT NULL DEFAULT 0, count INTEGER NOT NULL DEFAULT 0, UNIQUE (container_pid, media_type));
        
        CREATE TABLE container_item_person (container_item_person_pid INTEGER PRIMARY KEY, container_item_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, UNIQUE (container_item_pid, person_pid));
        
        CREATE TABLE container_item_reaction (container_item_reaction_pid INTEGER PRIMARY KEY, container_item_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, reaction TEXT NOT NULL DEFAULT '', date INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE container_seed (container_pid INTEGER PRIMARY KEY, item_pid INTEGER NOT NULL DEFAULT 0, seed_order INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE db_info (db_pid INTEGER PRIMARY KEY, primary_container_pid INTEGER, media_folder_url TEXT, audio_language INTEGER, subtitle_language INTEGER, genius_cuid TEXT, bib BLOB, rib BLOB);
        
        CREATE TABLE entity_changes (class INTEGER NOT NULL, entity_pid INTEGER NOT NULL, source_pid INTEGER NOT NULL, change_type INTEGER NOT NULL, changes TEXT NOT NULL DEFAULT '', UNIQUE (class, entity_pid, source_pid, change_type));
        
        CREATE TABLE entity_revision (revision INTEGER PRIMARY KEY, entity_pid INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0, class INTEGER NOT NULL DEFAULT 0, revision_type INTEGER NOT NULL DEFAULT 0, UNIQUE (entity_pid, class, revision_type));
        
        CREATE TABLE genius_config (id INTEGER PRIMARY KEY, version INTEGER UNIQUE, default_num_results INTEGER NOT NULL DEFAULT 0, min_num_results INTEGER NOT NULL DEFAULT 0, data BLOB);
        
        CREATE TABLE genius_metadata (genius_id INTEGER PRIMARY KEY, revision_level INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL DEFAULT 0, checksum INTEGER NOT NULL DEFAULT 0, data BLOB);
        
        CREATE TABLE genius_similarities (genius_id INTEGER PRIMARY KEY, data BLOB);
        
        CREATE TABLE genre (genre_id INTEGER PRIMARY KEY, genre TEXT NOT NULL DEFAULT '', grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item (item_pid INTEGER PRIMARY KEY, media_type INTEGER NOT NULL DEFAULT 0, title_order INTEGER NOT NULL DEFAULT 0, title_order_section INTEGER NOT NULL DEFAULT 0, item_artist_pid INTEGER NOT NULL DEFAULT 0, item_artist_order INTEGER NOT NULL DEFAULT 0, item_artist_order_section INTEGER NOT NULL DEFAULT 0, series_name_order INTEGER NOT NULL DEFAULT 0, series_name_order_section INTEGER NOT NULL DEFAULT 0, album_pid INTEGER NOT NULL DEFAULT 0, album_order INTEGER NOT NULL DEFAULT 0, album_order_section INTEGER NOT NULL DEFAULT 0, album_artist_pid INTEGER NOT NULL DEFAULT 0, album_artist_order INTEGER NOT NULL DEFAULT 0, album_artist_order_section INTEGER NOT NULL DEFAULT 0, composer_pid INTEGER NOT NULL DEFAULT 0, composer_order INTEGER NOT NULL DEFAULT 0, composer_order_section INTEGER NOT NULL DEFAULT 0, genre_id INTEGER NOT NULL DEFAULT 0, genre_order INTEGER NOT NULL DEFAULT 0, genre_order_section INTEGER NOT NULL DEFAULT 0, disc_number INTEGER NOT NULL DEFAULT 0, track_number INTEGER NOT NULL DEFAULT 0, episode_sort_id INTEGER NOT NULL DEFAULT 0, base_location_id INTEGER NOT NULL DEFAULT 0, remote_location_id INTEGER NOT NULL DEFAULT 0, exclude_from_shuffle INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, in_my_library INTEGER NOT NULL DEFAULT 0, is_compilation INTEGER NOT NULL DEFAULT 0, date_added INTEGER NOT NULL DEFAULT 0, show_composer INTEGER NOT NULL DEFAULT 0, is_music_show INTEGER NOT NULL DEFAULT 0, date_downloaded INTEGER NOT NULL DEFAULT 0, download_source_container_pid INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_artist (item_artist_pid INTEGER PRIMARY KEY, item_artist TEXT NOT NULL DEFAULT '', sort_item_artist TEXT, series_name TEXT NOT NULL DEFAULT '', sort_series_name TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, sync_id INTEGER NOT NULL DEFAULT 0, classical_experience_available INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_extra (item_pid INTEGER PRIMARY KEY, title TEXT NOT NULL DEFAULT '', sort_title TEXT, disc_count INTEGER NOT NULL DEFAULT 0, track_count INTEGER NOT NULL DEFAULT 0, total_time_ms REAL NOT NULL DEFAULT 0, year INTEGER NOT NULL DEFAULT 0, location TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0, integrity BLOB, is_audible_audio_book INTEGER NOT NULL DEFAULT 0, date_modified INTEGER NOT NULL DEFAULT 0, media_kind INTEGER NOT NULL DEFAULT 0, content_rating INTEGER NOT NULL DEFAULT 0, content_rating_level INTEGER NOT NULL DEFAULT 0, is_user_disabled INTEGER NOT NULL DEFAULT 0, bpm INTEGER NOT NULL DEFAULT 0, genius_id INTEGER NOT NULL DEFAULT 0, comment TEXT, grouping TEXT, description TEXT, description_long TEXT, collection_description TEXT, copyright TEXT, pending_genius_checksum INTEGER NOT NULL DEFAULT 0, category_id INTEGER NOT NULL DEFAULT 0, location_kind_id INTEGER NOT NULL DEFAULT 0, version TEXT NOT NULL DEFAULT '', display_version TEXT NOT NULL DEFAULT '', classical_work TEXT NOT NULL DEFAULT '', classical_movement TEXT NOT NULL DEFAULT '', classical_movement_count INTEGER NOT NULL DEFAULT 0, classical_movement_number INTEGER NOT NULL DEFAULT 0, is_preorder INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_kvs (item_pid INTEGER PRIMARY KEY, key TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE item_playback (item_pid INTEGER PRIMARY KEY, audio_format INTEGER NOT NULL DEFAULT 0, bit_rate INTEGER NOT NULL DEFAULT 0, codec_type INTEGER NOT NULL DEFAULT 0, codec_subtype INTEGER NOT NULL DEFAULT 0, data_kind INTEGER NOT NULL DEFAULT 0, data_url TEXT, duration INTEGER NOT NULL DEFAULT 0, eq_preset TEXT, format TEXT, gapless_heuristic_info INTEGER NOT NULL DEFAULT 0, gapless_encoding_delay INTEGER NOT NULL DEFAULT 0, gapless_encoding_drain INTEGER NOT NULL DEFAULT 0, gapless_last_frame_resynch INTEGER NOT NULL DEFAULT 0, has_video INTEGER NOT NULL DEFAULT 0, relative_volume INTEGER, sample_rate REAL NOT NULL DEFAULT 0, start_time_ms REAL NOT NULL DEFAULT 0, stop_time_ms REAL NOT NULL DEFAULT 0, volume_normalization_energy INTEGER NOT NULL DEFAULT 0, progression_direction INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_search (item_pid INTEGER PRIMARY KEY, search_title INTEGER NOT NULL DEFAULT 0, search_album INTEGER NOT NULL DEFAULT 0, search_artist INTEGER NOT NULL DEFAULT 0, search_composer INTEGER NOT NULL DEFAULT 0, search_album_artist INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_stats (item_pid INTEGER PRIMARY KEY, user_rating INTEGER NOT NULL DEFAULT 0, needs_restore INTEGER NOT NULL DEFAULT 0, download_identifier TEXT, play_count_user INTEGER NOT NULL DEFAULT 0, play_count_recent INTEGER NOT NULL DEFAULT 0, has_been_played INTEGER NOT NULL DEFAULT 0, date_played INTEGER NOT NULL DEFAULT 0, date_skipped INTEGER NOT NULL DEFAULT 0, date_accessed INTEGER NOT NULL DEFAULT 0, is_alarm INTEGER NOT NULL DEFAULT 0, skip_count_user INTEGER NOT NULL DEFAULT 0, skip_count_recent INTEGER NOT NULL DEFAULT 0, remember_bookmark INTEGER NOT NULL DEFAULT 0, bookmark_time_ms REAL NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0, chosen_by_auto_fill INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, liked_state_changed INTEGER NOT NULL DEFAULT 0, user_rating_is_derived INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE item_store (item_pid INTEGER PRIMARY KEY, store_item_id INTEGER NOT NULL DEFAULT 0, store_composer_id INTEGER NOT NULL DEFAULT 0, store_genre_id INTEGER NOT NULL DEFAULT 0, store_playlist_id INTEGER NOT NULL DEFAULT 0, storefront_id INTEGER NOT NULL DEFAULT 0, purchase_history_id INTEGER NOT NULL DEFAULT 0, purchase_history_token INTEGER NOT NULL DEFAULT 0, purchase_history_redownload_params TEXT, store_saga_id INTEGER NOT NULL DEFAULT 0, match_redownload_params TEXT, cloud_status INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, home_sharing_id INTEGER NOT NULL DEFAULT 0, is_ota_purchased INTEGER NOT NULL DEFAULT 0, store_kind INTEGER NOT NULL DEFAULT 0, account_id INTEGER NOT NULL DEFAULT 0, downloader_account_id INTEGER NOT NULL DEFAULT 0, family_account_id INTEGER NOT NULL DEFAULT 0, is_protected INTEGER NOT NULL DEFAULT 0, key_versions INTEGER NOT NULL DEFAULT 0, key_platform_id INTEGER NOT NULL DEFAULT 0, key_id INTEGER NOT NULL DEFAULT 0, key_id_2 INTEGER NOT NULL DEFAULT 0, date_purchased INTEGER NOT NULL DEFAULT 0, date_released INTEGER NOT NULL DEFAULT 0, external_guid TEXT, feed_url TEXT, artwork_url TEXT, store_xid TEXT, store_flavor TEXT, store_matched_status INTEGER NOT NULL DEFAULT 0, store_redownloaded_status INTEGER NOT NULL DEFAULT 0, extras_url TEXT NOT NULL DEFAULT '', vpp_is_licensed INTEGER NOT NULL DEFAULT 0, vpp_org_id INTEGER NOT NULL DEFAULT 0, vpp_org_name TEXT NOT NULL DEFAULT '', sync_redownload_params TEXT NOT NULL DEFAULT '', needs_reporting INTEGER NOT NULL DEFAULT 0, subscription_store_item_id INTEGER NOT NULL DEFAULT 0, playback_endpoint_type INTEGER NOT NULL DEFAULT 0, is_mastered_for_itunes INTEGER NOT NULL DEFAULT 0, radio_station_id TEXT NOT NULL DEFAULT '', advertisement_unique_id TEXT NOT NULL DEFAULT '', advertisement_type INTEGER NOT NULL DEFAULT 0, is_artist_uploaded_content INTEGER NOT NULL DEFAULT 0, cloud_asset_available INTEGER NOT NULL DEFAULT 0, is_subscription INTEGER NOT NULL DEFAULT 0, sync_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_album_id TEXT NOT NULL DEFAULT '', cloud_playback_endpoint_type INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', reporting_store_item_id INTEGER NOT NULL DEFAULT 0, asset_store_item_id INTEGER NOT NULL DEFAULT 0, extended_playback_attribute INTEGER NOT NULL DEFAULT 0, extended_lyrics_attribute INTEGER NOT NULL DEFAULT 0, store_canonical_id TEXT NOT NULL DEFAULT '', tv_show_canonical_id TEXT NOT NULL DEFAULT '', tv_season_canonical_id TEXT NOT NULL DEFAULT '', immersive_deep_link_url TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE item_video (item_pid INTEGER PRIMARY KEY, video_quality INTEGER NOT NULL DEFAULT 0, is_rental INTEGER NOT NULL DEFAULT 0, has_chapter_data INTEGER NOT NULL DEFAULT 0, season_number INTEGER NOT NULL DEFAULT 0, episode_id TEXT NOT NULL DEFAULT '', network_name TEXT NOT NULL DEFAULT '', extended_content_rating TEXT NOT NULL DEFAULT '', movie_info TEXT NOT NULL DEFAULT '', has_alternate_audio INTEGER NOT NULL DEFAULT 0, has_subtitles INTEGER NOT NULL DEFAULT 0, audio_language INTEGER NOT NULL DEFAULT 0, audio_track_index INTEGER NOT NULL DEFAULT 0, audio_track_id INTEGER NOT NULL DEFAULT 0, subtitle_language INTEGER NOT NULL DEFAULT 0, subtitle_track_index INTEGER NOT NULL DEFAULT 0, rental_duration INTEGER NOT NULL DEFAULT 0, rental_playback_duration INTEGER NOT NULL DEFAULT 0, rental_playback_date_started INTEGER NOT NULL DEFAULT 0, rental_date_started INTEGER NOT NULL DEFAULT 0, is_demo INTEGER NOT NULL DEFAULT 0, has_hls INTEGER NOT NULL DEFAULT 0, audio_track_locale TEXT NOT NULL DEFAULT '', show_sort_type INTEGER NOT NULL DEFAULT 0, episode_type INTEGER NOT NULL DEFAULT 0, episode_type_display_name TEXT NOT NULL DEFAULT '', episode_sub_sort_order INTEGER NOT NULL DEFAULT 0, hls_offline_playback_keys BLOB, is_premium INTEGER NOT NULL DEFAULT 0, color_capability INTEGER NOT NULL DEFAULT 0, hls_color_capability INTEGER NOT NULL DEFAULT 0, hls_video_quality INTEGER NOT NULL DEFAULT 0, hls_playlist_url TEXT NOT NULL DEFAULT '', audio_capability INTEGER NOT NULL DEFAULT 0, hls_audio_capability INTEGER NOT NULL DEFAULT 0, hls_asset_traits INTEGER NOT NULL DEFAULT 0, hls_key_server_url TEXT NOT NULL DEFAULT '', hls_key_cert_url TEXT NOT NULL DEFAULT '', hls_key_server_protocol TEXT NOT NULL DEFAULT '');
        
        CREATE TABLE library_pins (pin_pid INTEGER PRIMARY KEY, entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, default_action INTEGER NOT NULL DEFAULT 1, position_uuid TEXT, UNIQUE (entity_pid, entity_type));
        
        CREATE TABLE library_property (property_pid INTEGER PRIMARY KEY, source_id INTEGER, key TEXT, value TEXT, UNIQUE (source_id, key));
        
        CREATE TABLE lyrics (item_pid INTEGER PRIMARY KEY, checksum INTEGER NOT NULL DEFAULT 0, pending_checksum INTEGER NOT NULL DEFAULT 0, lyrics TEXT NOT NULL DEFAULT '', store_lyrics_available INTEGER NOT NULL DEFAULT 0, time_synced_lyrics_available INTEGER NOT NULL DEFAULT 0, downloaded_catalog_lyrics_available INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE person (person_pid INTEGER PRIMARY KEY, cloud_id TEXT NOT NULL DEFAULT '', handle TEXT NOT NULL DEFAULT '', name TEXT NOT NULL DEFAULT '', image_url TEXT NOT NULL DEFAULT '', image_token TEXT NOT NULL DEFAULT '', lightweight_profile INTEGER NOT NULL DEFAULT 0);
        
        CREATE TABLE sort_map (name TEXT NOT NULL UNIQUE, name_order INTEGER UNIQUE, name_section INTEGER, sort_key BLOB NOT NULL DEFAULT x'');
        
        CREATE TABLE sort_map_no_uniques (name TEXT, name_order INTEGER, name_section INTEGER, sort_key BLOB);
        
        CREATE TABLE source (source_pid INTEGER PRIMARY KEY, source_name TEXT, last_sync_date INTEGER NOT NULL DEFAULT 0, last_sync_revision INTEGER NOT NULL DEFAULT 0);
        """
        
        let statements = schema.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        for statement in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement + ";", nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                Logger.shared.log("[MediaLibraryBuilder] Schema error: \(error)")
                Logger.shared.log("[MediaLibraryBuilder] Statement: \(statement)")
                throw MediaLibraryError.schemaCreationFailed(error)
            }
        }
        

        
        // Create indexes - CRITICAL for MPMediaLibrary to function
        
        try createIndexes(db: db)
    }
    
    // MARK: - Index Creation
    
    private static func createIndexes(db: OpaquePointer?) throws {
        let indexes = """
        -- CRITICAL: Composite indexes from documentation required for browsing
        -- IMPORTANTE: Indexes compuestos que pide la docu pa poder navegar
        CREATE INDEX IF NOT EXISTS ItemArtist ON item (item_artist_order ASC, item_artist_pid ASC);
        CREATE INDEX IF NOT EXISTS ItemAlbum ON item (album_order ASC, album_pid ASC, disc_number ASC, track_number ASC);
        CREATE INDEX IF NOT EXISTS ItemTitle ON item (title_order ASC, item_artist_order ASC);
        CREATE INDEX IF NOT EXISTS ItemKeepLocal ON item (keep_local ASC);
        
        -- sort_map indexes for fast lookups
        -- Indexes pal sort_map pa buscar en fa
        CREATE INDEX IF NOT EXISTS SortMapSortName ON sort_map (name ASC);
        CREATE INDEX IF NOT EXISTS SortMapSortNameOrder ON sort_map (name_order ASC);
        
        -- Additional indexes on foreign keys and common lookups
        -- Mas indexes pa foreign keys y lookups comunes
        CREATE INDEX IF NOT EXISTS idx_item_album_pid ON item (album_pid);
        CREATE INDEX IF NOT EXISTS idx_item_artist_pid ON item (item_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_item_album_artist_pid ON item (album_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_item_genre_id ON item (genre_id);
        CREATE INDEX IF NOT EXISTS idx_item_base_location ON item (base_location_id);
        CREATE INDEX IF NOT EXISTS idx_item_media_type ON item (media_type);
        CREATE INDEX IF NOT EXISTS idx_item_title_order ON item (title_order);
        CREATE INDEX IF NOT EXISTS idx_item_date_added ON item (date_added);
        CREATE INDEX IF NOT EXISTS idx_item_in_my_library ON item (in_my_library);
        
        CREATE INDEX IF NOT EXISTS idx_item_extra_item_pid ON item_extra (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_playback_item_pid ON item_playback (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_store_item_pid ON item_store (item_pid);
        CREATE INDEX IF NOT EXISTS idx_item_store_sync_id ON item_store (sync_id);
        
        CREATE INDEX IF NOT EXISTS idx_item_stats_item_pid ON item_stats (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_search_item_pid ON item_search (item_pid);
        CREATE INDEX IF NOT EXISTS idx_item_search_title ON item_search (search_title);
        CREATE INDEX IF NOT EXISTS idx_item_search_artist ON item_search (search_artist);
        CREATE INDEX IF NOT EXISTS idx_item_search_album ON item_search (search_album);
        
        CREATE INDEX IF NOT EXISTS idx_album_album_artist_pid ON album (album_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_album_grouping_key ON album (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_item_artist_grouping_key ON item_artist (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_album_artist_grouping_key ON album_artist (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_genre_grouping_key ON genre (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_container_item_container_pid ON container_item (container_pid);
        CREATE INDEX IF NOT EXISTS idx_container_item_item_pid ON container_item (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_artwork_token_entity ON artwork_token (entity_pid, entity_type);
        
        CREATE INDEX IF NOT EXISTS idx_best_artwork_entity ON best_artwork_token (entity_pid, entity_type);
        """
        
        let statements = indexes.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        for statement in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement + ";", nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                Logger.shared.log("[MediaLibraryBuilder] Index warning: \(error)")
                // Don't throw - indexes are optional, continue
            }
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Indexes created")
        
        // Create critical trigger
        try createTriggers(db: db)
    }
    
    // MARK: - Trigger Creation
    
    private static func createTriggers(db: OpaquePointer?) throws {
        // This trigger is CRITICAL - it sets in_my_library when item_store is inserted
        let triggerSQL = """
        CREATE TRIGGER IF NOT EXISTS on_insert_item_setInMyLibraryColumn 
        AFTER INSERT ON item_store 
        BEGIN 
          UPDATE item SET in_my_library = (
            CASE WHEN 
              new.home_sharing_id OR 
              (new.store_saga_id AND new.cloud_in_my_library) OR 
              new.purchase_history_id OR 
              (new.sync_id AND new.sync_in_my_library) OR
              new.is_ota_purchased 
            THEN 1 ELSE 0 END
          ) WHERE item_pid = new.item_pid; 
        END
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, triggerSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            Logger.shared.log("[MediaLibraryBuilder] Trigger warning: \(error)")
            // Don't throw - triggers are optional, continue
        } else {
            Logger.shared.log("[MediaLibraryBuilder] Triggers created")
        }
    }
    
    // MARK: - Base Data
    
    private static func insertBaseData(db: OpaquePointer?) throws {
        // Base location - use relative path
        let baseDataSQL = """
        INSERT INTO base_location (base_location_id, path) VALUES (0, '');
        INSERT INTO base_location (base_location_id, path) VALUES (3840, 'iTunes_Control/Music/F00');
        INSERT INTO base_location (base_location_id, path) VALUES (3900, 'iTunes_Control/Ringtones');
        INSERT INTO db_info (db_pid) VALUES (1);
        INSERT INTO genius_config (id, version, default_num_results, min_num_results) VALUES (1, 1, 25, 10);
        INSERT INTO container_seed (container_pid, item_pid, seed_order) VALUES (0, 0, 0);
        INSERT INTO _MLDatabaseProperties (key, value) VALUES ('OrderingLanguage', 'en-US');
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, baseDataSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            throw MediaLibraryError.insertFailed(error)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Base data inserted")
    }
    
        /// Format: Hex(filename + "iTunes_Control/Music/F00")
    static func generateRingtoneIntegrity(filename: String) -> String {
        // Ringtones usually reside in iTunes_Control/Ringtones
        // Match the same logic as songs for consistency
        let rawString = "iTunes_Control/Ringtones/\(filename)"
        guard let data = rawString.data(using: .utf8) else { return "" }
        return data.map { String(format: "%02X", $0) }.joined()
    }

    private static func executeSQL(_ db: OpaquePointer?, _ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            Logger.shared.log("[MediaLibraryBuilder] SQL Error: \(error)")
            Logger.shared.log("[MediaLibraryBuilder] SQL: \(sql)")
            throw MediaLibraryError.insertFailed(error)
        }
    }
    
    /// Insert a string into sort_map and return its name_order
    /// This is CRITICAL for Albums/Artists to appear in list views
    private static func insertSortMap(db: OpaquePointer?, name: String) -> Int64 {
        let escapedName = name.replacingOccurrences(of: "'", with: "''")
        
        // Check if already exists
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT name_order FROM sort_map WHERE name = '\(escapedName)'", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let existingOrder = sqlite3_column_int64(stmt, 0)
                sqlite3_finalize(stmt)
                return existingOrder
            }
        }
        sqlite3_finalize(stmt)
        
        // Get max name_order
        var maxOrder: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT MAX(name_order) FROM sort_map", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxOrder = sqlite3_column_int64(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        
        let nameOrder = maxOrder + 1
        
        // Calculate section (first letter: A=1, B=2, etc., non-alpha=27)
        var nameSection = 27
        if let firstChar = name.uppercased().first {
            let charValue = Int(firstChar.asciiValue ?? 0)
            if charValue >= 65 && charValue <= 90 { // A-Z
                nameSection = charValue - 64 // A=1, B=2, etc.
            }
        }
        
        // Generate sort key (grouping key for sorting)
        let sortKey = SongMetadata.generateGroupingKey(name)
        let sortKeyHex = sortKey.map { String(format: "%02x", $0) }.joined()
        
        // Insert into sort_map
        var errMsg: UnsafeMutablePointer<CChar>?
        let sql = "INSERT OR IGNORE INTO sort_map (name, name_order, name_section, sort_key) VALUES ('\(escapedName)', \(nameOrder), \(nameSection), X'\(sortKeyHex)')"
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            Logger.shared.log("[MediaLibraryBuilder] sort_map insert error: \(error)")
        }
        
        return nameOrder
    }
    
    // MARK: - Playlist Creation
    
    /// Creates a playlist and adds songs to it
    /// - Parameters:
    ///   - db: Database handle
    ///   - playlistName: Name of the playlist
    ///   - songPids: Array of item_pid values for songs to add
    static func createPlaylist(db: OpaquePointer?, playlistName: String, songPids: [Int64]) throws {
        let containerPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        let now = Int64(Date().timeIntervalSince1970)
        
        // Insert playlist name into sort_map
        let nameOrder = insertSortMap(db: db, name: playlistName)
        
        // Insert into container table
        let containerSQL = """
        INSERT INTO container (
            container_pid, name, name_order, date_created, date_modified,
            contained_media_type, is_owner, is_editable, distinguished_kind
        ) VALUES (?, ?, ?, ?, ?, 8, 1, 1, 0)
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, containerSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            sqlite3_bind_text(stmt, 2, playlistName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(stmt, 3, Int64(nameOrder))
            sqlite3_bind_int64(stmt, 4, now)
            sqlite3_bind_int64(stmt, 5, now)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(stmt)
                throw MediaLibraryError.insertFailed("container: \(error)")
            }
        }
        sqlite3_finalize(stmt)
        
        Logger.shared.log("[MediaLibraryBuilder] Created playlist '\(playlistName)' with pid: \(containerPid)")
        
        // Insert container_item entries for each song
        let itemSQL = """
        INSERT INTO container_item (
            container_item_pid, container_pid, item_pid, position, uuid
        ) VALUES (?, ?, ?, ?, ?)
        """
        
        for (index, songPid) in songPids.enumerated() {
            let containerItemPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
            let uuid = UUID().uuidString
            
            if sqlite3_prepare_v2(db, itemSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, containerItemPid)
                sqlite3_bind_int64(stmt, 2, containerPid)
                sqlite3_bind_int64(stmt, 3, songPid)
                sqlite3_bind_int64(stmt, 4, Int64(index))
                sqlite3_bind_text(stmt, 5, uuid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    let error = String(cString: sqlite3_errmsg(db))
                    Logger.shared.log("[MediaLibraryBuilder] container_item insert warning: \(error)")
                }
            }
            sqlite3_finalize(stmt)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Added \(songPids.count) songs to playlist")
    }
    
    /// Convenience to open database and extract playlists
    static func extractPlaylists(fromDbPath path: String) -> [(name: String, pid: Int64)] {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }
        return getPlaylists(db: db)
    }
    
    /// Get existing user playlists
    static func getPlaylists(db: OpaquePointer?) -> [(name: String, pid: Int64)] {
        var playlists: [(String, Int64)] = []
        let query = "SELECT name, container_pid FROM container WHERE contained_media_type = 8 AND distinguished_kind = 0 ORDER BY name"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)
                    playlists.append((name, pid))
                }
            }
        }
        sqlite3_finalize(stmt)
        return playlists
    }
    
    /// Add songs to an existing playlist
    static func addToPlaylist(db: OpaquePointer?, containerPid: Int64, songPids: [Int64]) throws {
        // Get current max position
        var maxPos: Int64 = -1
        let maxQuery = "SELECT MAX(position) FROM container_item WHERE container_pid = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, maxQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            if sqlite3_step(stmt) == SQLITE_ROW {
                // Check for NULL (empty playlist returns NULL for MAX)
                if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    maxPos = sqlite3_column_int64(stmt, 0)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        let startPos = maxPos + 1
        Logger.shared.log("[MediaLibraryBuilder] Appending \(songPids.count) songs to playlist \(containerPid) starting at pos \(startPos)")
        
        // Insert container_item entries for each song
        let itemSQL = """
        INSERT INTO container_item (
            container_item_pid, container_pid, item_pid, position, uuid
        ) VALUES (?, ?, ?, ?, ?)
        """
        
        for (index, songPid) in songPids.enumerated() {
            let containerItemPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
            let uuid = UUID().uuidString
            let position = startPos + Int64(index)
            
            if sqlite3_prepare_v2(db, itemSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, containerItemPid)
                sqlite3_bind_int64(stmt, 2, containerPid)
                sqlite3_bind_int64(stmt, 3, songPid)
                sqlite3_bind_int64(stmt, 4, position)
                sqlite3_bind_text(stmt, 5, uuid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    let error = String(cString: sqlite3_errmsg(db))
                    Logger.shared.log("[MediaLibraryBuilder] container_item insert warning: \(error)")
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Ringtone Insertion
    
    /// Insert ringtones into the database
    @discardableResult
    static func insertRingtones(db: OpaquePointer?, ringtones: [SongMetadata]) throws -> [Int64] {
        let now = Int(Date().timeIntervalSince1970)
        var insertedPids: [Int64] = []
        
        // Ensure base_location 3900 exists
        let baseLocSQL = "INSERT OR IGNORE INTO base_location (base_location_id, path) VALUES (3900, 'iTunes_Control/Ringtones')"
        var baseErrMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, baseLocSQL, nil, nil, &baseErrMsg) != SQLITE_OK {
            let error = baseErrMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(baseErrMsg)
            Logger.shared.log("[MediaLibraryBuilder] Warning: Failed to insert ringtone base location: \(error)")
        }
        
        for ringtone in ringtones {
            let itemPid = SongMetadata.generatePersistentId()
            insertedPids.append(itemPid)
            
            // Generate sort orders
            let titleOrder = insertSortMap(db: db, name: ringtone.title)
            
            Logger.shared.log("[MediaLibraryBuilder] Adding Ringtone: \(ringtone.title) -> \(ringtone.remoteFilename)")
            
            // INSERT into item table (media_type 16384 for Ringtone, base_location 3900)
            try executeSQL(db, """
                INSERT INTO item (
                    item_pid, media_type, title_order, title_order_section,
                    item_artist_pid, item_artist_order, item_artist_order_section,
                    series_name_order, series_name_order_section,
                    album_pid, album_order, album_order_section,
                    album_artist_pid, album_artist_order, album_artist_order_section,
                    composer_pid, composer_order, composer_order_section,
                    genre_id, genre_order, genre_order_section,
                    disc_number, track_number, episode_sort_id,
                    base_location_id, remote_location_id,
                    exclude_from_shuffle, keep_local, keep_local_status, keep_local_status_reason, keep_local_constraints,
                    in_my_library, is_compilation, date_added, show_composer, is_music_show, date_downloaded, download_source_container_pid
                ) VALUES (
                    \(itemPid), 16384, \(titleOrder), 1,
                    0, 0, 0,
                    0, 27,
                    33003300, 0, 0,
                    0, 0, 0,
                    0, 0, 27,
                    0, 0, 0,
                    0, 0, 0,
                    3900, 0,
                    1, 1, 2, 0, 0,
                    1, 0, \(now), 0, 0, \(now), 0
                )
            """)
            
            // INSERT into item_extra
            // Note: Ringtones typically don't track duration in item_extra same way, but let's put it.
            // location_kind_id? check. 42 is file.
            // media_kind? usually 1 for music? maybe 16384 for ringtone? or just 1.
            // Testing showed that media_type in item table is the KEY.
            let escapedTitle = ringtone.title.replacingOccurrences(of: "'", with: "''")
            let escapedFilename = ringtone.remoteFilename.replacingOccurrences(of: "'", with: "''")
            try executeSQL(db, """
                INSERT INTO item_extra (
                    item_pid, title, sort_title, disc_count, track_count, total_time_ms, year,
                    location, file_size, integrity, is_audible_audio_book, date_modified,
                    media_kind, content_rating, content_rating_level, is_user_disabled, bpm, genius_id,
                    location_kind_id
                ) VALUES (
                    \(itemPid), '\(escapedTitle)', '\(escapedTitle)', 0, 0, \(ringtone.durationMs), \(ringtone.year),
                    '\(escapedFilename)', \(ringtone.fileSize), X'\(MediaLibraryBuilder.generateRingtoneIntegrity(filename: ringtone.remoteFilename))', 0, \(now),
                    16384, 0, 0, 0, 0, 0,
                    42
                )
            """)
            
            // INSERT into item_playback
            let audioFmt = audioFormatForExtension("m4r") // Always M4R
            try executeSQL(db, """
                INSERT INTO item_playback (
                    item_pid, audio_format, bit_rate, codec_type, codec_subtype, data_kind,
                    duration, has_video, relative_volume, sample_rate
                ) VALUES (
                    \(itemPid), \(audioFmt), 320, 0, 0, 0,
                    0, 0, 0, 44100.0
                )
            """)
            
            // INSERT into item_stats
            try executeSQL(db, "INSERT INTO item_stats (item_pid, date_accessed) VALUES (\(itemPid), \(now))")
            
            // INSERT into item_store
            let syncId = SongMetadata.generatePersistentId()
            try executeSQL(db, "INSERT INTO item_store (item_pid, sync_id, sync_in_my_library) VALUES (\(itemPid), \(syncId), 1)")
        }
        
        return insertedPids
    }
}

// MARK: - Errors

enum MediaLibraryError: Error, LocalizedError {
    case databaseOpenFailed
    case schemaCreationFailed(String)
    case insertFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed:
            return "Failed to open database"
        case .schemaCreationFailed(let msg):
            return "Schema creation failed: \(msg)"
        case .insertFailed(let msg):
            return "Insert failed: \(msg)"
        }
    }
}
