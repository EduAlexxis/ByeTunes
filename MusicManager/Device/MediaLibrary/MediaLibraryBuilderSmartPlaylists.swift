import Foundation
import SQLite3

struct SmartPlaylistLimit: Codable, Equatable {
    var isLimited: Bool = false
    var kind: Int = 2
    var order: Int = 2
    var value: Int = 25
    var reverse: Bool = false
}

struct NativeSmartPlaylist: Identifiable, Equatable {
    let pid: Int64
    let name: String
    let criteria: SmartCriteriaGroup
    let limit: SmartPlaylistLimit
    var id: Int64 { pid }
}

extension MediaLibraryBuilder {
    static func readNativeSmartPlaylists(db: OpaquePointer?) -> [NativeSmartPlaylist] {
        let sql = """
        SELECT container_pid, name, smart_criteria, smart_is_limited, smart_limit_kind,
               smart_limit_order, smart_limit_value, smart_reverse_limit_order
        FROM container
        WHERE distinguished_kind = 0 AND smart_is_dynamic = 1 AND smart_is_folder = 0
        AND smart_criteria IS NOT NULL AND length(smart_criteria) > 0
        ORDER BY name
        """
        var stmt: OpaquePointer?
        var result: [NativeSmartPlaylist] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return []
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pid = sqlite3_column_int64(stmt, 0)
            let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let length = Int(sqlite3_column_bytes(stmt, 2))
            guard length > 0, let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let data = Data(bytes: blob, count: length)
            guard let criteria = SmartCriteriaCodec.parse(data) else {
                Logger.shared.log("[SmartPlaylists] Could not parse criteria for '\(name)' (\(length) bytes)")
                continue
            }
            var limit = SmartPlaylistLimit()
            limit.isLimited = sqlite3_column_int(stmt, 3) != 0
            limit.kind = Int(sqlite3_column_int(stmt, 4))
            limit.order = Int(sqlite3_column_int(stmt, 5))
            limit.value = Int(sqlite3_column_int(stmt, 6))
            limit.reverse = sqlite3_column_int(stmt, 7) != 0
            result.append(NativeSmartPlaylist(pid: pid, name: name, criteria: criteria, limit: limit))
        }
        sqlite3_finalize(stmt)
        return result
    }

    static func createNativeSmartPlaylist(db: OpaquePointer?, containerPid: Int64, name: String, criteria: SmartCriteriaGroup, limit: SmartPlaylistLimit) throws {
        var existing: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM container WHERE container_pid = ? LIMIT 1", -1, &existing, nil) == SQLITE_OK {
            sqlite3_bind_int64(existing, 1, containerPid)
            exists = sqlite3_step(existing) == SQLITE_ROW
        }
        sqlite3_finalize(existing)
        if exists {
            throw MediaLibraryError.insertFailed("A playlist with this id already exists on the device")
        }

        let now = Int64(Date().timeIntervalSinceReferenceDate)
        let nameOrder = insertSortMap(db: db, name: name).order
        let blob = SmartCriteriaCodec.serialize(criteria)
        let sql = """
        INSERT INTO container (
            container_pid, distinguished_kind, date_created, date_modified, name, name_order,
            is_owner, is_editable, parent_pid, contained_media_type,
            smart_is_dynamic, smart_is_filtered, smart_is_limited, smart_limit_kind,
            smart_limit_order, smart_limit_value, smart_reverse_limit_order,
            smart_criteria, play_order, filepath
        ) VALUES (?, 0, ?, ?, ?, ?, 1, 1, 0, 0, 1, 1, ?, ?, ?, ?, ?, ?, 1, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("smart playlist: \(error)")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(stmt, 1, containerPid)
        sqlite3_bind_int64(stmt, 2, now)
        sqlite3_bind_int64(stmt, 3, now)
        sqlite3_bind_text(stmt, 4, name, -1, transient)
        sqlite3_bind_int64(stmt, 5, Int64(nameOrder))
        sqlite3_bind_int(stmt, 6, limit.isLimited ? 1 : 0)
        sqlite3_bind_int(stmt, 7, Int32(limit.kind))
        sqlite3_bind_int(stmt, 8, Int32(limit.order))
        sqlite3_bind_int(stmt, 9, Int32(limit.value))
        sqlite3_bind_int(stmt, 10, limit.reverse ? 1 : 0)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(stmt, 11, $0.baseAddress, Int32(blob.count), transient) }
        sqlite3_bind_text(stmt, 12, "/var/mobile/Media/iTunes_Control/iTunes/OnTheGoPlaylist_\(containerPid).plist", -1, transient)
        let rc = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("smart playlist: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Created smart playlist '\(name)' with pid: \(containerPid)")
    }
}
