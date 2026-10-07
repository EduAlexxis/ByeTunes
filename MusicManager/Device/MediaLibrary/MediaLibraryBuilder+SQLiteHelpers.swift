import Foundation
import SQLite3
import CommonCrypto
import UIKit

// MARK: - SQLite Helpers
extension MediaLibraryBuilder {
    static func generateRingtoneIntegrity(filename: String) -> String {
        
        
        let rawString = "iTunes_Control/Ringtones/\(filename)"
        guard let data = rawString.data(using: .utf8) else { return "" }
        return data.map { String(format: "%02X", $0) }.joined()
    }

    static func executeSQL(_ db: OpaquePointer?, _ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            Logger.shared.log("[MediaLibraryBuilder] SQL Error: \(error)")
            Logger.shared.log("[MediaLibraryBuilder] SQL: \(sql)")
            throw MediaLibraryError.insertFailed(error)
        }
    }
    
    
    
    static func insertSortMap(db: OpaquePointer?, name: String) -> (order: Int64, section: Int) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT name_order, name_section FROM sort_map WHERE name = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                let existingOrder = sqlite3_column_int64(stmt, 0)
                let existingSection = Int(sqlite3_column_int(stmt, 1))
                sqlite3_finalize(stmt)
                return (existingOrder, existingSection)
            }
        }
        sqlite3_finalize(stmt)

        var maxOrder: Int64 = 0
        if sqlite3_prepare_v2(db, "SELECT MAX(name_order) FROM sort_map", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxOrder = sqlite3_column_int64(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)

        let nameOrder = maxOrder + 1

        var nameSection = 26
        let normalized = name.folding(options: .diacriticInsensitive, locale: .current)
        if let firstChar = normalized.uppercased().first {
            let charValue = Int(firstChar.asciiValue ?? 0)
            if charValue >= 65 && charValue <= 90 {
                nameSection = charValue - 65
            }
        }

        let sortKey = SongMetadata.generateGroupingKey(name)
        let sortKeyHex = sortKey.map { String(format: "%02x", $0) }.joined()

        var insertStmt: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO sort_map (name, name_order, name_section, sort_key) VALUES (?, ?, ?, X'\(sortKeyHex)')"
        if sqlite3_prepare_v2(db, sql, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(insertStmt, 2, nameOrder)
            sqlite3_bind_int(insertStmt, 3, Int32(nameSection))
            if sqlite3_step(insertStmt) != SQLITE_DONE {
                Logger.shared.log("[MediaLibraryBuilder] sort_map insert error: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            Logger.shared.log("[MediaLibraryBuilder] sort_map prepare error: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(insertStmt)

        return (nameOrder, nameSection)
    }
    
    
    
    
    
    
    
    

    static func columnExists(db: OpaquePointer?, tableName: String, columnName: String) -> Bool {
        var exists = false
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(tableName))"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(stmt, 1) {
                    let name = String(cString: namePtr)
                    if name == columnName {
                        exists = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return exists
    }
}
