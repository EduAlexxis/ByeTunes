import Foundation
import SQLite3

// MARK: - Favorites Playlist
extension MediaLibraryBuilder {
    private static let favoritesPlaylistKind: Int64 = 71
    private static let britishSpellingRegions: Set<String> = ["GB", "IE", "AU", "NZ", "CA", "ZA", "IN", "SG"]

    private static var favoritesPlaylistName: String {
        let region = Locale.current.region?.identifier ?? ""
        return britishSpellingRegions.contains(region) ? "Favourite Songs" : "Favorite Songs"
    }
    private static let favoritesCriteriaHex = "534C73740001000100000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009A0000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004400000000000000020000000000000000000000000000000100000000000000020000000000000000000000000000000100000000000000000000000000000000000000000000003C000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000440000000000000001000000000000000000000000000000010000000000000001000000000000000000000000000000010000000000000000000000000000000000000000"

    static func hasFavoritesPlaylist(db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        var found = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM container WHERE distinguished_kind = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, favoritesPlaylistKind)
            found = sqlite3_step(stmt) == SQLITE_ROW
        }
        sqlite3_finalize(stmt)
        return found
    }

    static func createFavoritesPlaylist(db: OpaquePointer?) throws {
        let containerPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        let now = Date().timeIntervalSinceReferenceDate
        let name = favoritesPlaylistName
        let nameOrder = insertSortMap(db: db, name: name).order
        let criteria = hexData(favoritesCriteriaHex)

        let sql = """
        INSERT INTO container (
            container_pid, distinguished_kind, date_created, date_modified, name, name_order,
            is_owner, is_editable, parent_pid, contained_media_type, liked_state,
            smart_is_dynamic, smart_is_filtered, smart_is_limited, smart_limit_kind,
            smart_limit_order, smart_limit_value, smart_criteria, play_order,
            filepath, category_type_mask, liked_state_changed_date
        ) VALUES (?, ?, ?, ?, ?, ?, 1, 0, 0, 0, 2, 1, 1, 1, 2, 112, 50000, ?, 1, ?, 4, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw MediaLibraryError.insertFailed("favorites container: \(error)")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(stmt, 1, containerPid)
        sqlite3_bind_int64(stmt, 2, favoritesPlaylistKind)
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_bind_double(stmt, 4, now)
        sqlite3_bind_text(stmt, 5, name, -1, transient)
        sqlite3_bind_int64(stmt, 6, nameOrder)
        _ = criteria.withUnsafeBytes { sqlite3_bind_blob(stmt, 7, $0.baseAddress, Int32(criteria.count), transient) }
        sqlite3_bind_text(stmt, 8, "/var/mobile/Media/iTunes_Control/iTunes/OnTheGoPlaylist_\(containerPid).plist", -1, transient)
        sqlite3_bind_double(stmt, 9, now)

        let result = sqlite3_step(stmt)
        let error = String(cString: sqlite3_errmsg(db))
        sqlite3_finalize(stmt)
        guard result == SQLITE_DONE else {
            throw MediaLibraryError.insertFailed("favorites container: \(error)")
        }
        Logger.shared.log("[MediaLibraryBuilder] Created favorites playlist with pid: \(containerPid)")
    }

    static func deleteFavoritesPlaylist(db: OpaquePointer?) throws {
        try executeSQL(db, "DELETE FROM container_item WHERE container_pid IN (SELECT container_pid FROM container WHERE distinguished_kind = \(favoritesPlaylistKind))")
        try executeSQL(db, "DELETE FROM container WHERE distinguished_kind = \(favoritesPlaylistKind)")
        Logger.shared.log("[MediaLibraryBuilder] Removed existing favorites playlist")
    }

    static func refreshLocalFavorites(db: OpaquePointer?) throws -> Int {
        let now = Date().timeIntervalSinceReferenceDate
        try executeSQL(db, """
            UPDATE item_stats SET liked_state = 2, liked_state_changed = 1, liked_state_changed_date = \(now)
            WHERE liked_state = 2
            AND item_pid IN (SELECT item_pid FROM item_store WHERE cloud_in_my_library = 0)
        """)
        let refreshed = Int(sqlite3_changes(db))
        Logger.shared.log("[MediaLibraryBuilder] Refreshed \(refreshed) favorited songs")
        return refreshed
    }

    static func fixFavoritedLocalSongs(db: OpaquePointer?) throws -> Int {
        let now = Date().timeIntervalSinceReferenceDate
        let favoritedWithoutCatalogId = """
            item_pid IN (SELECT item_pid FROM item_stats WHERE liked_state = 2)
            AND store_saga_id = 0
        """
        try executeSQL(db, """
            UPDATE item_store SET
                cloud_in_my_library = 1,
                cloud_status = 8,
                storefront_id = CASE WHEN storefront_id = 0 THEN 143441 ELSE storefront_id END,
                store_item_id = 9000000000 + ABS(item_pid % 900000000),
                store_saga_id = 9000000000 + ABS(item_pid % 900000000),
                subscription_store_item_id = 9000000000 + ABS(item_pid % 900000000),
                store_playlist_id = 9000000000 + ABS(item_pid % 900000000)
            WHERE \(favoritedWithoutCatalogId)
        """)
        let fixed = Int(sqlite3_changes(db))
        try executeSQL(db, """
            UPDATE item_stats SET liked_state_changed = 1, liked_state_changed_date = \(now)
            WHERE liked_state = 2
            AND item_pid IN (SELECT item_pid FROM item_store WHERE store_saga_id >= 9000000000)
        """)
        Logger.shared.log("[MediaLibraryBuilder] Fixed \(fixed) favorited songs without a catalog id")
        return fixed
    }

    private static func hexData(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<next], radix: 16) {
                data.append(byte)
            }
            index = next
        }
        return data
    }
}
