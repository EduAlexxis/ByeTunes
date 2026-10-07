import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct DeviceLibraryBrowserView: View {
    static let exportFolderBookmarkKey = "deviceLibraryExportFolderBookmark"
    static var didLogExportBookmarkResolutionFailure = false

    enum LibraryMode: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case artists = "Artists"
        case albums = "Albums"
        case playlists = "Playlists"

        var id: String { rawValue }
    }

    enum SongSortOption: String, CaseIterable, Identifiable {
        case titleAscending = "Title"
        case artistAscending = "Artist"
        case albumAscending = "Album"
        case durationDescending = "Duration"
        case yearDescending = "Year"
        case fileSizeDescending = "File Size"

        var id: String { rawValue }
    }

    static let allGenresOption = "All Genres"

    struct ArtistEntry: Identifiable {
        let name: String
        let songs: [DeviceManager.ExportableSongInfo]
        var id: String { name }
    }

    struct AlbumEntry: Identifiable {
        let name: String
        let artist: String
        let albumPid: Int64
        let songs: [DeviceManager.ExportableSongInfo]
        var id: String { albumPid > 0 ? "pid:\(albumPid)" : "\(artist)|\(name)" }
    }
    
    struct PlaylistEntry: Identifiable {
        var name: String
        let pid: Int64
        var songs: [DeviceManager.ExportableSongInfo]
        var coverImage: UIImage? = nil
        var id: Int64 { pid }
    }

    @ObservedObject var manager: DeviceManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State var songs: [DeviceManager.ExportableSongInfo] = []
    @State var cachedGroupedSongs: [(key: String, songs: [DeviceManager.ExportableSongInfo])] = []
    @State var cachedArtistEntries: [ArtistEntry] = []
    @State var cachedAlbumEntries: [AlbumEntry] = []
    @State var playlists: [PlaylistEntry] = []
    @State var isSyncingPlaylists = false
    @State var showingNewPlaylistPrompt = false
    @State var showingSmartPlaylistBuilder = false
    @State var showingAddToPlaylistSheet = false
    @State var showingRenamePlaylistPrompt = false
    @State var renamePlaylistPid: Int64? = nil
    @State var renamePlaylistText = ""
    @State var searchText = ""
    @State var selectedIDs = Set<String>()
    @State var isSelectionMode = false
    @State var sortOption: SongSortOption = .titleAscending
    @State var selectedGenre: String = DeviceLibraryBrowserView.allGenresOption
    @State var showingBatchDeleteSongsConfirm = false
    @State var selectedPlaylistPids = Set<Int64>()
    @State var showingDeletePlaylistsConfirm = false
    @State var isLoading = true
    @State var isExporting = false
    @State var statusMessage = ""
    @State var showingFolderPicker = false
    @State var pendingExportAfterFolderSelection = false
    @State var pendingPlaylistExportAfterFolderSelection = false
    @State var artworkImages: [String: UIImage] = [:]
    @State var artworkDataCache: [String: Data] = [:]
    @State var artworkLoadingIDs = Set<String>()
    @State var queuedArtworkSongs: [DeviceManager.ExportableSongInfo] = []
    @State var queuedArtworkIDs = Set<String>()
    @State var libraryMode: LibraryMode = .songs
    @State var editingOriginalSong: DeviceManager.ExportableSongInfo?
    @State var editingDraftSong = SongMetadata(
        localURL: FileManager.default.temporaryDirectory.appendingPathComponent("device-library-edit.mp3"),
        title: "",
        artist: "",
        album: "",
        albumArtist: nil,
        genre: "Music",
        year: 0,
        durationMs: 0,
        fileSize: 0,
        remoteFilename: ""
    )
    @State var showingMetadataEditor = false
    @State var songPendingDeletion: DeviceManager.ExportableSongInfo?
    @State var songForQualityAnalysis: DeviceManager.ExportableSongInfo?
    @State var songForAudioReplace: DeviceManager.ExportableSongInfo?
    @State var editingAlbum: AlbumEntry?
    @State var addingSongsToAlbum: AlbumEntry?
    @State var showingAddToAlbumSheet = false
    @State var isApplyingAlbumEdit = false
    @State var addingToPlaylistPid: Int64? = nil

    let maxConcurrentArtworkLoads = 2

    var pageBackground: Color { Color(.systemGroupedBackground) }
    var panelBackground: Color { Color(.secondarySystemBackground) }
    var strongTextColor: Color { Color.primary }
    var mutedTextColor: Color { Color.secondary }
    var hairlineColor: Color { Color(.separator).opacity(colorScheme == .dark ? 0.55 : 0.85) }
    var controlFillColor: Color { Color(.systemBackground) }

    var filteredSongs: [DeviceManager.ExportableSongInfo] {
        let genreFiltered = selectedGenre == Self.allGenresOption
            ? songs
            : songs.filter { $0.genre == selectedGenre }

        let trimmed = normalizedSearchText
        guard !trimmed.isEmpty else { return genreFiltered }
        return genreFiltered.filter { song in
            let haystack = "\(song.artist) \(song.title) \(song.album)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var availableGenres: [String] {
        let genres = Set(
            songs.map { $0.genre.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return genres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var sortedFilteredSongsFlat: [DeviceManager.ExportableSongInfo] {
        switch sortOption {
        case .titleAscending:
            return filteredSongs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artistAscending:
            return filteredSongs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .albumAscending:
            return filteredSongs.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .durationDescending:
            return filteredSongs.sorted { $0.durationMs > $1.durationMs }
        case .yearDescending:
            return filteredSongs.sorted { $0.year > $1.year }
        case .fileSizeDescending:
            return filteredSongs.sorted { $0.fileSize > $1.fileSize }
        }
    }

    var selectedSongs: [DeviceManager.ExportableSongInfo] {
        songs.filter { selectedIDs.contains($0.id) }
    }

    var normalizedSearchText: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    var preferredExportFolder: URL? {
        Self.resolveBookmarkedFolder(forKey: Self.exportFolderBookmarkKey)
    }

    var hasSavedExportFolder: Bool {
        UserDefaults.standard.data(forKey: Self.exportFolderBookmarkKey) != nil
    }

    func computeGroupedSongs() -> [(key: String, songs: [DeviceManager.ExportableSongInfo])] {
        guard sortOption == .titleAscending else {
            return [(key: "", songs: sortedFilteredSongsFlat)]
        }

        let grouped = Dictionary(grouping: filteredSongs) { song in
            let first = song.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .uppercased()
                .first

            guard let first, first.isLetter else { return "#" }
            return String(first)
        }

        return grouped
            .map { (key: $0.key, songs: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { lhs, rhs in
                if lhs.key == "#" { return false }
                if rhs.key == "#" { return true }
                return lhs.key < rhs.key
            }
    }

    static let artistSplitRegex = try! NSRegularExpression(
        pattern: #"\s*(?:,|&|/|\bfeat\.?|\bft\.?|\bfeaturing\b|\bvs\.?|\bx\b|\by\b)\s*"#,
        options: [.caseInsensitive]
    )

    static func splitArtistNames(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let normalized = artistSplitRegex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "\u{1}")
        return normalized
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func computeArtistEntries() -> [ArtistEntry] {
        var songsByArtist: [String: [DeviceManager.ExportableSongInfo]] = [:]

        for song in filteredSongs {
            let names = Self.splitArtistNames(song.artist)
            for name in names.isEmpty ? ["Unknown Artist"] : names {
                songsByArtist[name, default: []].append(song)
            }
        }

        return songsByArtist
            .map { key, value in
                ArtistEntry(
                    name: key,
                    songs: value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func computeAlbumEntries() -> [AlbumEntry] {
        Dictionary(grouping: filteredSongs) { song -> String in
            if song.albumPid > 0 {
                return "pid:\(song.albumPid)"
            }
            let album = song.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Album" : song.album
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : song.artist
            return "\(artist)|\(album)"
        }
        .compactMap { _, value in
            guard let first = value.first else { return nil }
            return AlbumEntry(
                name: first.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Album" : first.album,
                artist: first.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Artist" : first.artist,
                albumPid: first.albumPid,
                songs: value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }
        .sorted {
            if $0.name == $1.name {
                return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        topBar

                        controlsSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(pageBackground)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if isLoading {
                                loadingState
                            } else if songs.isEmpty {
                                emptyState
                            } else {
                                songsSection
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 120)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingFolderPicker) {
            DocumentPicker(types: [.folder], asCopy: false) { url in
                handleExportFolderSelection(url: url)
            }
        }
        .sheet(isPresented: $showingMetadataEditor) {
            ManualMetadataEditor(
                song: Binding(
                    get: { editingDraftSong },
                    set: { editingDraftSong = $0 }
                ),
                isPresented: $showingMetadataEditor
            ) { updatedSong in
                guard let original = editingOriginalSong else { return }
                applyMetadataEdits(updatedSong, original: original)
            }
        }
        .sheet(item: $songForQualityAnalysis) { song in
            AudioQualityAnalysisView(manager: manager, song: song, artwork: artworkImages[song.id])
        }
        .sheet(item: $songForAudioReplace) { song in
            DocumentPicker(types: MusicView.supportedAudioTypes.filter { $0 != .folder }) { url in
                if let url {
                    replaceSongAudioFile(song, with: url)
                }
            }
        }
        .sheet(isPresented: $showingAddToPlaylistSheet) {
            AddToPlaylistView(
                playlists: playlists,
                onSelect: { playlistPid in
                    let selectedSongs = songs.filter { selectedIDs.contains($0.id) }
                    let actions: [DeviceManager.PlaylistAction] = [
                        .addSongs(containerPid: playlistPid, itemPids: selectedSongs.map(\.itemPid))
                    ]
                    applyPlaylistActions(actions)
                    isSelectionMode = false
                    selectedIDs.removeAll()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingAlbum) { album in
            AlbumMetadataEditor(
                album: album,
                initialArtworkData: album.songs.first.flatMap { artworkDataCache[$0.id] },
                isPresented: Binding(
                    get: { editingAlbum != nil },
                    set: { if !$0 { editingAlbum = nil } }
                )
            ) { artist, albumName, genre, year, artworkData, explicitRating in
                applyAlbumMetadataEdits(
                    to: album.songs,
                    artist: artist,
                    album: albumName,
                    genre: genre,
                    year: year,
                    artworkData: artworkData,
                    explicitRating: explicitRating
                )
            }
        }
        .sheet(item: $addingSongsToAlbum) { album in
            let candidateSongs = songs.filter { candidate in !album.songs.contains(where: { $0.id == candidate.id }) }
            AddSongsToAlbumSheet(
                album: album,
                candidateSongs: candidateSongs,
                suggestedSongs: suggestedSongs(for: album, in: candidateSongs)
            ) { selectedSongs in
                applyAlbumMetadataEdits(
                    to: selectedSongs,
                    artist: album.artist,
                    album: album.name,
                    genre: album.songs.first?.genre ?? "",
                    year: album.songs.first(where: { $0.year > 0 })?.year ?? 0,
                    artworkData: album.songs.first.flatMap { artworkDataCache[$0.id] },
                    explicitRating: nil
                )
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAddToAlbumSheet) {
            AddToAlbumView(
                albums: cachedAlbumEntries,
                onSelectAlbum: { album in
                    let selectedSongs = songs.filter { selectedIDs.contains($0.id) }
                    applyAlbumMetadataEdits(
                        to: selectedSongs,
                        artist: album.artist,
                        album: album.name,
                        genre: album.songs.first?.genre ?? "",
                        year: album.songs.first(where: { $0.year > 0 })?.year ?? 0,
                        artworkData: album.songs.first.flatMap { artworkDataCache[$0.id] },
                        explicitRating: nil
                    )
                    isSelectionMode = false
                    selectedIDs.removeAll()
                },
                onCreateNewAlbum: { artist, albumName, genre, year in
                    let selectedSongs = songs.filter { selectedIDs.contains($0.id) }
                    applyAlbumMetadataEdits(
                        to: selectedSongs,
                        artist: artist,
                        album: albumName,
                        genre: genre,
                        year: year,
                        artworkData: nil,
                        explicitRating: nil
                    )
                    isSelectionMode = false
                    selectedIDs.removeAll()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Delete Song?", isPresented: Binding(
            get: { songPendingDeletion != nil },
            set: { if !$0 { songPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                songPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                guard let song = songPendingDeletion else { return }
                songPendingDeletion = nil
                deleteSong(song)
            }
        } message: {
            Text(songPendingDeletion.map { "Delete \($0.title) from the device library?" } ?? "")
        }
        .alert("Delete Songs?", isPresented: $showingBatchDeleteSongsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedSongs()
            }
        } message: {
            Text("Delete \(selectedIDs.count) song\(selectedIDs.count == 1 ? "" : "s") from the device library? This can't be undone.")
        }
        .alert("Delete Playlists?", isPresented: $showingDeletePlaylistsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedPlaylists()
            }
        } message: {
            Text("Delete \(selectedPlaylistPids.count) playlist\(selectedPlaylistPids.count == 1 ? "" : "s") from the device? The songs themselves won't be removed.")
        }
        .onAppear {
            refreshSongs()
        }
        .onChange(of: libraryMode) { _ in
            prefetchArtworkForCurrentMode()
        }
        .onChange(of: searchText) { _ in
            recomputeLibraryGroupings()
        }
        .onChange(of: sortOption) { _ in
            recomputeLibraryGroupings()
        }
        .onChange(of: selectedGenre) { _ in
            recomputeLibraryGroupings()
        }
    }
}
