import SwiftUI

// MARK: - Songs
struct DatabaseSongsView: View {
    @ObservedObject var store: DatabaseEditorStore

    private let pageSize = 20

    @State private var songs: [DatabaseSong] = []
    @State private var total = 0
    @State private var page = 0
    @State private var search = ""
    @State private var expanded: Set<Int64> = []

    private var pageCount: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    var body: some View {
        List {
            Section {
                TextField("Search title, artist, album or id", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { page = 0; reload() }
            } footer: {
                Text("\(total) songs. Tap a song to expand and edit all of its fields.")
            }

            Section {
                ForEach(songs) { song in
                    DisclosureGroup(isExpanded: binding(for: song.id)) {
                        DatabaseSongDetail(store: store, itemPid: song.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title.isEmpty ? "(no title)" : song.title)
                                .font(.body)
                                .lineLimit(1)
                            Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " - "))
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        .navigationTitle("Songs")
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
        total = store.songCount(search: search)
        songs = store.songs(search: search, offset: page * pageSize, limit: pageSize)
        expanded = []
    }
}

// MARK: - Song Detail
struct DatabaseSongDetail: View {
    @ObservedObject var store: DatabaseEditorStore
    let itemPid: Int64

    @State private var sections: [DatabaseSongSection] = []

    var body: some View {
        Group {
            ForEach(sections) { section in
                Text(section.table)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.accentColor)
                    .padding(.top, 6)
                DatabaseRowEditor(store: store, table: section.table, columns: section.columns, row: section.row)
            }
        }
        .onAppear { sections = store.songSections(itemPid: itemPid) }
    }
}
