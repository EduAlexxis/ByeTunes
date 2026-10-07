import SwiftUI
import UniformTypeIdentifiers

struct BatchMetadataEditorSheet: View {
    @Binding var songs: [SongMetadata]
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedSong: SongMetadata?

    private var filteredSongs: [SongMetadata] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return songs }
        let needle = trimmed.lowercased()
        return songs.filter {
            $0.title.lowercased().contains(needle) ||
            $0.artist.lowercased().contains(needle) ||
            $0.album.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search imported songs", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSongs.enumerated()), id: \.element.id) { index, song in
                            HStack(spacing: 12) {
                                artworkView(for: song)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(song.album)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 12)

                                Button {
                                    selectedSong = song
                                } label: {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "pencil")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.accentColor)
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        songs.removeAll { $0.id == song.id }
                                    }
                                } label: {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "xmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)

                            if index < filteredSongs.count - 1 {
                                Divider().padding(.leading, 88)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Batch Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !songs.isEmpty {
                        Button("Clear All", role: .destructive) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                songs.removeAll()
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedSong) { item in
                if let index = songs.firstIndex(where: { $0.id == item.id }) {
                    ManualMetadataEditor(
                        song: $songs[index],
                        isPresented: Binding(
                            get: { selectedSong != nil },
                            set: { if !$0 { selectedSong = nil } }
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func artworkView(for song: SongMetadata) -> some View {
        if let data = song.artworkPreviewData ?? song.artworkData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
            }
            .frame(width: 56, height: 56)
        }
    }
}
