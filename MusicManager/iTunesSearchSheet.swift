import SwiftUI

struct iTunesSearchSheet: View {
    @Binding var song: SongMetadata
    @Binding var isPresented: Bool
    
    @AppStorage("metadataSource") private var metadataSource = "local"
    
    @State private var searchQuery: String = ""
    @State private var itunesResults: [iTunesSong] = []
    @State private var deezerResults: [DeezerSong] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (Same as before)
                HStack {
                    Text("Select Match")
                        .font(.system(size: 24, weight: .bold))
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding([.top, .horizontal], 20)
                .padding(.bottom, 10)
                
                // Search Bar (Same as before)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search \(metadataSource == "deezer" ? "Deezer" : "iTunes (\(UserDefaults.standard.string(forKey: "storeRegion") ?? "US"))")...", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Content
                if isLoading {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching \(metadataSource == "deezer" ? "Deezer" : "iTunes (\(UserDefaults.standard.string(forKey: "storeRegion") ?? "US"))")...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if (metadataSource == "deezer" ? deezerResults.isEmpty : itunesResults.isEmpty) {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(Color(.systemGray4))
                        Text("No matching songs found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if metadataSource == "deezer" {
                                ForEach(deezerResults) { match in
                                    Button {
                                        applyDeezerMatch(match)
                                    } label: {
                                        DeezerRow(match: match)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                ForEach(itunesResults) { match in
                                    Button {
                                        applyItunesMatch(match)
                                    } label: {
                                        iTunesRow(match: match)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .onAppear {
            if searchQuery.isEmpty {
                searchQuery = "\(song.artist) \(song.title)"
                performSearch()
            }
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            if metadataSource == "deezer" {
                 let results = await SongMetadata.searchDeezer(query: searchQuery)
                 await MainActor.run {
                     self.deezerResults = results
                     self.isLoading = false
                     if results.isEmpty { self.errorMessage = nil }
                 }
            } else {
                 let results = await SongMetadata.searchiTunes(query: searchQuery)
                 await MainActor.run {
                     self.itunesResults = results
                     self.isLoading = false
                     if results.isEmpty { self.errorMessage = nil }
                 }
            }
        }
    }
    
    private func applyItunesMatch(_ match: iTunesSong) {
        isLoading = true
        Task {
            let updatedSong = await SongMetadata.applyiTunesMatch(match, to: song)
            await MainActor.run {
                self.song = updatedSong
                self.isLoading = false
                self.isPresented = false
            }
        }
    }
    
    private func applyDeezerMatch(_ match: DeezerSong) {
        isLoading = true
        Task {
            let updatedSong = await SongMetadata.applyDeezerMatch(match, to: song)
            await MainActor.run {
                self.song = updatedSong
                self.isLoading = false
                self.isPresented = false
            }
        }
    }
}

// Subviews
struct iTunesRow: View {
    let match: iTunesSong
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: match.artworkUrl100 ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(uiColor: .systemGray5)
                    .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
            }
            .frame(width: 56, height: 56).cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(match.trackName ?? "Unknown Title").font(.headline).foregroundColor(.primary).lineLimit(1)
                Text(match.artistName ?? "Unknown Artist").font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    if let album = match.collectionName { Text(album).lineLimit(1) }
                    if let year = match.releaseDate?.prefix(4) { Text("• \(String(year))") }
                }.font(.caption).foregroundColor(.secondary.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct DeezerRow: View {
    let match: DeezerSong
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: match.album.cover_xl)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(uiColor: .systemGray5)
                    .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
            }
            .frame(width: 56, height: 56).cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(match.title).font(.headline).foregroundColor(.primary).lineLimit(1)
                Text(match.artist.name).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                Text(match.album.title).font(.caption).foregroundColor(.secondary.opacity(0.8)).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}
