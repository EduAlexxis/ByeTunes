import Foundation
import SQLite3
import CommonCrypto
import UIKit

extension String {
    nonisolated var sqlEscaped: String {
        replacingOccurrences(of: "\u{0}", with: "").replacingOccurrences(of: "'", with: "''")
    }
}

enum MediaLibraryError: Error, LocalizedError {
    case databaseOpenFailed
    case schemaCreationFailed(String)
    case insertFailed(String)
    case integrityCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed:
            return "Failed to open database"
        case .schemaCreationFailed(let msg):
            return "Schema creation failed: \(msg)"
        case .insertFailed(let msg):
            return "Insert failed: \(msg)"
        case .integrityCheckFailed(let msg):
            return "The device's media library failed an integrity check (\(msg)). Run Clean & Repair Library in Settings before trying again."
        }
    }
}

class MediaLibraryBuilder {
    nonisolated static let itemRowTables = [
        "item", "item_extra", "item_playback", "item_stats", "item_store",
        "item_video", "item_search", "lyrics", "chapter"
    ]

    @discardableResult
    nonisolated static func deleteItemRows(db: OpaquePointer?, pid: Int64, tables: [String] = itemRowTables) -> Bool {
        guard sqlite3_exec(db, "SAVEPOINT delete_item_rows", nil, nil, nil) == SQLITE_OK else {
            Logger.shared.log("[MediaLibraryBuilder] Could not open savepoint to delete PID \(pid)")
            return false
        }
        for table in tables {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM \(table) WHERE item_pid = ?", -1, &stmt, nil) == SQLITE_OK else {
                sqlite3_finalize(stmt)
                continue
            }
            sqlite3_bind_int64(stmt, 1, pid)
            let rc = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            if rc != SQLITE_DONE {
                Logger.shared.log("[MediaLibraryBuilder] Delete from \(table) failed for PID \(pid); rolling back")
                sqlite3_exec(db, "ROLLBACK TO delete_item_rows", nil, nil, nil)
                sqlite3_exec(db, "RELEASE delete_item_rows", nil, nil, nil)
                return false
            }
        }
        return sqlite3_exec(db, "RELEASE delete_item_rows", nil, nil, nil) == SQLITE_OK
    }

    static func shouldWriteAppleCatalogStoreFields(for song: SongMetadata) -> Bool {
        guard song.storeId > 0 else { return false }

        let metadataSource = UserDefaults.standard.string(forKey: "metadataSource") ?? "apple"
        let richAppleMetadata = UserDefaults.standard.bool(forKey: "appleRichMetadata")

        if metadataSource == "apple" {
            return true
        }

        return richAppleMetadata
    }
    
    
    
    
    struct ArtworkInfo {
        let itemPid: Int64        
        let artworkHash: String   
        let artworkToken: String  
        let fileSize: UInt32      
    }
    
    
    
    
    static func generateIntegrityHex(filename: String) -> String {
        
        return "X''"
        
    }
    
    
    
    
    static func fourCC(_ str: String) -> Int {
        
        let padded = Array(str.utf8) + Array(repeating: 0x20, count: max(0, 4 - str.utf8.count))
        var val = 0
        for i in 0..<4 {
            val = (val << 8) | Int(padded[i])
        }
        return val
    }

    
    
    static func audioFormatForExtension(_ ext: String) -> Int {
        switch ext.lowercased() {
        case "mp3":
            return 301
        case "flac":
            return fourCC("fLaC")  
        case "opus":
            return fourCC("opus")
        case "m4a", "aac", "m4r":
            return fourCC("aac ")  
        case "alac":
            return fourCC("alac") 
        case "wav", "wave":
            return fourCC("WAVE") 
        default:
            return 0  
        }
    }
}
