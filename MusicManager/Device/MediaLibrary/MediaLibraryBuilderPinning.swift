import Foundation
import SQLite3

// MARK: - Pinning
extension MediaLibraryBuilder {
    private static let pinLimitKey = "MLCloudLibraryMaxPinCount"
    private static let defaultPinLimit = 6

    enum PinEntityType {
        static let playlist = 1
        static let album = 4
        static let artist = 7
    }

    static func currentPinLimit(db: OpaquePointer?) -> Int? {
        var stmt: OpaquePointer?
        var limit: Int?
        if sqlite3_prepare_v2(db, "SELECT value FROM _MLDatabaseProperties WHERE key = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, pinLimitKey, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) {
                limit = Int(String(cString: raw))
            }
        }
        sqlite3_finalize(stmt)
        return limit
    }

    static func enablePinning(db: OpaquePointer?) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO _MLDatabaseProperties (key, value) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("pin limit: \(error)")
        }
        sqlite3_bind_text(stmt, 1, pinLimitKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, String(defaultPinLimit), -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard result == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("pin limit: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Enabled pinning with a limit of \(defaultPinLimit)")
    }

    static func pinnedPids(db: OpaquePointer?, entityType: Int) -> Set<Int64> {
        var pids: Set<Int64> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT entity_pid FROM library_pins WHERE entity_type = \(entityType)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                pids.insert(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return pids
    }

    static func pinEntity(db: OpaquePointer?, entityPid: Int64, entityType: Int) throws {
        if pinnedPids(db: db, entityType: entityType).contains(entityPid) { return }

        let limit = currentPinLimit(db: db) ?? 0
        if limit <= 0 {
            try enablePinning(db: db)
        }
        let effectiveLimit = limit > 0 ? limit : defaultPinLimit

        var stmt: OpaquePointer?
        var count = 0
        var nextPosition: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*), IFNULL(MAX(position), -1) FROM library_pins", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int64(stmt, 0))
            nextPosition = sqlite3_column_int64(stmt, 1) + 1
        }
        sqlite3_finalize(stmt)

        guard count < effectiveLimit else {
            throw MediaLibraryError.insertFailed("Pin limit reached (\(effectiveLimit)). Unpin something first.")
        }

        let pinPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        let sql = "INSERT INTO library_pins (pin_pid, entity_pid, entity_type, position, default_action, position_uuid) VALUES (?, ?, ?, ?, 2, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("pin: \(error)")
        }
        sqlite3_bind_int64(stmt, 1, pinPid)
        sqlite3_bind_int64(stmt, 2, entityPid)
        sqlite3_bind_int64(stmt, 3, Int64(entityType))
        sqlite3_bind_int64(stmt, 4, nextPosition)
        sqlite3_bind_text(stmt, 5, UUID().uuidString, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard result == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("pin: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Pinned entity \(entityPid) (type \(entityType)) at position \(nextPosition)")
    }

    static func unpinEntity(db: OpaquePointer?, entityPid: Int64, entityType: Int) throws {
        try executeSQL(db, "DELETE FROM library_pins WHERE entity_type = \(entityType) AND entity_pid = \(entityPid)")
        try executeSQL(db, """
            UPDATE library_pins SET position = (
                SELECT COUNT(*) FROM library_pins other WHERE other.position < library_pins.position
            )
        """)
        Logger.shared.log("[MediaLibraryBuilder] Unpinned entity \(entityPid) (type \(entityType))")
    }

    private static func artistPinTable(entityType: Int) -> (table: String, pidColumn: String, nameColumn: String) {
        entityType == 2 ? ("item_artist", "item_artist_pid", "item_artist") : ("album_artist", "album_artist_pid", "album_artist")
    }

    static func artistEntityPid(db: OpaquePointer?, name: String, entityType: Int) -> Int64? {
        let info = artistPinTable(entityType: entityType)
        var stmt: OpaquePointer?
        var pid: Int64?
        if sqlite3_prepare_v2(db, "SELECT \(info.pidColumn) FROM \(info.table) WHERE \(info.nameColumn) = ? COLLATE NOCASE LIMIT 1", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                pid = sqlite3_column_int64(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return pid
    }

    static func pinnedArtistNames(db: OpaquePointer?, entityType: Int) -> Set<String> {
        let info = artistPinTable(entityType: entityType)
        var names: Set<String> = []
        var stmt: OpaquePointer?
        let sql = "SELECT t.\(info.nameColumn) FROM library_pins p JOIN \(info.table) t ON t.\(info.pidColumn) = p.entity_pid WHERE p.entity_type = \(entityType)"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let raw = sqlite3_column_text(stmt, 0) {
                    names.insert(String(cString: raw).lowercased())
                }
            }
        }
        sqlite3_finalize(stmt)
        return names
    }

    static func pinArtist(db: OpaquePointer?, name: String) throws {
        let type = PinEntityType.artist
        guard let pid = artistEntityPid(db: db, name: name, entityType: type) else {
            throw MediaLibraryError.insertFailed("\"\(name)\" has no artist entry in the library, so it can't be pinned")
        }
        try pinEntity(db: db, entityPid: pid, entityType: type)
    }

    static func unpinArtist(db: OpaquePointer?, name: String) throws {
        let type = PinEntityType.artist
        guard let pid = artistEntityPid(db: db, name: name, entityType: type) else { return }
        try unpinEntity(db: db, entityPid: pid, entityType: type)
    }
}
