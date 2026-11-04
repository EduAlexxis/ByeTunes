import Foundation
import SQLite3

enum SmartPlaylistFile {
    private static let formatName = "byetunes-smart-playlists"

    private struct Container: Codable {
        var format: String
        var version: Int
        var playlists: [Entry]
    }

    private struct Entry: Codable {
        var name: String
        var criteria: Data
        var isLimited: Bool
        var limitKind: Int
        var limitOrder: Int
        var limitValue: Int
        var limitReverse: Bool
    }

    static func encode(_ playlists: [NativeSmartPlaylist]) -> Data? {
        let entries = playlists.map { playlist in
            Entry(
                name: playlist.name,
                criteria: SmartCriteriaCodec.serialize(playlist.criteria),
                isLimited: playlist.limit.isLimited,
                limitKind: playlist.limit.kind,
                limitOrder: playlist.limit.order,
                limitValue: playlist.limit.value,
                limitReverse: playlist.limit.reverse
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Container(format: formatName, version: 1, playlists: entries))
    }

    static func decode(_ data: Data) -> [NativeSmartPlaylist] {
        guard let container = try? JSONDecoder().decode(Container.self, from: data),
              container.format == formatName else {
            return []
        }
        return container.playlists.compactMap { entry in
            guard let criteria = SmartCriteriaCodec.parse(entry.criteria) else { return nil }
            var limit = SmartPlaylistLimit()
            limit.isLimited = entry.isLimited
            limit.kind = entry.limitKind
            limit.order = entry.limitOrder
            limit.value = entry.limitValue
            limit.reverse = entry.limitReverse
            return NativeSmartPlaylist(
                pid: Int64.random(in: 1_000_000_000...9_999_999_999_999),
                name: entry.name,
                criteria: criteria,
                limit: limit
            )
        }
    }

    static func readDatabase(at url: URL) -> [NativeSmartPlaylist] {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("smart_import_\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let local = tempDir.appendingPathComponent("library.sqlitedb")
            try fileManager.copyItem(at: url, to: local)
            for suffix in ["-wal", "-shm"] {
                let sibling = URL(fileURLWithPath: url.path + suffix)
                if fileManager.isReadableFile(atPath: sibling.path) {
                    try? fileManager.copyItem(at: sibling, to: tempDir.appendingPathComponent("library.sqlitedb" + suffix))
                }
            }
            var db: OpaquePointer?
            guard sqlite3_open_v2(local.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return []
            }
            defer { sqlite3_close(db) }
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
            return MediaLibraryBuilder.readNativeSmartPlaylists(db: db).map {
                NativeSmartPlaylist(
                    pid: Int64.random(in: 1_000_000_000...9_999_999_999_999),
                    name: $0.name,
                    criteria: $0.criteria,
                    limit: $0.limit
                )
            }
        } catch {
            return []
        }
    }

    static func writeTemporaryFile(_ playlists: [NativeSmartPlaylist], fileName: String) -> URL? {
        guard let data = encode(playlists) else { return nil }
        let safeName = DeviceManager.sanitizedExportFilenameBase(fileName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "Smart Playlists" : safeName).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
