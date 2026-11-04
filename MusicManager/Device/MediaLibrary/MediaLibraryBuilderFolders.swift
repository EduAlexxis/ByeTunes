import Foundation
import SQLite3

struct PlaylistFolderInfo: Identifiable, Equatable {
    let pid: Int64
    var name: String
    var id: Int64 { pid }
}

extension MediaLibraryBuilder {
    static func readPlaylistFolders(db: OpaquePointer?) -> (folders: [PlaylistFolderInfo], parents: [Int64: Int64]) {
        var folders: [PlaylistFolderInfo] = []
        var parents: [Int64: Int64] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT container_pid, name FROM container WHERE smart_is_folder = 1 AND distinguished_kind = 0 ORDER BY name", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                folders.append(PlaylistFolderInfo(pid: sqlite3_column_int64(stmt, 0), name: name))
            }
        }
        sqlite3_finalize(stmt)
        let folderPids = Set(folders.map(\.pid))
        if sqlite3_prepare_v2(db, "SELECT container_pid, parent_pid FROM container WHERE parent_pid <> 0 AND smart_is_folder = 0", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let parent = sqlite3_column_int64(stmt, 1)
                if folderPids.contains(parent) {
                    parents[sqlite3_column_int64(stmt, 0)] = parent
                }
            }
        }
        sqlite3_finalize(stmt)
        return (folders, parents)
    }

    static func createPlaylistFolder(db: OpaquePointer?, containerPid: Int64, name: String) throws {
        let now = Int64(Date().timeIntervalSinceReferenceDate)
        let nameOrder = insertSortMap(db: db, name: name).order
        let sql = """
        INSERT INTO container (
            container_pid, distinguished_kind, date_created, date_modified, name, name_order,
            is_owner, is_editable, parent_pid, contained_media_type, smart_is_folder, play_order, filepath
        ) VALUES (?, 0, ?, ?, ?, ?, 1, 1, 0, 0, 1, 1, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("folder: \(error)")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(stmt, 1, containerPid)
        sqlite3_bind_int64(stmt, 2, now)
        sqlite3_bind_int64(stmt, 3, now)
        sqlite3_bind_text(stmt, 4, name, -1, transient)
        sqlite3_bind_int64(stmt, 5, nameOrder)
        sqlite3_bind_text(stmt, 6, "/var/mobile/Media/iTunes_Control/iTunes/OnTheGoPlaylist_\(containerPid).plist", -1, transient)
        let rc = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("folder: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Created playlist folder '\(name)' with pid: \(containerPid)")
    }

    static func readPlaylistDescriptions(db: OpaquePointer?) -> [Int64: String] {
        var result: [Int64: String] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT container_pid, description FROM container WHERE description IS NOT NULL AND description <> '' AND smart_is_folder = 0", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let raw = sqlite3_column_text(stmt, 1) {
                    result[sqlite3_column_int64(stmt, 0)] = String(cString: raw)
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    static func setPlaylistDescription(db: OpaquePointer?, containerPid: Int64, text: String) throws {
        let sql = "UPDATE container SET description = ?, date_modified = ? WHERE container_pid = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("description: \(error)")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, text, -1, transient)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(stmt, 3, containerPid)
        let rc = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("description: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Set description for playlist \(containerPid)")
    }

    static func movePlaylist(db: OpaquePointer?, containerPid: Int64, toFolder folderPid: Int64) throws {
        let now = Date().timeIntervalSinceReferenceDate
        try executeSQL(db, "UPDATE container SET parent_pid = \(folderPid), date_modified = \(now) WHERE container_pid = \(containerPid)")
        Logger.shared.log("[MediaLibraryBuilder] Moved playlist \(containerPid) to folder \(folderPid)")
    }

    static func deletePlaylistFolder(db: OpaquePointer?, containerPid: Int64) throws {
        try executeSQL(db, "UPDATE container SET parent_pid = 0 WHERE parent_pid = \(containerPid)")
        try executeSQL(db, "DELETE FROM container WHERE container_pid = \(containerPid) AND smart_is_folder = 1")
        Logger.shared.log("[MediaLibraryBuilder] Deleted playlist folder \(containerPid)")
    }
}
