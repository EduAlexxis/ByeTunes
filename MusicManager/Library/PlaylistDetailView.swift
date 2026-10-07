import SwiftUI

struct PlaylistDetailView: View {
    let playlistName: String
    let playlistPid: Int64
    let allSongs: [DeviceManager.ExportableSongInfo]
    let onSave: ([DeviceManager.PlaylistAction]) -> Void
    
    @State private var songs: [DeviceManager.ExportableSongInfo]
    @State private var actions: [DeviceManager.PlaylistAction] = []
    
    @Environment(\.dismiss) private var dismiss
    
    init(playlistName: String, playlistPid: Int64, initialSongs: [DeviceManager.ExportableSongInfo], allSongs: [DeviceManager.ExportableSongInfo], onSave: @escaping ([DeviceManager.PlaylistAction]) -> Void) {
        self.playlistName = playlistName
        self.playlistPid = playlistPid
        self.allSongs = allSongs
        self.onSave = onSave
        _songs = State(initialValue: initialSongs)
    }
    
    var body: some View {
        VStack {
            List {
                ForEach(songs) { song in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(song.title).font(.body)
                            Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let song = songs[i]
                        actions.append(.removeSong(containerPid: playlistPid, itemPid: song.itemPid))
                    }
                    songs.remove(atOffsets: indexSet)
                }
                .onMove { indices, newOffset in
                    songs.move(fromOffsets: indices, toOffset: newOffset)
                    actions.append(.reorder(containerPid: playlistPid, orderedItemPids: songs.map(\.itemPid)))
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(playlistName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save Sync") {
                    onSave(actions)
                    dismiss()
                }
                .fontWeight(.bold)
                .disabled(actions.isEmpty)
            }
        }
    }
}
