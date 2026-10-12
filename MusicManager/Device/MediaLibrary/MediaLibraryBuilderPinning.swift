import Foundation
import SQLite3

// MARK: - Pinning
extension MediaLibraryBuilder {
    private static let pinLimitKey = "MLCloudLibraryMaxPinCount"
    private static let defaultPinLimit = 6

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

    static func pinnedPlaylistPids(db: OpaquePointer?) -> Set<Int64> {
        var pids: Set<Int64> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT entity_pid FROM library_pins WHERE entity_type = 1", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                pids.insert(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return pids
    }

    static func pinPlaylist(db: OpaquePointer?, containerPid: Int64) throws {
        if pinnedPlaylistPids(db: db).contains(containerPid) { return }

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
        let sql = "INSERT INTO library_pins (pin_pid, entity_pid, entity_type, position, default_action, position_uuid) VALUES (?, ?, 1, ?, 2, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("pin: \(error)")
        }
        sqlite3_bind_int64(stmt, 1, pinPid)
        sqlite3_bind_int64(stmt, 2, containerPid)
        sqlite3_bind_int64(stmt, 3, nextPosition)
        sqlite3_bind_text(stmt, 4, UUID().uuidString, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard result == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("pin: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Pinned playlist \(containerPid) at position \(nextPosition)")
    }

    static func unpinPlaylist(db: OpaquePointer?, containerPid: Int64) throws {
        try executeSQL(db, "DELETE FROM library_pins WHERE entity_type = 1 AND entity_pid = \(containerPid)")
        try executeSQL(db, """
            UPDATE library_pins SET position = (
                SELECT COUNT(*) FROM library_pins other WHERE other.position < library_pins.position
            )
        """)
        Logger.shared.log("[MediaLibraryBuilder] Unpinned playlist \(containerPid)")
    }
}
