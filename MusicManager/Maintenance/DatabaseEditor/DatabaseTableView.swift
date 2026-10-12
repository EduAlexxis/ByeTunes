import SwiftUI

// MARK: - Tables
struct DatabaseTablesView: View {
    @ObservedObject var store: DatabaseEditorStore
    @State private var tables: [DatabaseTable] = []

    var body: some View {
        List(tables) { table in
            NavigationLink {
                DatabaseTableView(store: store, table: table.name)
            } label: {
                HStack {
                    Text(table.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(table.rowCount)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Tables")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tables = store.tables() }
    }
}

// MARK: - Table
struct DatabaseTableView: View {
    @ObservedObject var store: DatabaseEditorStore
    let table: String

    private let pageSize = 25

    @State private var rows: [DatabaseRow] = []
    @State private var total = 0
    @State private var page = 0
    @State private var search = ""
    @State private var expanded: Set<Int64> = []

    private var columns: [DatabaseColumn] { store.columns(of: table) }
    private var pageCount: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    var body: some View {
        List {
            Section {
                TextField("Search all columns", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { page = 0; reload() }
            } footer: {
                Text("\(total) rows. Tap a row to expand and edit it.")
            }

            Section {
                ForEach(rows) { row in
                    DisclosureGroup(isExpanded: binding(for: row.id)) {
                        DatabaseRowEditor(store: store, table: table, columns: columns, row: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("rowid \(row.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(summary(of: row))
                                .font(.footnote)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button("Previous") { page -= 1; reload() }
                        .disabled(page == 0)
                    Spacer()
                    Text("Page \(page + 1) of \(pageCount)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Next") { page += 1; reload() }
                        .disabled(page + 1 >= pageCount)
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle(table)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: store.revision) { _ in reload() }
    }

    private func binding(for id: Int64) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func reload() {
        total = store.rowCount(table: table, search: search)
        rows = store.rows(table: table, search: search, offset: page * pageSize, limit: pageSize)
        expanded = []
    }

    private func summary(of row: DatabaseRow) -> String {
        let names = ["title", "name", "album", "item_artist", "album_artist", "genre", "key"]
        let preferred = columns.enumerated().first { names.contains($0.element.name) && $0.offset < row.values.count }
        if let preferred, case .text(let text) = row.values[preferred.offset], !text.isEmpty {
            return text
        }
        return row.values.prefix(3).map { $0.display }.joined(separator: "  |  ")
    }
}
