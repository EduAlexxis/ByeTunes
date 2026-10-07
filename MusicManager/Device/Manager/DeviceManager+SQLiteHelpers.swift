import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func itemPid(forRemoteFilename filename: String, db: OpaquePointer?) -> Int64? {
        var stmt: OpaquePointer?
        let sql = "SELECT item_pid FROM item_extra WHERE location = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, filename, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func ensureNamedArtist(
        db: OpaquePointer?,
        tableName: String,
        idColumn: String,
        nameColumn: String,
        sortColumn: String,
        name: String,
        representativeItemPid: Int64
    ) -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if let existing = self.firstInt64Query(
            db: db,
            sql: "SELECT \(idColumn) FROM \(tableName) WHERE lower(\(nameColumn)) = lower(?) LIMIT 1",
            text: trimmed
        ) {
            return existing
        }

        let nextId = self.firstInt64Query(db: db, sql: "SELECT IFNULL(MAX(\(idColumn)), 0) + 1 FROM \(tableName)") ?? 1
        let escaped = self.escapeSQLString(trimmed)
        _ = self.sqliteExec(db, """
        INSERT INTO \(tableName) (\(idColumn), \(nameColumn), \(sortColumn), representative_item_pid)
        VALUES (\(nextId), '\(escaped)', '\(escaped)', \(representativeItemPid))
        """)
        return nextId
    }

    func ensureAlbum(
        db: OpaquePointer?,
        name: String,
        albumArtistPid: Int64,
        representativeItemPid: Int64,
        year: Int
    ) -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if let existing = self.firstInt64Query(
            db: db,
            sql: "SELECT album_pid FROM album WHERE lower(album) = lower(?) AND album_artist_pid = \(albumArtistPid) LIMIT 1",
            text: trimmed
        ) {
            return existing
        }

        let nextId = self.firstInt64Query(db: db, sql: "SELECT IFNULL(MAX(album_pid), 0) + 1 FROM album") ?? 1
        let escaped = self.escapeSQLString(trimmed)
        _ = self.sqliteExec(db, """
        INSERT INTO album (album_pid, album, sort_album, album_artist_pid, representative_item_pid, album_year)
        VALUES (\(nextId), '\(escaped)', '\(escaped)', \(albumArtistPid), \(representativeItemPid), \(max(0, year)))
        """)
        return nextId
    }

    func ensureGenre(db: OpaquePointer?, name: String, representativeItemPid: Int64) -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if let existing = self.firstInt64Query(
            db: db,
            sql: "SELECT genre_id FROM genre WHERE lower(genre) = lower(?) LIMIT 1",
            text: trimmed
        ) {
            return existing
        }

        let nextId = self.firstInt64Query(db: db, sql: "SELECT IFNULL(MAX(genre_id), 0) + 1 FROM genre") ?? 1
        let escaped = self.escapeSQLString(trimmed)
        _ = self.sqliteExec(db, """
        INSERT INTO genre (genre_id, genre, representative_item_pid)
        VALUES (\(nextId), '\(escaped)', \(representativeItemPid))
        """)
        return nextId
    }

    func firstInt64Query(db: OpaquePointer?, sql: String, text: String? = nil) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        if let text {
            sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func escapeSQLString(_ value: String) -> String {
        value.sqlEscaped
    }

    func sqliteExec(_ db: OpaquePointer?, _ sql: String) -> Bool {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if rc != SQLITE_OK {
            if let msg = errorMsg {
                Logger.shared.log("[Backup] SQLite exec warning: \(String(cString: msg))")
                sqlite3_free(errorMsg)
            }
            return false
        }
        return true
    }
    
}
