import SwiftUI

// MARK: - Field
struct DatabaseFieldRow: View {
    @ObservedObject var store: DatabaseEditorStore
    let table: String
    let rowid: Int64
    let column: DatabaseColumn
    let initial: DatabaseValue

    @State private var text: String
    @State private var isEdited = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(store: DatabaseEditorStore, table: String, rowid: Int64, column: DatabaseColumn, initial: DatabaseValue) {
        self.store = store
        self.table = table
        self.rowid = rowid
        self.column = column
        self.initial = initial
        _text = State(initialValue: initial.display)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(column.name)
                    .font(.caption)
                    .foregroundColor(isEdited ? .orange : .secondary)
                if !column.type.isEmpty {
                    Text(column.type.lowercased())
                        .font(.caption2)
                        .foregroundColor(Color(.systemGray3))
                }
            }
            if initial.isEditable {
                TextField("NULL", text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { apply() }
                    .onChange(of: focused) { isFocused in
                        if !isFocused { apply() }
                    }
            } else {
                Text(initial.display)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func apply() {
        guard initial.isEditable else { return }
        guard text != (isEdited ? text : initial.display) || !isEdited else { return }
        do {
            let value = try store.update(table: table, rowid: rowid, column: column.name, text: text)
            text = value.display
            isEdited = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row
struct DatabaseRowEditor: View {
    @ObservedObject var store: DatabaseEditorStore
    let table: String
    let columns: [DatabaseColumn]
    let row: DatabaseRow

    var body: some View {
        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
            if index < row.values.count {
                DatabaseFieldRow(store: store, table: table, rowid: row.id, column: column, initial: row.values[index])
            }
        }
    }
}
