import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct DeviceLibraryBrowserView: View {
    private static let exportFolderBookmarkKey = "deviceLibraryExportFolderBookmark"
    private static var didLogExportBookmarkResolutionFailure = false

    private enum LibraryMode: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case artists = "Artists"
        case albums = "Albums"
        case playlists = "Playlists"

        var id: String { rawValue }
    }

    private enum SongSortOption: String, CaseIterable, Identifiable {
        case titleAscending = "Title"
        case artistAscending = "Artist"
        case albumAscending = "Album"
        case durationDescending = "Duration"
        case yearDescending = "Year"
        case fileSizeDescending = "File Size"

        var id: String { rawValue }
    }

    private static let allGenresOption = "All Genres"

    private struct ArtistEntry: Identifiable {
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var songs: [DeviceManager.ExportableSongInfo] = []
    @State private var cachedGroupedSongs: [(key: String, songs: [DeviceManager.ExportableSongInfo])] = []
    @State private var cachedArtistEntries: [ArtistEntry] = []
    @State private var cachedAlbumEntries: [AlbumEntry] = []
    @State private var playlists: [PlaylistEntry] = []
    @State private var isSyncingPlaylists = false
    @State private var showingNewPlaylistPrompt = false
    @State private var showingSmartPlaylistBuilder = false
    @State private var showingAddToPlaylistSheet = false
    @State private var showingRenamePlaylistPrompt = false
    @State private var renamePlaylistPid: Int64? = nil
    @State private var renamePlaylistText = ""
    @State private var searchText = ""
    @State private var selectedIDs = Set<String>()
    @State private var isSelectionMode = false
    @State private var sortOption: SongSortOption = .titleAscending
    @State private var selectedGenre: String = DeviceLibraryBrowserView.allGenresOption
    @State private var showingBatchDeleteSongsConfirm = false
    @State private var selectedPlaylistPids = Set<Int64>()
    @State private var showingDeletePlaylistsConfirm = false
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var statusMessage = ""
    @State private var showingFolderPicker = false
    @State private var pendingExportAfterFolderSelection = false
    @State private var pendingPlaylistExportAfterFolderSelection = false
    @State private var artworkImages: [String: UIImage] = [:]
    @State private var artworkDataCache: [String: Data] = [:]
    @State private var artworkLoadingIDs = Set<String>()
    @State private var queuedArtworkSongs: [DeviceManager.ExportableSongInfo] = []
    @State private var queuedArtworkIDs = Set<String>()
    @State private var libraryMode: LibraryMode = .songs
    @State private var editingOriginalSong: DeviceManager.ExportableSongInfo?
    @State private var editingDraftSong = SongMetadata(
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
    @State private var showingMetadataEditor = false
    @State private var songPendingDeletion: DeviceManager.ExportableSongInfo?
    @State private var songForQualityAnalysis: DeviceManager.ExportableSongInfo?
    @State private var songForAudioReplace: DeviceManager.ExportableSongInfo?
    @State private var editingAlbum: AlbumEntry?
    @State private var addingSongsToAlbum: AlbumEntry?
    @State private var showingAddToAlbumSheet = false
    @State private var isApplyingAlbumEdit = false

    private let maxConcurrentArtworkLoads = 2

    private var pageBackground: Color { Color(.systemGroupedBackground) }
    private var panelBackground: Color { Color(.secondarySystemBackground) }
    private var strongTextColor: Color { Color.primary }
    private var mutedTextColor: Color { Color.secondary }
    private var hairlineColor: Color { Color(.separator).opacity(colorScheme == .dark ? 0.55 : 0.85) }
    private var controlFillColor: Color { Color(.systemBackground) }

    private var filteredSongs: [DeviceManager.ExportableSongInfo] {
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

    private var availableGenres: [String] {
        let genres = Set(
            songs.map { $0.genre.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return genres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var sortedFilteredSongsFlat: [DeviceManager.ExportableSongInfo] {
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

    private var selectedSongs: [DeviceManager.ExportableSongInfo] {
        songs.filter { selectedIDs.contains($0.id) }
    }

    private var normalizedSearchText: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var preferredExportFolder: URL? {
        Self.resolveBookmarkedFolder(forKey: Self.exportFolderBookmarkKey)
    }

    private var hasSavedExportFolder: Bool {
        UserDefaults.standard.data(forKey: Self.exportFolderBookmarkKey) != nil
    }

    private func computeGroupedSongs() -> [(key: String, songs: [DeviceManager.ExportableSongInfo])] {
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

    private func computeArtistEntries() -> [ArtistEntry] {
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

    private func computeAlbumEntries() -> [AlbumEntry] {
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

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                topBarIconButton(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                refreshSongs()
            } label: {
                topBarIconButton(systemName: "arrow.clockwise", showsProgress: isLoading)
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isExporting)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryModeSwitcher

            if libraryMode == .playlists {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        actionCapsule(
                            title: isSelectionMode ? "Done" : "Select",
                            systemImage: "checklist",
                            isPrimary: false,
                            isDisabled: isLoading || playlists.isEmpty
                        ) {
                            isSelectionMode.toggle()
                            if !isSelectionMode { selectedPlaylistPids.removeAll() }
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: allPlaylistsSelected ? "Clear All" : "Select All",
                                systemImage: allPlaylistsSelected ? "checkmark.circle.fill" : "checklist",
                                isPrimary: false,
                                isDisabled: playlists.isEmpty
                            ) {
                                toggleAllPlaylistsSelection()
                            }

                            actionCapsule(
                                title: isExporting ? "Exporting..." : "Export",
                                systemImage: "square.and.arrow.up",
                                isPrimary: false,
                                isDisabled: selectedPlaylistPids.isEmpty || isLoading || isExporting
                            ) {
                                exportSelectedPlaylists()
                            }

                            actionCapsule(
                                title: "Delete",
                                systemImage: "trash",
                                isPrimary: false,
                                isDestructive: true,
                                isDisabled: selectedPlaylistPids.isEmpty
                            ) {
                                showingDeletePlaylistsConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else if libraryMode == .songs {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        actionCapsule(
                            title: isSelectionMode ? "Done" : "Select",
                            systemImage: "checklist",
                            isPrimary: false,
                            isDisabled: isLoading || filteredSongs.isEmpty || isExporting
                        ) {
                            if isSelectionMode {
                                isSelectionMode = false
                            } else {
                                isSelectionMode = true
                            }
                        }

                        actionCapsule(
                            title: isSelectionMode ? (allFilteredSongsSelected ? "Clear All" : "Select All") : "Folder",
                            systemImage: isSelectionMode ? (allFilteredSongsSelected ? "checkmark.circle.fill" : "checklist") : "folder",
                            isPrimary: false,
                            isDisabled: isExporting || (isSelectionMode && filteredSongs.isEmpty)
                        ) {
                            if isSelectionMode {
                                toggleVisibleSelection()
                            } else {
                                pendingExportAfterFolderSelection = false
                                showingFolderPicker = true
                            }
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: "Add to Playlist",
                                systemImage: "text.badge.plus",
                                isPrimary: false,
                                isDisabled: selectedIDs.isEmpty || playlists.isEmpty
                            ) {
                                showingAddToPlaylistSheet = true
                            }

                            actionCapsule(
                                title: "Add to Album",
                                systemImage: "square.stack.badge.plus",
                                isPrimary: false,
                                isDisabled: selectedIDs.isEmpty
                            ) {
                                showingAddToAlbumSheet = true
                            }
                        } else {
                            sortMenu

                            if availableGenres.count > 1 {
                                genreFilterMenu
                            }
                        }

                        actionCapsule(
                            title: isExporting ? "Exporting..." : "Export",
                            systemImage: "square.and.arrow.up",
                            isPrimary: false,
                            isDisabled: selectedIDs.isEmpty || isLoading || isExporting
                        ) {
                            exportSelectedSongs()
                        }

                        if isSelectionMode {
                            actionCapsule(
                                title: "Delete",
                                systemImage: "trash",
                                isPrimary: false,
                                isDestructive: true,
                                isDisabled: selectedIDs.isEmpty || isLoading || isExporting
                            ) {
                                showingBatchDeleteSongsConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            searchField

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(2)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(mutedTextColor)

            TextField("Search on-device songs", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(strongTextColor)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(mutedTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(hairlineColor, lineWidth: 1)
                )
        )
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading library...")
                .font(.subheadline)
                .foregroundStyle(mutedTextColor)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.title3.weight(.semibold))
                .foregroundStyle(strongTextColor)

            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(mutedTextColor)
                Text("No Songs Found")
                    .font(.headline)
                    .foregroundStyle(strongTextColor)
                Text("Could not read any exportable songs from the device library.")
                    .font(.subheadline)
                    .foregroundStyle(mutedTextColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(24)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(searchText.isEmpty ? libraryMode.rawValue : "Results")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(strongTextColor)
                Spacer()
                Text(summaryCountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(mutedTextColor)
            }

            switch libraryMode {
            case .songs:
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(cachedGroupedSongs, id: \.key) { section in
                        if !section.key.isEmpty {
                            Text(section.key)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(strongTextColor)
                                .padding(.top, section.key == cachedGroupedSongs.first?.key ? 2 : 18)
                                .padding(.bottom, 8)
                        }

                        ForEach(Array(section.songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song)
                            if index < section.songs.count - 1 {
                                Divider()
                                    .overlay(hairlineColor)
                                    .padding(.leading, 64)
                            }
                        }
                    }
                }
                .id(cachedGroupedSongs.count)
            case .artists:
                LazyVStack(spacing: 0) {
                    ForEach(Array(cachedArtistEntries.enumerated()), id: \.element.id) { index, artist in
                        artistRow(artist)
                        if index < cachedArtistEntries.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
                .id(cachedArtistEntries.count)
            case .albums:
                LazyVStack(spacing: 0) {
                    ForEach(Array(cachedAlbumEntries.enumerated()), id: \.element.id) { index, album in
                        albumRow(album)
                        if index < cachedAlbumEntries.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
                .id(cachedAlbumEntries.count)
            case .playlists:
                playlistListView()
            }
        }
    }

    private func songRow(_ song: DeviceManager.ExportableSongInfo) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                artworkView(for: song)

                if isSelectionMode {
                    Circle()
                        .fill(selectedIDs.contains(song.id) ? Color(red: 1.0, green: 0.27, blue: 0.42) : Color.black.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedIDs.contains(song.id)
                                    ? Color(red: 1.0, green: 0.27, blue: 0.42)
                                    : Color.white.opacity(0.22),
                                    lineWidth: 1.5
                                )
                        )
                        .overlay(
                            Image(systemName: selectedIDs.contains(song.id) ? "checkmark" : "circle.fill")
                                .font(.system(size: selectedIDs.contains(song.id) ? 10 : 7, weight: .bold))
                                .foregroundStyle(selectedIDs.contains(song.id) ? .white : Color.clear)
                        )
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    if isSelectionMode && selectedIDs.contains(song.id) {
                        Text("READY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.27, blue: 0.42).opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(1)
                Text(song.album)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear {
            loadArtworkIfNeeded(for: song)
        }
        .onTapGesture {
            if isSelectionMode {
                toggleSelection(song.id)
            } else {
                songForQualityAnalysis = song
            }
        }
        .contextMenu {
            if !isSelectionMode {
                Button {
                    beginEditing(song)
                } label: {
                    Label("Edit Metadata", systemImage: "pencil")
                }

                Button {
                    songForAudioReplace = song
                } label: {
                    Label("Replace Audio File", systemImage: "waveform.badge.exclamationmark")
                }

                Button(role: .destructive) {
                    songPendingDeletion = song
                } label: {
                    Label("Delete Song", systemImage: "trash")
                }
            }
        }
    }

    private func artistRow(_ artist: ArtistEntry) -> some View {
        NavigationLink {
            groupedSongListView(
                title: artist.name,
                subtitle: "\(artist.songs.count) song\(artist.songs.count == 1 ? "" : "s")",
                songs: artist.songs
            )
        } label: {
            HStack(spacing: 10) {
                artistArtworkView(artist)

                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text("\(artist.songs.count) song\(artist.songs.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mutedTextColor.opacity(0.8))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if let firstSong = artist.songs.first {
                loadArtworkIfNeeded(for: firstSong)
            }
        }
    }

    private func albumRow(_ album: AlbumEntry) -> some View {
        NavigationLink {
            groupedSongListView(
                title: album.name,
                subtitle: album.artist,
                songs: album.songs,
                onEdit: { editingAlbum = album },
                onAddSongs: { addingSongsToAlbum = album }
            )
        } label: {
            HStack(spacing: 10) {
                albumArtworkView(album)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor)
                        .lineLimit(1)
                    Text("\(album.songs.count) track\(album.songs.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(mutedTextColor.opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mutedTextColor.opacity(0.8))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            if let firstSong = album.songs.first {
                loadArtworkIfNeeded(for: firstSong)
            }
        }
    }

    private func groupedSongListView(
        title: String,
        subtitle: String,
        songs: [DeviceManager.ExportableSongInfo],
        onEdit: (() -> Void)? = nil,
        onAddSongs: (() -> Void)? = nil
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(strongTextColor)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                    Text("\(songs.count) song\(songs.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                HStack(spacing: 12) {
                    Button {
                        if isSelectionMode {
                            isSelectionMode = false
                        } else {
                            isSelectionMode = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14, weight: .semibold))
                            Text(isSelectionMode ? "Done" : "Select")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(strongTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Capsule()
                                .fill(controlFillColor)
                                .overlay(
                                    Capsule()
                                        .stroke(hairlineColor, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    if isSelectionMode {
                        Button {
                            selectAll(in: songs)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: areAllSelected(in: songs) ? "checkmark.circle.fill" : "checklist")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(areAllSelected(in: songs) ? "Clear All" : "Select All")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let onEdit {
                        Button(action: onEdit) {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Edit")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let onAddSongs {
                        Button(action: onAddSongs) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Add Songs")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(strongTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule()
                                    .fill(controlFillColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(hairlineColor, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        songRow(song)
                        if index < songs.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            for song in songs.prefix(18) {
                loadArtworkIfNeeded(for: song)
            }
        }
    }

    @ViewBuilder
    private func artworkView(for song: DeviceManager.ExportableSongInfo) -> some View {
        if let image = artworkImages[song.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            panelBackground.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(mutedTextColor)
                )
        }
    }

    @ViewBuilder
    private func artistArtworkView(_ artist: ArtistEntry) -> some View {
        if let firstSong = artist.songs.first {
            artworkView(for: firstSong)
        }
    }

    @ViewBuilder
    private func albumArtworkView(_ album: AlbumEntry) -> some View {
        if let firstSong = album.songs.first {
            artworkView(for: firstSong)
        }
    }

    private func topBarIconButton(systemName: String, showsProgress: Bool = false) -> some View {
        ZStack {
            Circle()
                .fill(controlFillColor)
                .frame(width: 44, height: 44)

            if showsProgress {
                ProgressView()
                    .tint(strongTextColor)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(strongTextColor)
            }
        }
        .compositingGroup()
    }

    private var libraryModeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(LibraryMode.allCases) { mode in
                Button {
                    libraryMode = mode
                } label: {
                    VStack(spacing: 6) {
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(libraryMode == mode ? strongTextColor : mutedTextColor)

                        Rectangle()
                            .fill(libraryMode == mode ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func actionCapsule(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDestructive: Bool = false,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isDestructive ? Color(red: 1.0, green: 0.27, blue: 0.42) : strongTextColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(hairlineColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SongSortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    if sortOption == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sort: \(sortOption.rawValue)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(strongTextColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(hairlineColor, lineWidth: 1)
                    )
            )
        }
        .disabled(isLoading || filteredSongs.isEmpty)
        .opacity(isLoading || filteredSongs.isEmpty ? 0.45 : 1)
    }

    private var genreFilterMenu: some View {
        Menu {
            Button {
                selectedGenre = Self.allGenresOption
            } label: {
                if selectedGenre == Self.allGenresOption {
                    Label(Self.allGenresOption, systemImage: "checkmark")
                } else {
                    Text(Self.allGenresOption)
                }
            }

            ForEach(availableGenres, id: \.self) { genre in
                Button {
                    selectedGenre = genre
                } label: {
                    if selectedGenre == genre {
                        Label(genre, systemImage: "checkmark")
                    } else {
                        Text(genre)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(selectedGenre == Self.allGenresOption ? "Genre" : selectedGenre)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selectedGenre == Self.allGenresOption ? strongTextColor : Color.accentColor)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(controlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(selectedGenre == Self.allGenresOption ? hairlineColor : Color.accentColor, lineWidth: 1)
                    )
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.45 : 1)
    }

    private var summaryCountText: String {
        switch libraryMode {
        case .songs:
            return "\(filteredSongs.count)"
        case .artists:
            return "\(cachedArtistEntries.count)"
        case .albums:
            return "\(cachedAlbumEntries.count)"
        case .playlists:
            return "\(playlists.count)"
        }
    }

    private var allFilteredSongsSelected: Bool {
        let visibleIDs = Set(filteredSongs.map(\.id))
        return !visibleIDs.isEmpty && selectedIDs.isSuperset(of: visibleIDs)
    }

    private var allPlaylistsSelected: Bool {
        let allPids = Set(playlists.map(\.pid))
        return !allPids.isEmpty && selectedPlaylistPids.isSuperset(of: allPids)
    }

    private func toggleAllPlaylistsSelection() {
        let allPids = Set(playlists.map(\.pid))
        guard !allPids.isEmpty else { return }
        if selectedPlaylistPids.isSuperset(of: allPids) {
            selectedPlaylistPids.subtract(allPids)
        } else {
            selectedPlaylistPids.formUnion(allPids)
        }
    }

    private func togglePlaylistSelection(_ pid: Int64) {
        if selectedPlaylistPids.contains(pid) {
            selectedPlaylistPids.remove(pid)
        } else {
            selectedPlaylistPids.insert(pid)
        }
    }

    private func deleteSelectedPlaylists() {
        guard !selectedPlaylistPids.isEmpty else { return }
        applyPlaylistActions(selectedPlaylistPids.map { .delete(containerPid: $0) })
        selectedPlaylistPids.removeAll()
        isSelectionMode = false
    }

    private func loadArtworkIfNeeded(for song: DeviceManager.ExportableSongInfo) {
        guard artworkImages[song.id] == nil else { return }
        guard !artworkLoadingIDs.contains(song.id) else { return }
        guard !queuedArtworkIDs.contains(song.id) else { return }
        guard let relativePath = song.artworkRelativePath, !relativePath.isEmpty else { return }

        queuedArtworkSongs.append(song)
        queuedArtworkIDs.insert(song.id)
        processArtworkQueueIfNeeded()
    }

    private func processArtworkQueueIfNeeded() {
        while artworkLoadingIDs.count < maxConcurrentArtworkLoads, !queuedArtworkSongs.isEmpty {
            let song = queuedArtworkSongs.removeFirst()
            queuedArtworkIDs.remove(song.id)

            guard artworkImages[song.id] == nil else { continue }
            guard let relativePath = song.artworkRelativePath, !relativePath.isEmpty else { continue }

            artworkLoadingIDs.insert(song.id)
            let remotePath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
            manager.downloadFileFromDevice(remotePath: remotePath) { data in
                let image = data.flatMap { Self.downsampledArtworkImage(from: $0, maxPixelSize: 120) }
                DispatchQueue.main.async {
                    if let image {
                        artworkImages[song.id] = image
                    }
                    if let data {
                        artworkDataCache[song.id] = data
                    }
                    artworkLoadingIDs.remove(song.id)
                    processArtworkQueueIfNeeded()
                }
            }
        }
    }

    private func prefetchArtworkForCurrentMode() {
        let seeds: [DeviceManager.ExportableSongInfo]
        switch libraryMode {
        case .songs:
            seeds = Array(filteredSongs.prefix(18))
        case .artists:
            seeds = cachedArtistEntries.prefix(18).compactMap { $0.songs.first }
        case .albums:
            seeds = cachedAlbumEntries.prefix(18).compactMap { $0.songs.first }
        case .playlists:
            seeds = playlists.prefix(18).compactMap { $0.songs.first }
        }

        for song in seeds {
            loadArtworkIfNeeded(for: song)
        }
    }

    private static func downsampledArtworkImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleVisibleSelection() {
        let visibleIDs = Set(filteredSongs.map(\.id))
        let selectedVisibleCount = selectedIDs.intersection(visibleIDs).count
        if selectedVisibleCount == visibleIDs.count && !visibleIDs.isEmpty {
            filteredSongs.forEach { selectedIDs.remove($0.id) }
        } else {
            filteredSongs.forEach { selectedIDs.insert($0.id) }
        }
    }

    private func areAllSelected(in songs: [DeviceManager.ExportableSongInfo]) -> Bool {
        let ids = Set(songs.map(\.id))
        return !ids.isEmpty && selectedIDs.isSuperset(of: ids)
    }

    private func selectAll(in songs: [DeviceManager.ExportableSongInfo]) {
        let ids = Set(songs.map(\.id))
        guard !ids.isEmpty else { return }

        if selectedIDs.isSuperset(of: ids) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    private func recomputeLibraryGroupings() {
        cachedGroupedSongs = computeGroupedSongs()
        cachedArtistEntries = computeArtistEntries()
        cachedAlbumEntries = computeAlbumEntries()
    }

    private func refreshSongs(completion: (() -> Void)? = nil) {
        isLoading = true
        statusMessage = ""
        manager.fetchExportableSongs { result in
            DispatchQueue.main.async {
                songs = result
                if selectedGenre != Self.allGenresOption && !availableGenres.contains(selectedGenre) {
                    selectedGenre = Self.allGenresOption
                }
                recomputeLibraryGroupings()
                selectedIDs = selectedIDs.intersection(Set(result.map(\.id)))
                if result.isEmpty {
                    isSelectionMode = false
                }

                manager.fetchExportablePlaylists { pList in
                    DispatchQueue.main.async {
                        print("[Playlist Debug] Fetched playlists: \(pList)")
                        self.playlists = pList.map { p in
                            let pSongs = p.songPids.compactMap { pid in
                                result.first(where: { $0.itemPid == pid })
                            }
                            print("[Playlist Debug] Playlist '\(p.name)' matched \(pSongs.count) out of \(p.songPids.count) PIDs.")
                            return PlaylistEntry(name: p.name, pid: p.pid, songs: pSongs)
                        }
                        isLoading = false
                        statusMessage = result.isEmpty ? "No songs found on the device." : ""
                        queuedArtworkSongs.removeAll()
                        queuedArtworkIDs.removeAll()
                        artworkLoadingIDs.removeAll()
                        prefetchArtworkForCurrentMode()
                        loadPlaylistCovers(for: pList)
                        completion?()
                    }
                }
            }
        }
    }

    private func loadPlaylistCovers(for pList: [(name: String, pid: Int64, songPids: [Int64], coverRelativePath: String?)]) {
        for p in pList {
            guard let relativePath = p.coverRelativePath else { continue }
            manager.downloadPlaylistCoverArtwork(relativePath: relativePath) { data in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if let idx = playlists.firstIndex(where: { $0.pid == p.pid }) {
                        playlists[idx].coverImage = image
                    }
                }
            }
        }
    }

    private func playlistRowContent(_ playlist: PlaylistEntry) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .frame(width: 48, height: 48)
                if let cover = playlist.coverImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(mutedTextColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(playlist.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(strongTextColor)
                    if SmartPlaylistStore.record(forPid: playlist.pid) != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    }
                }
                Text("\(playlist.songs.count) songs")
                    .font(.subheadline)
                    .foregroundStyle(mutedTextColor)
            }
            Spacer()
            if isSelectionMode {
                if selectedPlaylistPids.contains(playlist.pid) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                } else {
                    Circle()
                        .stroke(mutedTextColor, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func playlistListView() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Button {
                showingNewPlaylistPrompt = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("New Playlist")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().overlay(hairlineColor).padding(.leading, 64)

            Button {
                showingSmartPlaylistBuilder = true
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("New Smart Playlist")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider().overlay(hairlineColor).padding(.leading, 64)

            ForEach(playlists) { playlist in
                Group {
                    if isSelectionMode {
                        Button {
                            togglePlaylistSelection(playlist.pid)
                        } label: {
                            playlistRowContent(playlist)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: playlistDetailView(playlist)) {
                            playlistRowContent(playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if SmartPlaylistStore.record(forPid: playlist.pid) != nil {
                                Button {
                                    refreshSmartPlaylist(playlist)
                                } label: {
                                    Label("Refresh Smart Playlist", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            Button(role: .destructive) {
                                applyPlaylistActions([.delete(containerPid: playlist.pid)])
                            } label: {
                                Label("Delete Playlist", systemImage: "trash")
                            }
                        }
                    }
                }

                Divider()
                    .overlay(hairlineColor)
                    .padding(.leading, 64)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingNewPlaylistPrompt) {
            PlaylistNamingView(title: "New Playlist", icon: "music.note.list", iconTint: Color(red: 1.0, green: 0.27, blue: 0.42)) { name, coverImageData in
                guard !name.isEmpty else { return }
                applyPlaylistActions([.create(name: name)]) {
                    if let coverImageData, let matched = playlists.first(where: { $0.name == name }) {
                        applyPlaylistActions([.setCoverArtwork(containerPid: matched.pid, imageData: coverImageData)])
                    }
                }
            }
        }
        .sheet(isPresented: $showingSmartPlaylistBuilder) {
            SmartPlaylistBuilderView(songs: songs) { name, songPids, rule, coverImageData in
                applyPlaylistActions([.createWithSongs(name: name, songPids: songPids)]) {
                    guard let matched = playlists.first(where: { $0.name == name }) else { return }
                    SmartPlaylistStore.save(SmartPlaylistRecord(name: matched.name, containerPid: matched.pid, rule: rule))
                    if let coverImageData {
                        applyPlaylistActions([.setCoverArtwork(containerPid: matched.pid, imageData: coverImageData)])
                    }
                }
            }
        }
    }

    private func refreshSmartPlaylist(_ playlist: PlaylistEntry) {
        guard let record = SmartPlaylistStore.record(forPid: playlist.pid) else { return }
        let matchingPids = Set(record.rule.matchingSongs(in: songs).map(\.itemPid))
        let currentPids = Set(playlist.songs.map(\.itemPid))
        guard matchingPids != currentPids else { return }

        var actions: [DeviceManager.PlaylistAction] = []
        let toAdd = Array(matchingPids.subtracting(currentPids))
        if !toAdd.isEmpty {
            actions.append(.addSongs(containerPid: playlist.pid, itemPids: toAdd))
        }
        for pid in currentPids.subtracting(matchingPids) {
            actions.append(.removeSong(containerPid: playlist.pid, itemPid: pid))
        }
        applyPlaylistActions(actions)
    }

    private func applyPlaylistActions(_ actions: [DeviceManager.PlaylistAction], onSynced: (() -> Void)? = nil) {
        guard !actions.isEmpty else { return }

        for action in actions {
            switch action {
            case .create(let name):
                let newId = Int64.random(in: 1000...9000)
                playlists.append(PlaylistEntry(name: name, pid: newId, songs: []))
            case .createWithSongs(let name, let songPids):
                let newId = Int64.random(in: 1000...9000)
                let newSongs = songPids.compactMap { pid in songs.first(where: { $0.itemPid == pid }) }
                playlists.append(PlaylistEntry(name: name, pid: newId, songs: newSongs))
            case .delete(let containerPid):
                playlists.removeAll { $0.pid == containerPid }
                SmartPlaylistStore.remove(forPid: containerPid)
            case .rename(let containerPid, let newName):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].name = newName
                }
            case .removeSong(let containerPid, let itemPid):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].songs.removeAll { $0.itemPid == itemPid }
                }
            case .reorder(let containerPid, let orderedItemPids):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    let sortedSongs = orderedItemPids.compactMap { pid in
                        playlists[idx].songs.first(where: { $0.itemPid == pid })
                    }
                    if sortedSongs.count == playlists[idx].songs.count {
                        playlists[idx].songs = sortedSongs
                    }
                }
            case .addSongs(let containerPid, let itemPids):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    let newSongs = itemPids.compactMap { pid in songs.first(where: { $0.itemPid == pid }) }
                    playlists[idx].songs.append(contentsOf: newSongs)
                }
            case .setCoverArtwork(let containerPid, let imageData):
                if let idx = playlists.firstIndex(where: { $0.pid == containerPid }) {
                    playlists[idx].coverImage = UIImage(data: imageData)
                }
            }
        }
        
        isSyncingPlaylists = true
        manager.applyPlaylistEdits(actions: actions) { success, error in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isSyncingPlaylists = false
                if success {
                    refreshSongs {
                        onSynced?()
                    }
                } else {
                    statusMessage = "Sync failed: \(error)"
                }
            }
        }
    }
    
    @State private var addingToPlaylistPid: Int64? = nil

    private func playlistDetailView(_ playlist: PlaylistEntry) -> some View {
        let current = playlists.first(where: { $0.pid == playlist.pid }) ?? playlist

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(current.name)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(strongTextColor)
                            .lineLimit(1)

                        Button {
                            renamePlaylistPid = current.pid
                            renamePlaylistText = current.name
                            showingRenamePlaylistPrompt = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(mutedTextColor)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(current.songs.count) song\(current.songs.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mutedTextColor)
                }

                HStack(spacing: 12) {
                    Button {
                        addingToPlaylistPid = current.pid
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Add Songs")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(strongTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Capsule()
                                .fill(controlFillColor)
                                .overlay(
                                    Capsule()
                                        .stroke(hairlineColor, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(current.songs.enumerated()), id: \.element.id) { index, song in
                        playlistSongRow(song, playlist: current)
                        if index < current.songs.count - 1 {
                            Divider()
                                .overlay(hairlineColor)
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(pageBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: Binding(
            get: { addingToPlaylistPid.map { AddSheetItem(pid: $0) } },
            set: { addingToPlaylistPid = $0?.pid }
        )) { item in
            AddSongsToPlaylistSheet(
                allSongs: songs,
                playlistPid: item.pid,
                onAdd: { itemPids in
                    applyPlaylistActions([.addSongs(containerPid: item.pid, itemPids: itemPids)])
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Rename Playlist", isPresented: $showingRenamePlaylistPrompt) {
            TextField("Name", text: $renamePlaylistText)
            Button("Cancel", role: .cancel) { renamePlaylistPid = nil }
            Button("Save") {
                if let pid = renamePlaylistPid, !renamePlaylistText.isEmpty {
                    applyPlaylistActions([.rename(containerPid: pid, newName: renamePlaylistText)])
                }
                renamePlaylistPid = nil
            }
        }
    }

    private struct AddSheetItem: Identifiable {
        let pid: Int64
        var id: Int64 { pid }
    }

    private func playlistSongRow(_ song: DeviceManager.ExportableSongInfo, playlist: PlaylistEntry) -> some View {
        HStack(spacing: 14) {
            artworkView(for: song)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(strongTextColor)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear { loadArtworkIfNeeded(for: song) }
        .contextMenu {
            Button(role: .destructive) {
                applyPlaylistActions([.removeSong(containerPid: playlist.pid, itemPid: song.itemPid)])
            } label: {
                Label("Remove from Playlist", systemImage: "trash")
            }
        }
    }
    private func beginEditing(_ song: DeviceManager.ExportableSongInfo) {
        editingOriginalSong = song
        editingDraftSong = SongMetadata(
            localURL: FileManager.default.temporaryDirectory.appendingPathComponent(song.remoteFilename),
            title: song.title,
            artist: song.artist,
            album: song.album,
            albumArtist: nil,
            genre: song.genre,
            year: song.year,
            durationMs: song.durationMs,
            fileSize: song.fileSize,
            remoteFilename: song.remoteFilename,
            artworkData: artworkDataCache[song.id],
            explicitRating: song.explicitRating
        )
        editingDraftSong.trackNumber = song.trackNumber
        editingDraftSong.lyrics = song.lyrics
        showingMetadataEditor = true
    }

    private func applyMetadataEdits(_ updatedSong: SongMetadata, original: DeviceManager.ExportableSongInfo) {
        isLoading = true
        statusMessage = ""
        manager.updateExportableSongMetadata(original: original, updatedSong: updatedSong) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    private func applyAlbumMetadataEdits(
        to targetSongs: [DeviceManager.ExportableSongInfo],
        artist: String,
        album: String,
        genre: String,
        year: Int,
        artworkData: Data?,
        explicitRating: Int?
    ) {
        guard !targetSongs.isEmpty else { return }
        isLoading = true
        isApplyingAlbumEdit = true
        statusMessage = ""
        manager.updateExportableSongsMetadata(
            originals: targetSongs,
            artist: artist,
            album: album,
            genre: genre,
            year: year,
            artworkData: artworkData,
            explicitRating: explicitRating
        ) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                isApplyingAlbumEdit = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    private func suggestedSongs(
        for album: AlbumEntry,
        in candidates: [DeviceManager.ExportableSongInfo]
    ) -> [DeviceManager.ExportableSongInfo] {
        let albumYear = album.songs.first(where: { $0.year > 0 })?.year ?? 0
        let normalizedAlbumArtist = album.artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return candidates
            .filter { candidate in
                let normalizedCandidateArtist = candidate.artist
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard normalizedCandidateArtist == normalizedAlbumArtist else { return false }
                guard albumYear > 0, candidate.year > 0 else { return true }
                return abs(candidate.year - albumYear) <= 1
            }
            .sorted { lhs, rhs in
                if albumYear > 0, lhs.year > 0, rhs.year > 0 {
                    let lhsDistance = abs(lhs.year - albumYear)
                    let rhsDistance = abs(rhs.year - albumYear)
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func replaceSongAudioFile(_ song: DeviceManager.ExportableSongInfo, with newLocalURL: URL) {
        isLoading = true
        statusMessage = "Replacing audio file for \(song.title)..."
        manager.replaceExportableSongAudioFile(original: song, newLocalURL: newLocalURL) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    refreshSongs()
                }
            }
        }
    }

    private func deleteSong(_ song: DeviceManager.ExportableSongInfo) {
        isLoading = true
        statusMessage = ""
        manager.deleteExportableSong(song) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    selectedIDs.remove(song.id)
                    if selectedIDs.isEmpty {
                        isSelectionMode = false
                    }
                    refreshSongs()
                }
            }
        }
    }

    private func deleteSelectedSongs() {
        let items = selectedSongs
        guard !items.isEmpty else { return }

        isLoading = true
        statusMessage = ""
        manager.deleteExportableSongs(items) { success, message in
            DispatchQueue.main.async {
                isLoading = false
                statusMessage = message
                if success {
                    selectedIDs.subtract(items.map(\.id))
                    isSelectionMode = false
                    refreshSongs()
                }
            }
        }
    }

    private func exportSelectedSongs() {
        let items = selectedSongs
        guard !items.isEmpty else { return }

        let exportFolder = preferredExportFolder
        if exportFolder == nil && !hasSavedExportFolder {
            pendingExportAfterFolderSelection = true
            showingFolderPicker = true
            return
        }

        isExporting = true
        statusMessage = "Exporting \(items.count) song(s) to \(exportFolder?.lastPathComponent ?? "the app folder")..."
        manager.exportSongs(items, destinationFolder: exportFolder) { success, message, _ in
            DispatchQueue.main.async {
                isExporting = false
                statusMessage = success ? message : "\(message) Tap Change Folder and pick another location."
            }
        }
    }

    private var selectedPlaylistSongs: [DeviceManager.ExportableSongInfo] {
        var seenIDs = Set<String>()
        return playlists
            .filter { selectedPlaylistPids.contains($0.pid) }
            .flatMap(\.songs)
            .filter { seenIDs.insert($0.id).inserted }
    }

    private func exportSelectedPlaylists() {
        let items = selectedPlaylistSongs
        guard !items.isEmpty else { return }

        let exportFolder = preferredExportFolder
        if exportFolder == nil && !hasSavedExportFolder {
            pendingPlaylistExportAfterFolderSelection = true
            showingFolderPicker = true
            return
        }

        isExporting = true
        statusMessage = "Exporting \(items.count) song(s) to \(exportFolder?.lastPathComponent ?? "the app folder")..."
        manager.exportSongs(items, destinationFolder: exportFolder) { success, message, _ in
            DispatchQueue.main.async {
                isExporting = false
                statusMessage = success ? message : "\(message) Tap Change Folder and pick another location."
            }
        }
    }

    private func handleExportFolderSelection(url: URL?) {
        guard let url else {
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            return
        }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.exportFolderBookmarkKey)
            statusMessage = "Export folder set to \(url.lastPathComponent)."
            let shouldExportSongsNow = pendingExportAfterFolderSelection
            let shouldExportPlaylistsNow = pendingPlaylistExportAfterFolderSelection
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            if shouldExportSongsNow {
                DispatchQueue.main.async {
                    exportSelectedSongs()
                }
            } else if shouldExportPlaylistsNow {
                DispatchQueue.main.async {
                    exportSelectedPlaylists()
                }
            }
        } catch {
            pendingExportAfterFolderSelection = false
            pendingPlaylistExportAfterFolderSelection = false
            statusMessage = "Could not save export folder."
        }
    }

    private static func resolveBookmarkedFolder(forKey key: String) -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale,
               let refreshedBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshedBookmark, forKey: key)
            }

            return url
        } catch {
            if !Self.didLogExportBookmarkResolutionFailure {
                Self.didLogExportBookmarkResolutionFailure = true
                Logger.shared.log("[Export] Failed to resolve export folder bookmark: \(error)")
            }
            return nil
        }
    }
}

struct AddToPlaylistView: View {
    let playlists: [DeviceLibraryBrowserView.PlaylistEntry]
    let onSelect: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        if playlists.isEmpty {
                            Text("No playlists found.")
                                .foregroundStyle(mutedTextColor)
                                .padding(.top, 40)
                        } else {
                            ForEach(Array(playlists.enumerated()), id: \.element.pid) { index, playlist in
                                Button {
                                    onSelect(playlist.pid)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(controlFillColor)
                                                .frame(width: 48, height: 48)
                                            Image(systemName: "music.note.list")
                                                .font(.title3)
                                                .foregroundStyle(mutedTextColor)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(playlist.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(strongTextColor)
                                            Text("\(playlist.songs.count) songs")
                                                .font(.subheadline)
                                                .foregroundStyle(mutedTextColor)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 20)
                                    .background(panelBackground)
                                }
                                .buttonStyle(.plain)
                                
                                if index < playlists.count - 1 {
                                    Divider()
                                        .background(hairlineColor)
                                        .padding(.leading, 82)
                                }
                            }
                        }
                    }
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding()
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
            }
        }
    }
}

struct AddSongsToPlaylistSheet: View {
    let allSongs: [DeviceManager.ExportableSongInfo]
    let playlistPid: Int64
    let onAdd: ([Int64]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPids = Set<Int64>()
    @State private var searchText = ""
    
    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
    }
    
    var filteredSongs: [DeviceManager.ExportableSongInfo] {
        if searchText.isEmpty { return allSongs }
        return allSongs.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(mutedTextColor)
                        TextField("Search songs", text: $searchText)
                            .foregroundStyle(strongTextColor)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(controlFillColor))
                    .padding()
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredSongs.enumerated()), id: \.element.itemPid) { index, song in
                                Button {
                                    if selectedPids.contains(song.itemPid) {
                                        selectedPids.remove(song.itemPid)
                                    } else {
                                        selectedPids.insert(song.itemPid)
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(song.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(strongTextColor)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.subheadline)
                                                .foregroundStyle(mutedTextColor)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if selectedPids.contains(song.itemPid) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                                        } else {
                                            Circle()
                                                .stroke(mutedTextColor, lineWidth: 1)
                                                .frame(width: 22, height: 22)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 20)
                                }
                                .buttonStyle(.plain)
                                
                                if index < filteredSongs.count - 1 {
                                    Divider().background(hairlineColor).padding(.leading, 20)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(Array(selectedPids))
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    .disabled(selectedPids.isEmpty)
                }
            }
        }
    }
}

struct AddSongsToAlbumSheet: View {
    let album: DeviceLibraryBrowserView.AlbumEntry
    let candidateSongs: [DeviceManager.ExportableSongInfo]
    let suggestedSongs: [DeviceManager.ExportableSongInfo]
    let onAdd: ([DeviceManager.ExportableSongInfo]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIDs = Set<String>()
    @State private var searchText = ""

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
    }

    private func matches(_ song: DeviceManager.ExportableSongInfo) -> Bool {
        searchText.isEmpty || song.title.localizedCaseInsensitiveContains(searchText) || song.artist.localizedCaseInsensitiveContains(searchText)
    }

    private var remainingSongs: [DeviceManager.ExportableSongInfo] {
        let suggestedIDs = Set(suggestedSongs.map(\.id))
        return candidateSongs
            .filter { !suggestedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var filteredSuggested: [DeviceManager.ExportableSongInfo] {
        suggestedSongs.filter(matches)
    }

    private var filteredRemaining: [DeviceManager.ExportableSongInfo] {
        remainingSongs.filter(matches)
    }

    @ViewBuilder
    private func songRow(_ song: DeviceManager.ExportableSongInfo) -> some View {
        Button {
            if selectedIDs.contains(song.id) {
                selectedIDs.remove(song.id)
            } else {
                selectedIDs.insert(song.id)
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(strongTextColor)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(mutedTextColor)
                        .lineLimit(1)
                }
                Spacer()
                if selectedIDs.contains(song.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                } else {
                    Circle()
                        .stroke(mutedTextColor, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(mutedTextColor)
                        TextField("Search songs", text: $searchText)
                            .foregroundStyle(strongTextColor)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(controlFillColor))
                    .padding()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !filteredSuggested.isEmpty {
                                Text("Suggested")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                                ForEach(Array(filteredSuggested.enumerated()), id: \.element.id) { index, song in
                                    songRow(song)
                                    if index < filteredSuggested.count - 1 {
                                        Divider().background(hairlineColor).padding(.leading, 20)
                                    }
                                }
                            }

                            if !filteredRemaining.isEmpty {
                                Text("All Songs")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                ForEach(Array(filteredRemaining.enumerated()), id: \.element.id) { index, song in
                                    songRow(song)
                                    if index < filteredRemaining.count - 1 {
                                        Divider().background(hairlineColor).padding(.leading, 20)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(candidateSongs.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}

struct AddToAlbumView: View {
    let albums: [DeviceLibraryBrowserView.AlbumEntry]
    let onSelectAlbum: (DeviceLibraryBrowserView.AlbumEntry) -> Void
    let onCreateNewAlbum: (_ artist: String, _ album: String, _ genre: String, _ year: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNewAlbumForm = false
    @State private var newAlbumName = ""
    @State private var newAlbumArtist = ""
    @State private var newAlbumGenre = ""
    @State private var newAlbumYear = ""

    private var pageBackground: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.12) : Color(red: 0.95, green: 0.95, blue: 0.97)
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.white
    }

    private var strongTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedTextColor: Color {
        colorScheme == .dark ? Color(white: 0.6) : Color(white: 0.4)
    }

    private var hairlineColor: Color {
        colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)
    }

    private var controlFillColor: Color {
        colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if showingNewAlbumForm {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Album name", text: $newAlbumName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Album artist", text: $newAlbumArtist)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Genre", text: $newAlbumGenre)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Year", text: $newAlbumYear)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    onCreateNewAlbum(
                                        newAlbumArtist,
                                        newAlbumName,
                                        newAlbumGenre,
                                        Int(newAlbumYear.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                    )
                                    dismiss()
                                } label: {
                                    Text("Create Album")
                                        .font(.body.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(red: 1.0, green: 0.27, blue: 0.42))
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding()
                            .background(panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        } else {
                            Button {
                                showingNewAlbumForm = true
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(controlFillColor)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundStyle(mutedTextColor)
                                    }
                                    Text("New Album")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(strongTextColor)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .background(panelBackground)
                            }
                            .buttonStyle(.plain)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                        }

                        VStack(spacing: 0) {
                            if albums.isEmpty {
                                Text("No albums found.")
                                    .foregroundStyle(mutedTextColor)
                                    .padding(.top, 40)
                            } else {
                                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                                    Button {
                                        onSelectAlbum(album)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(controlFillColor)
                                                    .frame(width: 48, height: 48)
                                                Image(systemName: "square.stack")
                                                    .font(.title3)
                                                    .foregroundStyle(mutedTextColor)
                                            }

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(album.name)
                                                    .font(.body.weight(.semibold))
                                                    .foregroundStyle(strongTextColor)
                                                    .lineLimit(1)
                                                Text("\(album.artist) · \(album.songs.count) track\(album.songs.count == 1 ? "" : "s")")
                                                    .font(.subheadline)
                                                    .foregroundStyle(mutedTextColor)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 20)
                                        .background(panelBackground)
                                    }
                                    .buttonStyle(.plain)

                                    if index < albums.count - 1 {
                                        Divider()
                                            .background(hairlineColor)
                                            .padding(.leading, 82)
                                    }
                                }
                            }
                        }
                        .background(panelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.42))
                }
            }
        }
    }
}
