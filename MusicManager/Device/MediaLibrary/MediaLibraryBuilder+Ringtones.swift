import Foundation
import SQLite3
import CommonCrypto
import UIKit

extension MediaLibraryBuilder {
    static func addRingtonesToExistingDatabase(
        existingDbData: Data,
        walData: Data? = nil,
        shmData: Data? = nil,
        ringtones: [SongMetadata]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("RingtoneDB.sqlitedb")
        
        try? FileManager.default.removeItem(at: dbPath)
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-wal"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-shm"))
        
        try existingDbData.write(to: dbPath)
        
        if let wal = walData {
            try wal.write(to: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-wal"))
        }
        if let shm = shmData {
            try shm.write(to: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-shm"))
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw MediaLibraryError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }
        
        if walData != nil {
            var errorMsg: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
            if let msg = errorMsg { sqlite3_free(msg) }
        }
        
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        
        try insertRingtones(db: db, ringtones: ringtones)
        
        Logger.shared.log("[MediaLibraryBuilder] Ringtone DB entries inserted for \(ringtones.count) ringtones")
        
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-wal"))
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneDB.sqlitedb-shm"))
        
        return dbPath
    }
    
    @discardableResult
    static func insertRingtones(db: OpaquePointer?, ringtones: [SongMetadata]) throws -> [Int64] {
        let now = Int(Date().timeIntervalSince1970)
        var insertedPids: [Int64] = []
        
        Logger.shared.log("[Ringtone-DB] insertRingtones called with \(ringtones.count) ringtones, db=\(db != nil ? "valid" : "NIL")")
        
        let baseLocSQL = "INSERT OR IGNORE INTO base_location (base_location_id, path) VALUES (3900, 'iTunes_Control/Ringtones')"
        var baseErrMsg: UnsafeMutablePointer<CChar>?
        let baseResult = sqlite3_exec(db, baseLocSQL, nil, nil, &baseErrMsg)
        if baseResult != SQLITE_OK {
            let error = baseErrMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(baseErrMsg)
            Logger.shared.log("[Ringtone-DB] WARNING: base_location insert failed: \(error) (code: \(baseResult))")
        } else {
            Logger.shared.log("[Ringtone-DB] base_location insert OK")
        }
        
        for ringtone in ringtones {
            let itemPid = SongMetadata.generatePersistentId()
            insertedPids.append(itemPid)
            Logger.shared.log("[Ringtone-DB] Inserting ringtone '\(ringtone.title)' with pid=\(itemPid)")
            
            
            let titleSortResult = insertSortMap(db: db, name: ringtone.title)
            
            Logger.shared.log("[MediaLibraryBuilder] Adding Ringtone: \(ringtone.title) -> \(ringtone.remoteFilename)")
            
            
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
                    \(itemPid), 16384, \(titleSortResult.order), \(titleSortResult.section),
                    0, 0, 0,
                    0, 26,
                    33003300, 0, 0,
                    0, 0, 0,
                    0, 0, 26,
                    0, 0, 0,
                    0, 0, 0,
                    3900, 0,
                    1, 1, 2, 0, 0,
                    1, 0, \(now), 0, 0, \(now), 0
                )
            """)
            Logger.shared.log("[Ringtone-DB] ✓ item INSERT OK for pid=\(itemPid)")
            
            
            
            
            
            
            let escapedTitle = ringtone.title.sqlEscaped
            let escapedFilename = ringtone.remoteFilename.sqlEscaped
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
            Logger.shared.log("[Ringtone-DB] ✓ item_extra INSERT OK")
            
            
            let audioFmt = audioFormatForExtension("m4r") 
            try executeSQL(db, """
                INSERT INTO item_playback (
                    item_pid, audio_format, bit_rate, codec_type, codec_subtype, data_kind,
                    duration, has_video, relative_volume, sample_rate
                ) VALUES (
                    \(itemPid), \(audioFmt), 320, 0, 0, 0,
                    0, 0, 0, 44100.0
                )
            """)
            Logger.shared.log("[Ringtone-DB] ✓ item_playback INSERT OK")
            
            
            try executeSQL(db, "INSERT INTO item_stats (item_pid, date_accessed) VALUES (\(itemPid), \(now))")
            Logger.shared.log("[Ringtone-DB] ✓ item_stats INSERT OK")
            
            
            let syncId = SongMetadata.generatePersistentId()
            try executeSQL(db, "INSERT INTO item_store (item_pid, sync_id, sync_in_my_library) VALUES (\(itemPid), \(syncId), 1)")
            Logger.shared.log("[Ringtone-DB] ✓ item_store INSERT OK")
        }
        
        Logger.shared.log("[Ringtone-DB] insertRingtones complete — \(insertedPids.count) ringtones inserted successfully")
        
        return insertedPids
    }
    
}
