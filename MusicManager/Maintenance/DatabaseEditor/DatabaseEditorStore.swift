import Foundation
import Combine
import SQLite3

// MARK: - Models
enum DatabaseValue: Equatable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    var display: String {
        switch self {
        case .null:
            return "NULL"
        case .int(let value):
            return String(value)
        case .real(let value):
            return String(value)
        case .text(let value):
            return value
        case .blob(let data):
            let preview = data.prefix(16).map { String(format: "%02x", $0) }.joined()
            return "<BLOB \(data.count) bytes> \(preview)"
        }
    }

    var isEditable: Bool {
        if case .blob = self { return false }
        return true
    }
}

struct DatabaseColumn: Identifiable {
    let name: String
    let type: String
    var id: String { name }
}

struct DatabaseTable: Identifiable {
    let name: String
    let rowCount: Int
    var id: String { name }
}

struct DatabaseRow: Identifiable {
    let id: Int64
    var values: [DatabaseValue]
}

struct DatabaseSong: Identifiable {
    let id: Int64
    let title: String
    let artist: String
    let album: String
    let liked: Int64
}

struct DatabaseSongSection: Identifiable {
    let table: String
    let columns: [DatabaseColumn]
    let row: DatabaseRow
    var id: String { table }
}

enum DatabaseEditorError: LocalizedError {
    case cannotOpen
    case notALibrary
    case invalidValue(String)
    case sql(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "Could not open the database."
        case .notALibrary:
            return "This is not a Music library database."
        case .invalidValue(let message):
            return message
        case .sql(let message):
            return message
        }
    }
}

// MARK: - Store
@MainActor
final class DatabaseEditorStore: ObservableObject {
    @Published private(set) var isOpen = false
    @Published private(set) var sourceName = ""
    @Published private(set) var pendingChanges = 0
    @Published private(set) var revision = 0

    private var db: OpaquePointer?
    private var columnCache: [String: [DatabaseColumn]] = [:]

    let workingDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DatabaseEditor", isDirectory: true)
    }()

    var workingURL: URL {
        workingDirectory.appendingPathComponent("MediaLibrary.sqlitedb")
    }

    static let songTables = ["item", "item_extra", "item_stats", "item_store", "item_playback", "item_video", "item_search", "lyrics"]

    // MARK: Lifecycle
    func open(copying source: URL, displayName: String) throws {
        close()
        let fm = FileManager.default
        try? fm.removeItem(at: workingDirectory)
        try fm.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: workingURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: workingURL.path + suffix))
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open(workingURL.path, &handle) == SQLITE_OK else {
            if handle != nil { sqlite3_close(handle) }
            throw DatabaseEditorError.cannotOpen
        }
        db = handle
        columnCache = [:]
        guard scalar("SELECT COUNT(*) FROM item") != nil, scalar("SELECT COUNT(*) FROM container") != nil else {
            close()
            throw DatabaseEditorError.notALibrary
        }
        execute("PRAGMA wal_checkpoint(TRUNCATE)")
        execute("PRAGMA journal_mode=DELETE")
        execute("BEGIN IMMEDIATE")
        sourceName = displayName
        pendingChanges = 0
        isOpen = true
        revision += 1
    }

    func close() {
        if let db {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            sqlite3_close(db)
        }
        db = nil
        isOpen = false
        pendingChanges = 0
        columnCache = [:]
    }

    func save() {
        guard db != nil, pendingChanges > 0 else { return }
        execute("COMMIT")
        execute("BEGIN IMMEDIATE")
        pendingChanges = 0
        revision += 1
    }

    func discard() {
        guard db != nil else { return }
        execute("ROLLBACK")
        execute("BEGIN IMMEDIATE")
        pendingChanges = 0
        revision += 1
    }

    func commitForExport() {
        guard db != nil else { return }
        execute("COMMIT")
        execute("BEGIN IMMEDIATE")
        pendingChanges = 0
    }

    // MARK: Schema
    func tables() -> [DatabaseTable] {
        let names = strings("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        return names.map { DatabaseTable(name: $0, rowCount: Int(scalar("SELECT COUNT(*) FROM \(quote($0))") ?? 0)) }
    }

    func columns(of table: String) -> [DatabaseColumn] {
        if let cached = columnCache[table] { return cached }
        var result: [DatabaseColumn] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(quote(table)))", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                result.append(DatabaseColumn(name: name, type: type))
            }
        }
        sqlite3_finalize(stmt)
        columnCache[table] = result
        return result
    }

    // MARK: Rows
    func rowCount(table: String, search: String) -> Int {
        let (clause, bindings) = searchClause(table: table, search: search)
        return Int(scalar("SELECT COUNT(*) FROM \(quote(table))\(clause)", bindings: bindings) ?? 0)
    }

    func rows(table: String, search: String, offset: Int, limit: Int) -> [DatabaseRow] {
        let columnCount = columns(of: table).count
        let (clause, bindings) = searchClause(table: table, search: search)
        return query("SELECT rowid, * FROM \(quote(table))\(clause) ORDER BY rowid LIMIT \(limit) OFFSET \(offset)", bindings: bindings, columnCount: columnCount + 1).map { values in
            var values = values
            guard case .int(let rowid) = values.removeFirst() else { return DatabaseRow(id: 0, values: values) }
            return DatabaseRow(id: rowid, values: values)
        }
    }

    func rows(table: String, itemPid: Int64) -> [DatabaseRow] {
        let columnCount = columns(of: table).count
        return query("SELECT rowid, * FROM \(quote(table)) WHERE item_pid = ?", bindings: [.int(itemPid)], columnCount: columnCount + 1).map { values in
            var values = values
            guard case .int(let rowid) = values.removeFirst() else { return DatabaseRow(id: 0, values: values) }
            return DatabaseRow(id: rowid, values: values)
        }
    }

    // MARK: Songs
    func songCount(search: String) -> Int {
        let (clause, bindings) = songSearch(search)
        return Int(scalar("SELECT COUNT(*) FROM item i LEFT JOIN item_extra e ON e.item_pid = i.item_pid LEFT JOIN item_artist ia ON ia.item_artist_pid = i.item_artist_pid LEFT JOIN album al ON al.album_pid = i.album_pid\(clause)", bindings: bindings) ?? 0)
    }

    func songs(search: String, offset: Int, limit: Int) -> [DatabaseSong] {
        let (clause, bindings) = songSearch(search)
        let sql = """
        SELECT i.item_pid, IFNULL(e.title, ''), IFNULL(ia.item_artist, ''), IFNULL(al.album, ''), IFNULL(s.liked_state, 0)
        FROM item i
        LEFT JOIN item_extra e ON e.item_pid = i.item_pid
        LEFT JOIN item_stats s ON s.item_pid = i.item_pid
        LEFT JOIN item_artist ia ON ia.item_artist_pid = i.item_artist_pid
        LEFT JOIN album al ON al.album_pid = i.album_pid\(clause)
        ORDER BY e.title COLLATE NOCASE LIMIT \(limit) OFFSET \(offset)
        """
        return query(sql, bindings: bindings, columnCount: 5).compactMap { values in
            guard case .int(let pid) = values[0], case .int(let liked) = values[4] else { return nil }
            return DatabaseSong(id: pid, title: values[1].display, artist: values[2].display, album: values[3].display, liked: liked)
        }
    }

    func songSections(itemPid: Int64) -> [DatabaseSongSection] {
        let existing = Set(strings("SELECT name FROM sqlite_master WHERE type = 'table'"))
        return Self.songTables.filter { existing.contains($0) }.compactMap { table in
            let columnList = columns(of: table)
            guard columnList.contains(where: { $0.name == "item_pid" }),
                  let row = rows(table: table, itemPid: itemPid).first else { return nil }
            return DatabaseSongSection(table: table, columns: columnList, row: row)
        }
    }

    // MARK: Editing
    @discardableResult
    func update(table: String, rowid: Int64, column: String, text: String) throws -> DatabaseValue {
        let value = try parse(text, table: table, rowid: rowid, column: column)
        var stmt: OpaquePointer?
        let sql = "UPDATE \(quote(table)) SET \(quote(column)) = ? WHERE rowid = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw DatabaseEditorError.sql(errorMessage())
        }
        bind(value, at: 1, in: stmt)
        sqlite3_bind_int64(stmt, 2, rowid)
        let result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard result == SQLITE_DONE else { throw DatabaseEditorError.sql(errorMessage()) }
        pendingChanges += 1
        return value
    }

    // MARK: Helpers
    private func parse(_ text: String, table: String, rowid: Int64, column: String) throws -> DatabaseValue {
        if text == "NULL" { return .null }
        var storage = "text"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT typeof(\(quote(column))) FROM \(quote(table)) WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, rowid)
            if sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) {
                storage = String(cString: raw)
            }
        }
        sqlite3_finalize(stmt)

        let declared = (columns(of: table).first { $0.name == column }?.type ?? "").uppercased()
        let numeric: String
        if storage == "integer" || storage == "real" {
            numeric = storage
        } else if declared.contains("INT") {
            numeric = "integer"
        } else if declared.contains("REAL") || declared.contains("FLOA") || declared.contains("DOUB") {
            numeric = "real"
        } else {
            numeric = "text"
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch numeric {
        case "integer":
            guard let value = Int64(trimmed) else { throw DatabaseEditorError.invalidValue("\(column) expects a whole number.") }
            return .int(value)
        case "real":
            guard let value = Double(trimmed) else { throw DatabaseEditorError.invalidValue("\(column) expects a number.") }
            return .real(value)
        default:
            return .text(text)
        }
    }

    private func searchClause(table: String, search: String) -> (String, [DatabaseValue]) {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return ("", []) }
        let columnNames = columns(of: table).map { $0.name }
        guard !columnNames.isEmpty else { return ("", []) }
        let clause = " WHERE " + columnNames.map { "CAST(\(quote($0)) AS TEXT) LIKE ?" }.joined(separator: " OR ")
        return (clause, columnNames.map { _ in .text("%\(term)%") })
    }

    private func songSearch(_ search: String) -> (String, [DatabaseValue]) {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return ("", []) }
        let like = DatabaseValue.text("%\(term)%")
        return (" WHERE e.title LIKE ? OR ia.item_artist LIKE ? OR al.album LIKE ? OR CAST(i.item_pid AS TEXT) LIKE ?", [like, like, like, like])
    }

    private func query(_ sql: String, bindings: [DatabaseValue] = [], columnCount: Int) -> [[DatabaseValue]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return []
        }
        for (index, value) in bindings.enumerated() {
            bind(value, at: Int32(index + 1), in: stmt)
        }
        var rows: [[DatabaseValue]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<columnCount).map { value(at: Int32($0), in: stmt) })
        }
        sqlite3_finalize(stmt)
        return rows
    }

    private func scalar(_ sql: String, bindings: [DatabaseValue] = []) -> Int64? {
        guard let first = query(sql, bindings: bindings, columnCount: 1).first?.first, case .int(let number) = first else { return nil }
        return number
    }

    private func strings(_ sql: String) -> [String] {
        query(sql, columnCount: 1).compactMap { row in
            if case .text(let text) = row[0] { return text }
            return nil
        }
    }

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func value(at index: Int32, in stmt: OpaquePointer?) -> DatabaseValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            return .text(sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? "")
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(stmt, index))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private func bind(_ value: DatabaseValue, at index: Int32, in stmt: OpaquePointer?) {
        switch value {
        case .null:
            sqlite3_bind_null(stmt, index)
        case .int(let number):
            sqlite3_bind_int64(stmt, index, number)
        case .real(let number):
            sqlite3_bind_double(stmt, index, number)
        case .text(let text):
            sqlite3_bind_text(stmt, index, text, -1, SQLITE_TRANSIENT)
        case .blob(let data):
            _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        }
    }

    private func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func errorMessage() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
    }
}
