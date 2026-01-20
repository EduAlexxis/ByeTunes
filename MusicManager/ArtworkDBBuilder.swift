import Foundation

/// Generates the legacy iPod ArtworkDB binary file format
/// iOS 26 still requires this file at /iTunes_Control/Artwork/ArtworkDB
class ArtworkDBBuilder {
    
    /// Artwork entry representing a song with artwork
    struct ArtworkEntry {
        let imageID: UInt32          // Unique artwork ID (e.g., 100, 101, 102...)
        let songDBID: UInt64         // item_pid from MediaLibrary
        let artworkHash: String      // Hash path like "31/0b86e0..."
        let fileSize: UInt32         // Size of the artwork file in bytes
    }
    
    // MARK: - Public API
    
    /// Generates an ArtworkDB file containing entries for the provided artwork
    /// - Parameter entries: List of artwork entries to include
    /// - Returns: Binary data for the ArtworkDB file
    static func generateArtworkDB(entries: [ArtworkEntry]) -> Data {
        var data = Data()
        
        // Revised Structure: mhfd -> mhsd(1) -> mhli -> [mhii -> mhif] -> mhsd(2) -> mhla
        // mhif (File) is now a CHILD of mhii (Image)
        
        let mhfdSize: UInt32 = 0x84       // 132 bytes
        let mhsdSize: UInt32 = 0x60       // 96 bytes
        let mhliSize: UInt32 = 0x5C       // 92 bytes
        let mhlaSize: UInt32 = 0x5C       // 92 bytes
        
        let mhiiHeaderSize: UInt32 = 0x98 // 152 bytes (mhii header + padding)
        let mhifSize: UInt32 = 0x7C       // 124 bytes (mhif header + padding)
        
        // Total size of one image block (mhii + mhif)
        let imageBlockSize = mhiiHeaderSize + mhifSize
        
        let imageCount = UInt32(entries.count)
        
        // Calculate section sizes
        let section1TotalSize = mhsdSize + mhliSize + (imageBlockSize * imageCount)
        let section2TotalSize = mhsdSize + mhlaSize
        
        let totalFileSize = mhfdSize + section1TotalSize + section2TotalSize
        
        // ============ mhfd (File Header) ============
        data.append(contentsOf: "mhfd".utf8)                    // 0: magic
        data.append(uint32LE: mhfdSize)                         // 4: header length
        data.append(uint32LE: totalFileSize)                    // 8: total file length
        data.append(uint32LE: 0)                                // 12: unknown
        data.append(uint32LE: 0)                                // 16: unknown  
        data.append(uint32LE: 2)                                // 20: number of sections (Reduced to 2)
        data.append(uint32LE: 0)                                // 24: unknown
        // Calculate next image ID based on maximum ID in entries
        let maxId = entries.map { $0.imageID }.max() ?? 1000
        data.append(uint32LE: maxId + 1)                        // 28: next image ID
        data.append(Data(count: Int(mhfdSize - 32)))            // padding to 132 bytes
        
        // ============ mhsd Section 1 (Image List) ============
        data.append(contentsOf: "mhsd".utf8)                    // 0: magic
        data.append(uint32LE: mhsdSize)                         // 4: header length
        data.append(uint32LE: section1TotalSize)                // 8: total section length
        data.append(uint32LE: 1)                                // 12: section type (1 = image list)
        data.append(Data(count: Int(mhsdSize - 16)))            // padding
        
        // ============ mhli (Image List) ============
        data.append(contentsOf: "mhli".utf8)                    // 0: magic
        data.append(uint32LE: mhliSize)                         // 4: header length
        data.append(uint32LE: imageCount)                       // 8: number of images
        data.append(Data(count: Int(mhliSize - 12)))            // padding
        
        // ============ mhii entries (with nested mhif) ============
        for (index, entry) in entries.enumerated() {
            // ---- mhii (Image Item) ----
            data.append(contentsOf: "mhii".utf8)                // 0: magic
            data.append(uint32LE: mhiiHeaderSize)               // 4: header length  
            data.append(uint32LE: imageBlockSize)               // 8: total length (includes self + children)
            data.append(uint32LE: 1)                            // 12: number of children (1 mhif)
            data.append(uint32LE: entry.imageID)                // 16: image ID
            data.append(uint64LE: entry.songDBID)               // 20: song DBID (item_pid)
            data.append(uint32LE: 0)                            // 28: unknown
            data.append(uint32LE: entry.fileSize)               // 32: source image size
            data.append(Data(count: Int(mhiiHeaderSize - 36)))  // padding
            
            // ---- mhif (File Info) Nested Child ----
            data.append(contentsOf: "mhif".utf8)                // 0: magic
            data.append(uint32LE: mhifSize)                     // 4: header length
            data.append(uint32LE: mhifSize)                     // 8: total length
            data.append(uint32LE: 0)                            // 12: correlationID (3uTools uses 0)
            data.append(uint32LE: entry.fileSize)               // 16: image size
            data.append(Data(count: Int(mhifSize - 20)))        // padding
        }
        
        // ============ mhsd Section 2 (Album List) ============
        data.append(contentsOf: "mhsd".utf8)
        data.append(uint32LE: mhsdSize)
        data.append(uint32LE: section2TotalSize)
        data.append(uint32LE: 2)                                // section type 2 = album list
        data.append(Data(count: Int(mhsdSize - 16)))
        
        // ============ mhla (Album List - empty) ============
        data.append(contentsOf: "mhla".utf8)
        data.append(uint32LE: mhlaSize)
        data.append(uint32LE: 0)                                // 0 albums
        data.append(Data(count: Int(mhlaSize - 12)))
        
        return data
    }

    
    /// Generates an empty ArtworkDB (skeleton structure with no artwork)
    static func generateEmptyArtworkDB() -> Data {
        return generateArtworkDB(entries: [])
    }
}

// MARK: - Data Extension for Little-Endian Writing

extension Data {
    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
    
    mutating func append(uint64LE value: UInt64) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
