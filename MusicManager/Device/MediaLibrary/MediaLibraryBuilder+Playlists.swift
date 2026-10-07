import Foundation
import SQLite3
import CommonCrypto
import UIKit

extension MediaLibraryBuilder {
    static func createPlaylist(db: OpaquePointer?, playlistName: String, songPids: [Int64]) throws {
        let containerPid = Int64.random(in: 1_000_000_000...9_999_999_999_999)
        let now = Int64(Date().timeIntervalSince1970)
        
        
        let nameOrderResult = insertSortMap(db: db, name: playlistName)
        
        
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
            sqlite3_bind_int64(stmt, 3, Int64(nameOrderResult.order))
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

    static func setPlaylistCoverArtwork(db: OpaquePointer?, containerPid: Int64, artworkToken: String, relativePath: String) throws {
        var stmt: OpaquePointer?

        let artworkSQL = """
        INSERT OR REPLACE INTO artwork (
            artwork_token, artwork_source_type, relative_path, artwork_type, interest_data, artwork_variant_type
        ) VALUES (?, 100, ?, 5, NULL, 0)
        """
        if sqlite3_prepare_v2(db, artworkSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, artworkToken, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, relativePath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(stmt)
                throw MediaLibraryError.insertFailed("artwork: \(error)")
            }
        }
        sqlite3_finalize(stmt)

        let tokenSQL = """
        INSERT OR REPLACE INTO artwork_token (
            entity_pid, artwork_token, artwork_source_type, artwork_type, entity_type, artwork_variant_type,
            primary_text_color, secondary_text_color, tertiary_text_color, quaternary_text_color,
            background_color, gradient_text_color, gradient_color, gradient_size_start, gradient_size_end
        ) VALUES (?, ?, 100, 5, 1, 0, '', '', '', '', '', '', '', -1.0, -1.0)
        """
        if sqlite3_prepare_v2(db, tokenSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            sqlite3_bind_text(stmt, 2, artworkToken, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(stmt)
                throw MediaLibraryError.insertFailed("artwork_token: \(error)")
            }
        }
        sqlite3_finalize(stmt)

        let bestTokenSQL = """
        INSERT OR REPLACE INTO best_artwork_token (
            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
            fetchable_artwork_source_type, artwork_variant_type
        ) VALUES (?, 1, 5, ?, '', 0, 0)
        """
        if sqlite3_prepare_v2(db, bestTokenSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            sqlite3_bind_text(stmt, 2, artworkToken, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(stmt)
                throw MediaLibraryError.insertFailed("best_artwork_token: \(error)")
            }
        }
        sqlite3_finalize(stmt)

        Logger.shared.log("[MediaLibraryBuilder] Set custom cover artwork for playlist pid \(containerPid)")
    }


    static func extractPlaylists(fromDbPath path: String) -> [(name: String, pid: Int64)] {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }
        return getPlaylists(db: db)
    }
    
    
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
    
    
    static func addToPlaylist(db: OpaquePointer?, containerPid: Int64, songPids: [Int64]) throws {
        
        var maxPos: Int64 = -1
        let maxQuery = "SELECT MAX(position) FROM container_item WHERE container_pid = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, maxQuery, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            if sqlite3_step(stmt) == SQLITE_ROW {
                
                if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    maxPos = sqlite3_column_int64(stmt, 0)
                }
            }
        }
        sqlite3_finalize(stmt)
        
        let startPos = maxPos + 1
        Logger.shared.log("[MediaLibraryBuilder] Appending \(songPids.count) songs to playlist \(containerPid) starting at pos \(startPos)")
        
        
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
    
    static func deletePlaylist(db: OpaquePointer?, containerPid: Int64) throws {
        var stmt: OpaquePointer?
        
        let deleteItems = "DELETE FROM container_item WHERE container_pid = ?"
        if sqlite3_prepare_v2(db, deleteItems, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        let deleteContainer = "DELETE FROM container WHERE container_pid = ?"
        if sqlite3_prepare_v2(db, deleteContainer, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                throw MediaLibraryError.insertFailed("Failed to delete playlist: \(error)")
            }
        }
        sqlite3_finalize(stmt)
        Logger.shared.log("[MediaLibraryBuilder] Deleted playlist \(containerPid)")
    }
    
    static func renamePlaylist(db: OpaquePointer?, containerPid: Int64, newName: String) throws {
        let updateSQL = "UPDATE container SET name = ?, date_modified = ? WHERE container_pid = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, newName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSinceReferenceDate))
            sqlite3_bind_int64(stmt, 3, containerPid)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                sqlite3_finalize(stmt)
                throw MediaLibraryError.insertFailed("Failed to rename playlist: \(error)")
            }
        }
        sqlite3_finalize(stmt)
        Logger.shared.log("[MediaLibraryBuilder] Renamed playlist \(containerPid) to '\(newName)'")
    }
    
    static func removeSongFromPlaylist(db: OpaquePointer?, containerPid: Int64, itemPid: Int64) throws {
        let getSQL = "SELECT container_item_pid FROM container_item WHERE container_pid = ? AND item_pid = ? LIMIT 1"
        var stmt: OpaquePointer?
        var targetItemPid: Int64?
        
        if sqlite3_prepare_v2(db, getSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            sqlite3_bind_int64(stmt, 2, itemPid)
            if sqlite3_step(stmt) == SQLITE_ROW {
                targetItemPid = sqlite3_column_int64(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        
        guard let idToDelete = targetItemPid else { return }
        
        let deleteSQL = "DELETE FROM container_item WHERE container_item_pid = ?"
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, idToDelete)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        Logger.shared.log("[MediaLibraryBuilder] Removed song \(itemPid) from playlist \(containerPid)")
    }
    
    static func reorderSongsInPlaylist(db: OpaquePointer?, containerPid: Int64, orderedItemPids: [Int64]) throws {
        var stmt: OpaquePointer?
        
        let getSQL = "SELECT container_item_pid, item_pid FROM container_item WHERE container_pid = ?"
        var currentItems: [Int64: Int64] = [:] 
        
        if sqlite3_prepare_v2(db, getSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, containerPid)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let ciPid = sqlite3_column_int64(stmt, 0)
                let iPid = sqlite3_column_int64(stmt, 1)
                currentItems[iPid] = ciPid
            }
        }
        sqlite3_finalize(stmt)
        
        let updateSQL = "UPDATE container_item SET position = ? WHERE container_item_pid = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            for (index, itemPid) in orderedItemPids.enumerated() {
                guard let ciPid = currentItems[itemPid] else { continue }
                sqlite3_bind_int64(stmt, 1, Int64(index))
                sqlite3_bind_int64(stmt, 2, ciPid)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
        sqlite3_finalize(stmt)
        Logger.shared.log("[MediaLibraryBuilder] Reordered \(orderedItemPids.count) songs in playlist \(containerPid)")
    }
    
}
