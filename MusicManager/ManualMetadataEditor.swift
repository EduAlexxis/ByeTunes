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
    @State private var trackNumber: String = ""
    @State private var lyrics: String = ""
    @State private var isExplicit: Bool = false
    
    @State private var artworkItem: PhotosPickerItem?
    @State private var artworkData: Data?
    
    @State private var showingSearchSheet = false
    @State private var showingLyricsSearchSheet = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, artist, album, genre, year, trackNumber
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
                
                // Fetch Metadata button
                Section {
                    Button {
                        showingSearchSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.accentColor)
                            Text("Search Metadata")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(uiColor: .tertiaryLabel))
                        }
                    }
                } footer: {
                    Text("Search iTunes or Deezer to auto-fill metadata fields")
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
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Track Number")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("Track #", text: $trackNumber)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .trackNumber)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle(isOn: $isExplicit) {
                        HStack(spacing: 8) {
                            Text("🅴")
                                .font(.caption.weight(.black))
                                .foregroundColor(.red)
                            Text("Explicit")
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Details")
                }
                
                Section {
                    TextEditor(text: $lyrics)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    HStack {
                        Text("Lyrics")
                        Spacer()
                        if !lyrics.isEmpty {
                            Text("\(lyrics.components(separatedBy: .newlines).count) lines")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            showingLyricsSearchSheet = true
                        } label: {
                            Image(systemName: "text.magnifyingglass")
                        }
                        .disabled(title.isEmpty || artist.isEmpty)
                        .padding(.leading, 8)
                    }
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
                loadFieldsFromSong()
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
            .sheet(isPresented: $showingSearchSheet, onDismiss: {
                // Refresh fields from the (possibly updated) song binding
                loadFieldsFromSong()
            }) {
                iTunesSearchSheet(song: $song, isPresented: $showingSearchSheet)
            }
            .sheet(isPresented: $showingLyricsSearchSheet) {
                LyricsSearchSheet(
                    lyrics: $lyrics,
                    isPresented: $showingLyricsSearchSheet,
                    initialTitle: title,
                    initialArtist: artist
                )
            }
        }
    }
    
    private func loadFieldsFromSong() {
        title = song.title
        artist = song.artist
        album = song.album
        genre = song.genre
        year = String(song.year)
        if let track = song.trackNumber {
            trackNumber = String(track)
        }
        lyrics = song.lyrics ?? ""
        artworkData = song.artworkData
        isExplicit = song.explicitRating > 0
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
        if let t = Int(trackNumber) {
            updatedSong.trackNumber = t
        } else {
            updatedSong.trackNumber = nil
        }
        updatedSong.lyrics = lyrics.isEmpty ? nil : lyrics
        updatedSong.artworkData = artworkData
        updatedSong.explicitRating = isExplicit ? 1 : 0
        
        song = updatedSong
        isPresented = false
    }
}
