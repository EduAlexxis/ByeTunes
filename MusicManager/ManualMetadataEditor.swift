import SwiftUI
import PhotosUI

struct ManualMetadataEditor: View {
    @Binding var song: SongMetadata
    @Binding var isPresented: Bool
    
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""
    
    @State private var artworkItem: PhotosPickerItem?
    @State private var artworkData: Data?
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, artist, album, genre, year
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let data = artworkData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 140, height: 140)
                                    .cornerRadius(12)
                                    .shadow(radius: 4)
                            } else {
                                ZStack {
                                    Color(uiColor: .systemGray5)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 140, height: 140)
                                .cornerRadius(12)
                            }
                            
                            PhotosPicker(selection: $artworkItem, matching: .images) {
                                Label("Change Artwork", systemImage: "photo.on.rectangle")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Artwork")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Title")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter title", text: $title)
                            .focused($focusedField, equals: .title)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Artist")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter artist", text: $artist)
                            .focused($focusedField, equals: .artist)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Album")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter album", text: $album)
                            .focused($focusedField, equals: .album)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Genre")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Enter genre", text: $genre)
                            .focused($focusedField, equals: .genre)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Year")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("YYYY", text: $year)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .year)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Details")
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                // Initialize state from song
                title = song.title
                artist = song.artist
                album = song.album
                genre = song.genre
                year = String(song.year)
                artworkData = song.artworkData
            }
            .onChange(of: artworkItem, perform: { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            withAnimation {
                                self.artworkData = data
                            }
                        }
                    }
                }
            })
        }
    }
    
    private func saveChanges() {
        var updatedSong = song
        updatedSong.title = title
        updatedSong.artist = artist
        updatedSong.album = album
        updatedSong.genre = genre
        if let y = Int(year) {
             updatedSong.year = y
        }
        updatedSong.artworkData = artworkData
        
        song = updatedSong
        isPresented = false
    }
}
