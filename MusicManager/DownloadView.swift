import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

struct DownloadView: View {
    private enum ResultsPage: String {
        case songs = "Songs"
        case albums = "Albums"
        case playlists = "Playlists"
    }

    enum SearchProvider: String, CaseIterable, Identifiable {
        case appleMusic
        case spotify
        case metadata
        case itunes
        case deezer

        static var allCases: [SearchProvider] {
            [.appleMusic, .itunes, .deezer]
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appleMusic: return "Apple Music"
            case .spotify: return "Spotify"
            case .metadata: return "iTunes + Deezer"
            case .itunes: return "iTunes"
            case .deezer: return "Deezer"
            }
        }

        var searchPlaceholder: String {
            switch self {
            case .appleMusic: return "Search or paste an Apple music, Spotify or Deezer Link."
            case .spotify: return "Search or paste a Spotify link"
            case .metadata: return "Search iTunes and Deezer"
            case .itunes: return "Search iTunes songs"
            case .deezer: return "Search or paste a Deezer link"
            }
        }

        var emptyStateSubtitle: String {
            switch self {
            case .appleMusic: return "Search a song and tap download"
            case .spotify: return "Search a song and tap download"
            case .metadata: return "Search iTunes and Deezer and tap download"
            case .itunes: return "Search iTunes and tap download"
            case .deezer: return "Search Deezer and tap download"
            }
        }
    }

    private struct AlbumSelectionState {
        var album: DownloadAlbum?
        var tracks: [DownloadTrack] = []
        var selectedTrackIDs: Set<String> = []
        var isLoading = false
        var errorText: String?
        var navigationTitle = "Album Download"
        var helperText = "Choose the tracks you want to download, or grab the full album in one tap."

        var isPresented: Bool { album != nil }
        var selectedTracks: [DownloadTrack] {
            tracks.filter { selectedTrackIDs.contains($0.id) }
        }
    }

    private struct DirectTrackSelectionState: Identifiable {
        let id = UUID()
        let track: DownloadTrack
    }

    @Binding var songs: [SongMetadata]
    @Binding var status: String
    @StateObject private var vm = DownloadViewModel.shared
    @AppStorage("downloadSearchProvider") private var searchProviderRaw = SearchProvider.deezer.rawValue
    @State private var query = ""
    @State private var handledEmittedCount = 0
    @State private var selectedPage: ResultsPage = .songs
    @State private var showingQueueDetails = false
    @State private var showingMaintenancePanel = false
    @State private var albumSelection = AlbumSelectionState()
    @State private var directTrackSelection: DirectTrackSelectionState?
    @State private var selectedTrackForBrowse: DownloadTrack?
    @State private var pushedArtist: DownloadArtist?

    private var usesFloatingTabBarLayout: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return (16...18).contains(major)
    }

    private var resultsBottomInset: CGFloat {
        usesFloatingTabBarLayout ? 110 : 24
    }

    private var searchProvider: SearchProvider {
        get {
            SearchProvider(rawValue: searchProviderRaw) ?? .appleMusic
        }
        nonmutating set { searchProviderRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Download")
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                    Button {
                        showingQueueDetails = true
                    } label: {
                        DownloadQueueIndicator(
                            progress: vm.aggregateDownloadProgress,
                            label: vm.queueCounterText
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 0)
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(searchProvider.searchPlaceholder, text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            if query.trimmingCharacters(in: .whitespacesAndNewlines) == "EduAlexxis" {
                                query = ""
                                showingMaintenancePanel = true
                                return
                            }
                            Task { await vm.search(query: query, provider: searchProvider) }
                        }

                    if vm.isSearching {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                            vm.artistResults = []
                            vm.songResults = []
                            vm.albumResults = []
                            vm.playlistResults = []
                            vm.canLoadMoreSongs = false
                            vm.canLoadMoreAlbums = false
                            vm.canLoadMorePlaylists = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                if let error = vm.errorText {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Text(error)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                }

                HStack {
                    Text("Results")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if !vm.songResults.isEmpty || !vm.albumResults.isEmpty || !vm.playlistResults.isEmpty {
                        Text(resultsSummaryText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                if vm.songResults.isEmpty && vm.albumResults.isEmpty && vm.playlistResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(Color(.systemGray3))
                        VStack(spacing: 4) {
                            Text("No results yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(searchProvider.emptyStateSubtitle)
                                .font(.subheadline)
                                .foregroundColor(Color(.systemGray))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            pageSwitcher

                            if selectedPage == .songs {
                                if vm.songResults.isEmpty {
                                    emptyPage("No songs", subtitle: "No song matches for this search")
                                } else {
                                    ForEach(Array(vm.songResults.enumerated()), id: \.element.id) { index, track in
                                        songRow(track)
                                        if index < vm.songResults.count - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                    if vm.canLoadMoreSongs {
                                        Divider().padding(.leading, 80)
                                        loadMoreButton(title: "Load More Songs", isLoading: vm.isLoadingMoreSongs) {
                                            Task { await vm.loadMoreSongs() }
                                        }
                                    }
                                }
                            } else if selectedPage == .albums {
                                if vm.albumResults.isEmpty {
                                    emptyPage("No albums", subtitle: "No album matches for this search")
                                } else {
                                    ForEach(Array(vm.albumResults.enumerated()), id: \.element.id) { index, album in
                                        albumRow(album)
                                        if index < vm.albumResults.count - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                    if vm.canLoadMoreAlbums {
                                        Divider().padding(.leading, 80)
                                        loadMoreButton(title: "Load More Albums", isLoading: vm.isLoadingMoreAlbums) {
                                            Task { await vm.loadMoreAlbums() }
                                        }
                                    }
                                }
                            } else {
                                if vm.playlistResults.isEmpty {
                                    emptyPage("No playlists", subtitle: "No playlist matches for this search")
                                } else {
                                    ForEach(Array(vm.playlistResults.enumerated()), id: \.element.id) { index, playlist in
                                        playlistRow(playlist)
                                        if index < vm.playlistResults.count - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                    if vm.canLoadMorePlaylists {
                                        Divider().padding(.leading, 80)
                                        loadMoreButton(title: "Load More Playlists", isLoading: vm.isLoadingMorePlaylists) {
                                            Task { await vm.loadMorePlaylists() }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, resultsBottomInset)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .onChange(of: vm.emittedSongs.count) { newCount in
            guard newCount > handledEmittedCount else { return }
            for idx in handledEmittedCount..<newCount {
                let song = vm.emittedSongs[idx]
                songs.append(song)
                status = "Downloaded: \(song.title)"
            }
            handledEmittedCount = newCount
        }
        .onAppear {
            if searchProviderRaw == "tidal" || searchProviderRaw == SearchProvider.spotify.rawValue {
                searchProviderRaw = SearchProvider.appleMusic.rawValue
            }
            if searchProviderRaw == SearchProvider.metadata.rawValue {
                searchProviderRaw = SearchProvider.itunes.rawValue
            }
            vm.appDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IncomingMusicLink"))) { notification in
            if let link = notification.object as? String {
                self.query = link
                Task {
                    await vm.search(query: link, provider: searchProvider)
                }
            }
        }
        .onChange(of: searchProviderRaw) { newValue in
            vm.artistResults = []
            vm.songResults = []
            vm.albumResults = []
            vm.playlistResults = []
            selectedPage = .songs
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let provider = SearchProvider(rawValue: newValue) ?? .appleMusic
            Task { await vm.search(query: query, provider: provider) }
        }
        .onChange(of: vm.pendingDirectLinkAction?.id) { _ in
            guard let action = vm.pendingDirectLinkAction else { return }
            switch action.payload {
            case .track(let track):
                directTrackSelection = DirectTrackSelectionState(track: track)
            case .collection(let album, let tracks, let title, let helperText):
                presentResolvedCollectionSelection(
                    album: album,
                    tracks: tracks,
                    navigationTitle: title,
                    helperText: helperText
                )
            case .artist(let artist):
                presentArtistSelection(for: artist)
            }
            vm.pendingDirectLinkAction = nil
        }
        .sheet(isPresented: $showingQueueDetails) {
            DownloadQueueDetailsSheet(vm: vm)
        }
        .sheet(isPresented: $showingMaintenancePanel) {
            MaintenancePanelView()
        }
        .sheet(
            isPresented: Binding(
                get: { albumSelection.isPresented },
                set: { isPresented in
                    if !isPresented { resetAlbumSelection() }
                }
            )
        ) {
            albumSelectionSheet
        }
        .sheet(item: $directTrackSelection) { selection in
            DirectTrackDownloadSheet(
                track: selection.track,
                state: vm.state(for: selection.track.id),
                onCancel: {
                    directTrackSelection = nil
                },
                onConfirm: {
                    if vm.state(for: selection.track.id) == .failed {
                        vm.retry(trackID: selection.track.id)
                    } else {
                        vm.enqueue(track: selection.track)
                    }
                    directTrackSelection = nil
                }
            )
        }
        .sheet(item: $selectedTrackForBrowse) { track in
            TrackBrowseSheet(
                track: track,
                onSelectAlbum: {
                    selectedTrackForBrowse = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        presentAlbumSelection(for: albumForTrack(track))
                    }
                },
                onSelectArtist: {
                    selectedTrackForBrowse = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        presentArtistSelection(for: track)
                    }
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pushedArtist) { artist in
            NavigationStack {
                ArtistProfileScreen(
                    artist: artist,
                    vm: vm,
                    onSelectAlbum: { album in
                        presentAlbumSelection(for: album)
                    },
                    onBrowseTrack: { track in
                        selectedTrackForBrowse = track
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var pageSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                selectedPage = .songs
            } label: {
                VStack(spacing: 6) {
                    Text("Songs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedPage == .songs ? .primary : .secondary)

                    Rectangle()
                        .fill(selectedPage == .songs ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)

            Button {
                selectedPage = .albums
            } label: {
                VStack(spacing: 6) {
                    Text("Albums")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedPage == .albums ? .primary : .secondary)

                    Rectangle()
                        .fill(selectedPage == .albums ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)

            Button {
                selectedPage = .playlists
            } label: {
                VStack(spacing: 6) {
                    Text("Playlists")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedPage == .playlists ? .primary : .secondary)

                    Rectangle()
                        .fill(selectedPage == .playlists ? Color.accentColor : Color.clear)
                        .frame(height: 2)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func emptyPage(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var resultsSummaryText: String {
        "\(vm.songResults.count) songs • \(vm.albumResults.count) albums • \(vm.playlistResults.count) playlists"
    }

    @ViewBuilder
    private func loadMoreButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(isLoading ? "Loading..." : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private func songRow(_ track: DownloadTrack) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedTrackForBrowse = track
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .lineLimit(1)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text(track.artistLine)
                                .lineLimit(1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if track.isExplicit {
                                Text("E")
                                    .font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Text(track.albumName)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                vm.togglePreview(for: track)
            } label: {
                if vm.isPreviewLoading(for: track.id) {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: vm.isPreviewPlaying(for: track.id) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(vm.isPreviewPlaying(for: track.id) ? .blue : .secondary)
                }
            }
            .buttonStyle(.plain)

            Button {
                if vm.state(for: track.id) == .failed {
                    vm.retry(trackID: track.id)
                } else {
                    vm.enqueue(track: track)
                }
            } label: {
                switch vm.state(for: track.id) {
                case .downloading:
                    ProgressView().frame(width: 28, height: 28)
                case .queued:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                case .idle:
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!vm.canEnqueue(trackID: track.id))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func albumRow(_ album: DownloadAlbum) -> some View {
        HStack(spacing: 12) {
            Button {
                presentAlbumSelection(for: album)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: album.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "rectangle.stack.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.name)
                            .lineLimit(1)
                            .font(.headline)
                        Text(album.artistLine)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if vm.state(forAlbumID: album.id) == .failed {
                    Task { await vm.retry(album: album) }
                } else {
                    presentAlbumSelection(for: album)
                }
            } label: {
                if vm.isResolvingAlbum(albumID: album.id) {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    switch vm.state(forAlbumID: album.id) {
                    case .downloading:
                        ProgressView().frame(width: 28, height: 28)
                    case .queued:
                        Image(systemName: "clock.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    case .idle:
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(vm.isResolvingAlbum(albumID: album.id))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var albumSelectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let album = albumSelection.album {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            AsyncImage(url: album.artworkURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    ZStack {
                                        Color(.tertiarySystemFill)
                                        Image(systemName: "rectangle.stack.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.headline.weight(.semibold))
                                    .lineLimit(2)
                                Text(album.artistLine)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }

                        Text(albumSelection.helperText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button("Select All") {
                                albumSelection.selectedTrackIDs = Set(albumSelection.tracks.map(\.id))
                            }
                            .font(.caption.weight(.semibold))

                            Button("Clear All") {
                                albumSelection.selectedTrackIDs.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                            Spacer()

                            if !albumSelection.tracks.isEmpty {
                                Text("\(albumSelection.selectedTrackIDs.count) of \(albumSelection.tracks.count) selected")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                    if let errorText = albumSelection.errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }

                    Group {
                        if albumSelection.isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading album tracks...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if albumSelection.tracks.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundStyle(.secondary)
                                Text("No tracks found")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 10) {
                                    ForEach(Array(albumSelection.tracks.enumerated()), id: \.element.id) { index, track in
                                        Button {
                                            toggleAlbumTrackSelection(track)
                                        } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                ZStack {
                                                    Circle()
                                                        .fill(albumSelection.selectedTrackIDs.contains(track.id) ? Color.accentColor : Color(.systemGray5))
                                                        .frame(width: 24, height: 24)

                                                    Image(systemName: albumSelection.selectedTrackIDs.contains(track.id) ? "checkmark" : "\(index + 1)")
                                                        .font(.system(size: albumSelection.selectedTrackIDs.contains(track.id) ? 11 : 10, weight: .bold))
                                                        .foregroundStyle(albumSelection.selectedTrackIDs.contains(track.id) ? .white : .secondary)
                                                }
                                                .padding(.top, 1)

                                                VStack(alignment: .leading, spacing: 5) {
                                                    HStack(spacing: 6) {
                                                        Text(track.name)
                                                            .font(.subheadline.weight(.semibold))
                                                            .foregroundStyle(.primary)
                                                            .multilineTextAlignment(.leading)
                                                        if track.isExplicit {
                                                            Text("E")
                                                                .font(.system(size: 8, weight: .black))
                                                                .padding(.horizontal, 4)
                                                                .padding(.vertical, 2)
                                                                .background(Color.red)
                                                                .foregroundColor(.white)
                                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                                        }
                                                    }

                                                    Text(track.artistLine)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.leading)
                                                }

                                                Spacer()
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            queueEntireAlbumAndDismiss()
                        } label: {
                            Text("Download All")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(albumSelection.isLoading || albumSelection.tracks.isEmpty)

                        Button {
                            queueSelectedAlbumTracksAndDismiss()
                        } label: {
                            Text("Download Selected")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(albumSelection.isLoading || albumSelection.selectedTrackIDs.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(albumSelection.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetAlbumSelection()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func presentAlbumSelection(for album: DownloadAlbum) {
        albumSelection = AlbumSelectionState(
            album: album,
            tracks: [],
            selectedTrackIDs: [],
            isLoading: true,
            errorText: nil,
            navigationTitle: "Album Download",
            helperText: "Choose the tracks you want to download, or grab the full album in one tap."
        )

        Task {
            let tracks = await vm.loadTracks(for: album)
            guard albumSelection.album?.id == album.id else { return }

            albumSelection.tracks = tracks
            albumSelection.selectedTrackIDs = Set(tracks.map(\.id))
            albumSelection.isLoading = false
            albumSelection.errorText = tracks.isEmpty ? "Could not load tracks for \(album.name)." : nil
        }
    }

    private func presentPlaylistSelection(for playlist: DownloadAlbum) {
        albumSelection = AlbumSelectionState(
            album: playlist,
            tracks: [],
            selectedTrackIDs: [],
            isLoading: true,
            errorText: nil,
            navigationTitle: "Playlist Download",
            helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
        )

        Task {
            let tracks = await vm.loadTracks(forPlaylist: playlist)
            guard albumSelection.album?.id == playlist.id else { return }

            albumSelection.tracks = tracks
            albumSelection.selectedTrackIDs = Set(tracks.map(\.id))
            albumSelection.isLoading = false
            albumSelection.errorText = tracks.isEmpty ? "Could not load tracks for \(playlist.name)." : nil
        }
    }

    private func presentResolvedCollectionSelection(
        album: DownloadAlbum,
        tracks: [DownloadTrack],
        navigationTitle: String,
        helperText: String
    ) {
        albumSelection = AlbumSelectionState(
            album: album,
            tracks: tracks,
            selectedTrackIDs: Set(tracks.map(\.id)),
            isLoading: false,
            errorText: tracks.isEmpty ? "Could not load tracks for \(album.name)." : nil,
            navigationTitle: navigationTitle,
            helperText: helperText
        )
    }

    private func presentArtistSelection(for track: DownloadTrack) {
        let artist = DownloadArtist(
            id: track.artistIdentifier ?? "\(track.provider.rawValue):\(DownloadSupport.normalizedSearchValue(primaryArtistName(from: track.artistLine)))",
            name: primaryArtistName(from: track.artistLine),
            provider: track.provider,
            artworkURL: track.artworkURL
        )
        presentArtistSelection(for: artist)
    }

    private func presentArtistSelection(for album: DownloadAlbum) {
        let artist = DownloadArtist(
            id: album.artistIdentifier ?? "\(album.provider.rawValue):\(DownloadSupport.normalizedSearchValue(primaryArtistName(from: album.artistLine)))",
            name: primaryArtistName(from: album.artistLine),
            provider: album.provider,
            artworkURL: album.artworkURL
        )
        presentArtistSelection(for: artist)
    }

    private func presentArtistSelection(for artist: DownloadArtist) {
        pushedArtist = artist
    }

    private func toggleAlbumTrackSelection(_ track: DownloadTrack) {
        if albumSelection.selectedTrackIDs.contains(track.id) {
            albumSelection.selectedTrackIDs.remove(track.id)
        } else {
            albumSelection.selectedTrackIDs.insert(track.id)
        }
    }

    private func queueEntireAlbumAndDismiss() {
        guard let album = albumSelection.album else { return }
        let added = vm.enqueue(tracks: albumSelection.tracks, albumID: album.id)
        if added == 0 {
            vm.errorText = "All tracks from \(album.name) are already queued or downloaded."
        }
        resetAlbumSelection()
    }

    private func queueSelectedAlbumTracksAndDismiss() {
        guard let album = albumSelection.album else { return }
        let selectedTracks = albumSelection.selectedTracks
        let added = vm.enqueue(tracks: selectedTracks, albumID: album.id)
        if added == 0 {
            vm.errorText = selectedTracks.isEmpty
                ? "No tracks selected for \(album.name)."
                : "Selected tracks from \(album.name) are already queued or downloaded."
        }
        resetAlbumSelection()
    }

    private func resetAlbumSelection() {
        albumSelection = AlbumSelectionState()
    }

    private func albumForTrack(_ track: DownloadTrack) -> DownloadAlbum {
        DownloadAlbum(
            id: track.albumIdentifier ?? "\(track.provider.rawValue)-album-\(DownloadSupport.normalizedSearchValue(track.artistLine))-\(DownloadSupport.normalizedSearchValue(track.albumName))",
            name: track.albumName,
            artistLine: track.artistLine,
            artworkURL: track.artworkURL,
            sourceURL: track.sourceURL,
            provider: track.provider,
            artistIdentifier: track.artistIdentifier,
            albumIdentifier: track.albumIdentifier
        )
    }

    @ViewBuilder
    private func playlistRow(_ playlist: DownloadAlbum) -> some View {
        HStack(spacing: 12) {
            Button {
                presentPlaylistSelection(for: playlist)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: playlist.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                            .lineLimit(1)
                            .font(.headline)
                        Text(playlist.artistLine)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if vm.state(forAlbumID: playlist.id) == .failed {
                    Task { await vm.retry(playlist: playlist) }
                } else {
                    presentPlaylistSelection(for: playlist)
                }
            } label: {
                if vm.isResolvingAlbum(albumID: playlist.id) {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    switch vm.state(forAlbumID: playlist.id) {
                    case .downloading:
                        ProgressView().frame(width: 28, height: 28)
                    case .queued:
                        Image(systemName: "clock.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    case .idle:
                        Image(systemName: "music.note.list")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(vm.isResolvingAlbum(albumID: playlist.id))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func primaryArtistName(from artistLine: String) -> String {
        let separatorsPattern = #"\s*(?:,|&| x | y | feat\.?|ft\.?|with)\s*"#
        let canonicalized = artistLine.replacingOccurrences(of: separatorsPattern, with: ",", options: .regularExpression)
        let primary = canonicalized
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (primary?.isEmpty == false) ? primary! : artistLine
    }
}

#Preview {
    DownloadView(songs: .constant([]), status: .constant("Ready"))
}

private struct TrackBrowseSheet: View {
    let track: DownloadTrack
    let onSelectAlbum: () -> Void
    let onSelectArtist: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            HStack(spacing: 12) {
                AsyncImage(url: track.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(.tertiarySystemFill)
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(track.artistLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(track.albumName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 12) {
                Button {
                    onSelectAlbum()
                } label: {
                    Label("Go to Album", systemImage: "rectangle.stack")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onSelectArtist()
                } label: {
                    Label("Go to Artist", systemImage: "music.mic")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct DirectTrackDownloadSheet: View {
    let track: DownloadTrack
    let state: DownloadTrackState
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(track.artistLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(track.albumName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Text("Download this song now?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button(action: onConfirm) {
                        Text(confirmButtonTitle)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!canConfirm)
                }
            }
            .padding(20)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Song Download")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    private var canConfirm: Bool {
        switch state {
        case .queued, .downloading, .done:
            return false
        case .idle, .failed:
            return true
        }
    }

    private var confirmButtonTitle: String {
        switch state {
        case .failed:
            return "Retry Download"
        case .queued:
            return "Already Queued"
        case .downloading:
            return "Downloading"
        case .done:
            return "Already Downloaded"
        case .idle:
            return "Download"
        }
    }
}

struct DownloadTrack: Identifiable {
    enum SourceContext {
        case song
        case album
    }

    let id: String
    let name: String
    let artistLine: String
    let albumName: String
    let artworkURL: URL?
    let isExplicit: Bool
    let sourceURL: String
    let sourceContext: SourceContext
    let provider: DownloadView.SearchProvider
    let artistIdentifier: String?
    let albumIdentifier: String?
    let previewURL: URL?
}

struct DownloadAlbum: Identifiable {
    let id: String
    let name: String
    let artistLine: String
    let artworkURL: URL?
    let sourceURL: String
    let provider: DownloadView.SearchProvider
    let artistIdentifier: String?
    let albumIdentifier: String?
}

struct DownloadArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: DownloadView.SearchProvider
    let artworkURL: URL?
}

struct DownloadArtistProfile {
    let tracks: [DownloadTrack]
    let albums: [DownloadAlbum]
}

private struct ArtistProfileScreen: View {
    private enum ArtistSection: String {
        case albums = "Albums"
        case tracks = "Tracks"
    }

    let artist: DownloadArtist
    @ObservedObject var vm: DownloadViewModel
    let onSelectAlbum: (DownloadAlbum) -> Void
    let onBrowseTrack: (DownloadTrack) -> Void

    @State private var profile = DownloadArtistProfile(tracks: [], albums: [])
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var selectedSection: ArtistSection = .albums
    @State private var visibleAlbumCount = 8
    @State private var visibleTrackCount = 12

    private var hasResults: Bool {
        !profile.albums.isEmpty || !profile.tracks.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                artistHeroHeader

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading artist profile...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    if hasResults {
                        artistSectionPicker
                            .padding(.horizontal, 20)
                    }

                    if selectedSection == .albums {
                        if !profile.albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Albums & Singles")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(min(visibleAlbumCount, profile.albums.count))/\(profile.albums.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14)
                                    ],
                                    spacing: 14
                                ) {
                                    ForEach(Array(profile.albums.prefix(visibleAlbumCount))) { album in
                                        artistAlbumCard(album)
                                    }
                                }
                                .padding(.horizontal, 20)

                                if visibleAlbumCount < profile.albums.count {
                                    artistLoadMoreButton(title: "Load More Albums") {
                                        visibleAlbumCount = min(visibleAlbumCount + 8, profile.albums.count)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    } else {
                        if !profile.tracks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Tracks")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(min(visibleTrackCount, profile.tracks.count))/\(profile.tracks.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)

                                VStack(spacing: 0) {
                                    ForEach(Array(profile.tracks.prefix(visibleTrackCount).enumerated()), id: \.element.id) { index, track in
                                        artistTrackRow(track)
                                        if index < min(visibleTrackCount, profile.tracks.count) - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                }
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray5), lineWidth: 1)
                                )
                                .padding(.horizontal, 20)

                                if visibleTrackCount < profile.tracks.count {
                                    artistLoadMoreButton(title: "Load More Tracks") {
                                        visibleTrackCount = min(visibleTrackCount + 12, profile.tracks.count)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }

                    if profile.albums.isEmpty && profile.tracks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "music.mic")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No artist results found")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Artist")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: artist.id) {
            isLoading = true
            visibleAlbumCount = 8
            visibleTrackCount = 12
            selectedSection = .albums
            let loaded = await vm.loadArtistProfile(for: artist)
            profile = loaded
            errorText = (loaded.tracks.isEmpty && loaded.albums.isEmpty) ? "Could not load results for \(artist.name)." : nil
            if loaded.albums.isEmpty && !loaded.tracks.isEmpty {
                selectedSection = .tracks
            }
            isLoading = false
        }
    }

    private var artistHeroHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                AsyncImage(url: artist.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), Color(.secondarySystemFill)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.mic")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(artist.name)
                        .font(.system(size: 30, weight: .bold))
                    Text(artist.provider.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if hasResults {
                HStack(spacing: 10) {
                    artistCountPill(title: "Albums", value: profile.albums.count)
                    artistCountPill(title: "Tracks", value: profile.tracks.count)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func artistCountPill(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    private func artistLoadMoreButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var artistSectionPicker: some View {
        HStack(spacing: 8) {
            ForEach([ArtistSection.albums, .tracks], id: \.rawValue) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 6) {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSection == section ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedSection == section ? Color.accentColor : Color.clear)
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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func artistAlbumCard(_ album: DownloadAlbum) -> some View {
        Button {
            onSelectAlbum(album)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: album.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(.tertiarySystemFill)
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(album.artistLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artistTrackRow(_ track: DownloadTrack) -> some View {
        HStack(spacing: 12) {
            Button {
                onBrowseTrack(track)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .lineLimit(1)
                            .font(.headline)
                        Text(track.artistLine)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(track.albumName)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if vm.state(for: track.id) == .failed {
                    vm.retry(trackID: track.id)
                } else {
                    vm.enqueue(track: track)
                }
            } label: {
                switch vm.state(for: track.id) {
                case .downloading:
                    ProgressView().frame(width: 28, height: 28)
                case .queued:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                case .idle:
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!vm.canEnqueue(trackID: track.id))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct DownloadQueueIndicator: View {
    let progress: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 5)

            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Download queue progress \(label)")
    }
}

enum DownloadTrackState {
    case idle
    case queued
    case downloading
    case done
    case failed
}

struct DownloadDirectLinkAction: Identifiable {
    let id = UUID()
    let payload: DownloadDirectLinkPayload
}

enum DownloadDirectLinkPayload {
    case track(DownloadTrack)
    case collection(album: DownloadAlbum, tracks: [DownloadTrack], title: String, helperText: String)
    case artist(DownloadArtist)
}

struct BackendCandidate {
    let label: String
    let request: URLRequest?
    let customDownload: ((_ trackID: String, _ suggestedName: String, _ fallbackExtension: String) async throws -> URL)?
    var requestedFormat: String? = nil
}

struct BackendDownloadOutcome {
    let fileURL: URL
    let backendLabel: String
}

private struct PreparedBackgroundDownloadPlan {
    let candidates: [BackendCandidate]
    let suggestedName: String
    let fallbackExtension: String
}


enum DownloadPlatform: String {
    case appleMusic
    case spotify
    case deezer
    case qobuz
    case tidal
    case amazon
    case pandora
    case soundcloud
    case youtubeMusic
    case unknown

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .deezer: return "Deezer"
        case .qobuz: return "Qobuz"
        case .tidal: return "Tidal"
        case .amazon: return "Amazon Music"
        case .pandora: return "Pandora"
        case .soundcloud: return "SoundCloud"
        case .youtubeMusic: return "YouTube Music"
        case .unknown: return "Unknown"
        }
    }

    var backendGenreSource: String {
        switch self {
        case .appleMusic: return "itunes"
        case .spotify: return "spotify"
        case .deezer: return "itunes"
        case .qobuz: return "itunes"
        case .tidal: return "itunes"
        case .amazon: return "itunes"
        case .pandora: return "itunes"
        case .soundcloud: return "itunes"
        case .youtubeMusic: return "itunes"
        case .unknown: return "itunes"
        }
    }
}

struct DownloadSourceChoice {
    let platform: DownloadPlatform
    let url: String
    let backendGenreSource: String
}

private struct MetadataSearchBatch {
    let tracks: [DownloadTrack]
    let deezerCount: Int
}

private enum DirectLinkKind {
    case appleSong(id: String, sourceURL: String)
    case appleAlbum(id: String, sourceURL: String)
    case appleArtist(id: String, sourceURL: String)
    case applePlaylist(id: String, sourceURL: String)
    case spotifyTrack(id: String, sourceURL: String)
    case spotifyAlbum(id: String, sourceURL: String)
    case spotifyArtist(id: String, sourceURL: String)
    case spotifyPlaylist(id: String, sourceURL: String)
    case deezerTrack(id: String, sourceURL: String)
    case deezerAlbum(id: String, sourceURL: String)
    case deezerArtist(id: String, sourceURL: String)
    case deezerPlaylist(id: String, sourceURL: String)
    case deezerShortLink(sourceURL: String)
}

enum DownloadError: LocalizedError {
    case invalidURL(String)
    case searchFailed
    case mappingFailed(String)
    case trackNotFound
    case remoteFailure(String)
    case httpError(Int, String)
    case emptyResponse
    case fileSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL."
        case .searchFailed: return "Search failed."
        case .mappingFailed(let message): return message
        case .trackNotFound: return "No downloadable match was found for this track."
        case .remoteFailure(let text): return "Backend failure: \(text)"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .emptyResponse: return "Backend returned empty response."
        case .fileSaveFailed(let message): return "Save failed: \(message)"
        }
    }
}

enum DownloadSupport {
    static func fileExtension(for mimeType: String?, fallback: String) -> String {
        guard let type = mimeType?.lowercased() else { return fallback }
        if type.contains("opus") { return "opus" }
        if type.contains("flac") { return "flac" }
        if type.contains("mpeg") || type.contains("mp3") { return "mp3" }
        if type.contains("aac") || type.contains("mp4") { return "m4a" }
        if type.contains("wav") { return "wav" }
        return fallback
    }

    static func fallbackExtension(forRequestedFormat format: String?, defaultingTo fallback: String) -> String {
        guard let format else { return fallback }
        switch format.lowercased() {
        case "alac": return "m4a"
        case "": return fallback
        default: return format.lowercased()
        }
    }

    static func tidyFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
    }

    nonisolated static func normalizedSearchValue(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let cleaned = folded.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func artistTokens(from value: String) -> [String] {
        let separatorsPattern = #"\s*(?:,|&| x | y | feat\.?|ft\.?|with)\s*"#
        let canonicalized = value.replacingOccurrences(of: separatorsPattern, with: ",", options: .regularExpression)
        return canonicalized
            .components(separatedBy: ",")
            .map(normalizedSearchValue)
            .filter { !$0.isEmpty }
    }
}

private actor DownloadStartPacer {
    private let defaultMinSpacing: Duration
    private var lastStart: ContinuousClock.Instant?

    init(minSpacing: Duration) {
        self.defaultMinSpacing = minSpacing
    }

    func waitForNextSlot(minSpacing: Duration? = nil) async {
        let spacing = minSpacing ?? defaultMinSpacing
        if let lastStart {
            let elapsed = ContinuousClock.now - lastStart
            if elapsed < spacing {
                try? await Task.sleep(for: spacing - elapsed)
            }
        }
        lastStart = ContinuousClock.now
    }
}

private final class BackgroundTaskState {
    var id: UIBackgroundTaskIdentifier = .invalid
}

@MainActor
final class DownloadViewModel: ObservableObject {
    static let shared = DownloadViewModel()

    @Published var artistResults: [DownloadArtist] = []
    @Published var songResults: [DownloadTrack] = []
    @Published var albumResults: [DownloadAlbum] = []
    @Published var playlistResults: [DownloadAlbum] = []
    @Published var pendingDirectLinkAction: DownloadDirectLinkAction?
    @Published var isPaused = false
    private var foregroundWorkerTasks: [String: Task<Void, Never>] = [:]
    private var maxConcurrentDownloads: Int {
        isLosslessDownloadFormat ? 2 : 3
    }
    private var isLosslessDownloadFormat: Bool {
        let format = desiredDownloadFormat().lowercased()
        return format == "flac" || format == "alac"
    }
    private var isAppActive = UIApplication.shared.applicationState != .background
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var pendingBackgroundHandoffTrackIDs: Set<String> = []
    private let downloadStartPacer = DownloadStartPacer(minSpacing: .milliseconds(300))

    var shouldShowPauseButton: Bool {
        !pendingQueue.isEmpty || !activeDownloadTrackIDs.isEmpty
    }

    var shouldShowCancelButton: Bool {
        !pendingQueue.isEmpty || !activeDownloadTrackIDs.isEmpty || isPaused
    }
    @Published var isSearching = false
    @Published var errorText: String?
    @Published var canLoadMoreSongs = false
    @Published var canLoadMoreAlbums = false
    @Published var canLoadMorePlaylists = false
    @Published var isLoadingMoreSongs = false
    @Published var isLoadingMoreAlbums = false
    @Published var isLoadingMorePlaylists = false
    @Published private(set) var activeDownloadTrackIDs: Set<String> = []
    @Published var activePreviewTrackID: String?
    @Published private(set) var previewLoadingTrackIDs: Set<String> = []
    @Published var emittedSongs: [SongMetadata] = []
    @Published private(set) var totalQueueCount = 0
    @Published private(set) var completedQueueCount = 0
    @Published private(set) var downloadProgressByTrackID: [String: Double] = [:]
    @Published private(set) var downloadSpeedByTrackID: [String: Double] = [:]

    private let session: URLSession = .shared
    private var pendingQueue: [DownloadTrack] = []
    private var trackStates: [String: DownloadTrackState] = [:]
    private var trackFailureReasons: [String: String] = [:]
    private var trackQualityNotes: [String: String] = [:]
    private var knownTracksByID: [String: DownloadTrack] = [:]
    private var queueOrder: [String] = []
    private var albumTrackIDs: [String: [String]] = [:]
    private var restoredActiveTrackIDs: [String] = []
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @Published private var resolvingAlbumIDs: Set<String> = []
    private var lastSearchQuery = ""
    private var lastSearchProvider: DownloadView.SearchProvider = .appleMusic
    private let songPageSize = 25
    private let albumPageSize = 15
    private let playlistPageSize = 15
    private var metadataCachedSearchTracks: [DownloadTrack] = []
    private var metadataCachedSearchAlbums: [DownloadAlbum] = []
    private var metadataCachedSearchPlaylists: [DownloadAlbum] = []
    private var metadataAlbumTrackCache: [String: [DownloadTrack]] = [:]
    private var metadataDeezerOffset = 0
    private var metadataCanFetchMoreDeezer = false
    private var previewPlayer: AVPlayer?
    private var previewEndObserver: NSObjectProtocol?
    private var previewStatusObserver: NSKeyValueObservation?
    private var cachedPreviewURLs: [String: URL] = [:]
    private var preparedBackgroundPlansByTrackID: [String: PreparedBackgroundDownloadPlan] = [:]
    private var backgroundPreparationTasks: [String: Task<PreparedBackgroundDownloadPlan?, Never>] = [:]
    private var cancelledBackgroundTrackIDs = Set<String>()

    private var backgroundDownloadsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "backgroundDownloadsEnabled")
    }

    private var canAdvanceBackgroundQueueNow: Bool {
        true
    }

    init() {
        restorePersistedQueue()
        lifecycleObservers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appDidBecomeActive()
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appDidEnterBackground()
            }
        ]
        if backgroundDownloadsEnabled {
            Task { await recoverBackgroundDownloadIfNeeded() }
        }
    }

    var queueProgress: Double {
        guard totalQueueCount > 0 else { return 0 }
        return Double(completedQueueCount) / Double(totalQueueCount)
    }

    var aggregateDownloadProgress: Double {
        guard totalQueueCount > 0 else { return 0 }
        let activeCredit = downloadProgressByTrackID.values.reduce(0, +)
        return min((Double(completedQueueCount) + activeCredit) / Double(totalQueueCount), 1)
    }

    var aggregateDownloadSpeedBps: Double {
        downloadSpeedByTrackID.values.reduce(0, +)
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
        }
    }

    var queueStatusText: String {
        if isPaused {
            return "Paused"
        }
        guard totalQueueCount > 0 else { return "Apple Music Search" }
        if !activeDownloadTrackIDs.isEmpty, completedQueueCount < totalQueueCount {
            return "\(min(completedQueueCount + activeDownloadTrackIDs.count, totalQueueCount))/\(totalQueueCount)"
        }
        return "\(completedQueueCount)/\(totalQueueCount)"
    }

    var queueCounterText: String {
        if isPaused {
            return "Paused"
        }
        guard totalQueueCount > 0 else { return "Queue" }
        if !activeDownloadTrackIDs.isEmpty {
            return "\(min(completedQueueCount + activeDownloadTrackIDs.count, totalQueueCount))/\(totalQueueCount)"
        }
        return "\(min(completedQueueCount, totalQueueCount))/\(totalQueueCount)"
    }

    func state(for trackID: String) -> DownloadTrackState {
        trackStates[trackID] ?? .idle
    }

    func canEnqueue(trackID: String) -> Bool {
        switch state(for: trackID) {
        case .idle, .failed:
            return true
        case .queued, .downloading, .done:
            return false
        }
    }

    func state(forAlbumID albumID: String) -> DownloadTrackState {
        guard let trackIDs = albumTrackIDs[albumID], !trackIDs.isEmpty else { return .idle }
        let states = trackIDs.map { state(for: $0) }
        if states.contains(.downloading) { return .downloading }
        if states.contains(.queued) { return .queued }
        if !states.isEmpty && states.allSatisfy({ $0 == .done }) { return .done }
        if states.contains(.failed) { return .failed }
        return .idle
    }

    func isResolvingAlbum(albumID: String) -> Bool {
        resolvingAlbumIDs.contains(albumID)
    }

    func isPreviewPlaying(for trackID: String) -> Bool {
        activePreviewTrackID == trackID
    }

    func isPreviewLoading(for trackID: String) -> Bool {
        previewLoadingTrackIDs.contains(trackID)
    }

    func togglePreview(for track: DownloadTrack) {
        Task { @MainActor in
            if activePreviewTrackID == track.id {
                stopPreview()
                return
            }

            previewLoadingTrackIDs.insert(track.id)
            defer { previewLoadingTrackIDs.remove(track.id) }

            guard let url = await previewURL(for: track) else {
                errorText = "No preview available for \(track.name)."
                return
            }

            playPreview(for: track.id, url: url)
        }
    }

    private func playPreview(for trackID: String, url: URL) {
        stopPreview()

        guard configurePreviewAudioSession() else {
            errorText = "Could not start audio preview."
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 1.0
        previewPlayer = player
        activePreviewTrackID = trackID

        previewStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .failed {
                    self.errorText = "Could not play preview for this song."
                    self.log("Preview item failed: \(item.error?.localizedDescription ?? "unknown error")")
                    self.stopPreview()
                }
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopPreview()
            }
        }

        player.play()
    }

    private func configurePreviewAudioSession() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()

        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playback, .default, []),
            (.playback, .default, [.mixWithOthers]),
            (.ambient, .default, [])
        ]

        for (category, mode, options) in attempts {
            do {
                try audioSession.setCategory(category, mode: mode, options: options)
                try audioSession.setActive(true)
                return true
            } catch {
                log("Preview audio session setup failed for \(category.rawValue): \(error.localizedDescription)")
            }
        }

        return false
    }

    private func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        activePreviewTrackID = nil

        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }

        previewStatusObserver = nil
    }

    private func previewURL(for track: DownloadTrack) async -> URL? {
        if let trackPreviewURL = track.previewURL {
            cachedPreviewURLs[track.id] = trackPreviewURL
            return trackPreviewURL
        }

        if let cached = cachedPreviewURLs[track.id] {
            return cached
        }

        let resolved: URL?
        switch track.provider {
        case .appleMusic, .spotify, .metadata, .itunes, .deezer:
            resolved = await resolveITunesPreviewURL(for: track)
        }

        if let resolved {
            cachedPreviewURLs[track.id] = resolved
        }

        return resolved
    }

    private func resolveITunesPreviewURL(for track: DownloadTrack) async -> URL? {
        let query = [track.artistLine, track.name]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let results = await SongMetadata.searchiTunes(query: query, limit: 10)
        let match = results.first { song in
            guard
                let title = song.trackName,
                let artist = song.artistName
            else {
                return false
            }

            let normalizedTrackTitle = DownloadSupport.normalizedSearchValue(track.name)
            let normalizedSongTitle = DownloadSupport.normalizedSearchValue(title)
            guard normalizedTrackTitle == normalizedSongTitle else {
                return false
            }

            return matchesArtistLine(track.artistLine, artistName: artist)
        } ?? results.first

        return match?.previewUrl.flatMap(URL.init(string:))
    }

    func pauseQueue() {
        guard !isPaused else { return }
        isPaused = true
        for task in foregroundWorkerTasks.values {
            task.cancel()
        }
        if !activeDownloadTrackIDs.isEmpty {
            pushLiveActivityUpdate(phaseOverride: .paused)
        }
        log("Download queue paused by user.")
    }

    func resumeQueue() {
        guard isPaused else { return }
        isPaused = false
        log("Download queue resumed by user.")
        Task { await processQueueIfNeeded() }
    }

    func cancelQueue() {
        for task in foregroundWorkerTasks.values {
            task.cancel()
        }
        let activeIDsToCancel = activeDownloadTrackIDs
        let cancelledTrack = activeIDsToCancel.first.flatMap { knownTracksByID[$0] }
        for track in pendingQueue {
            trackStates[track.id] = .idle
        }
        pendingQueue.removeAll()
        for activeID in activeIDsToCancel {
            trackStates[activeID] = .idle
        }
        activeDownloadTrackIDs.removeAll()
        downloadProgressByTrackID.removeAll()
        downloadSpeedByTrackID.removeAll()
        totalQueueCount = 0
        completedQueueCount = 0
        isPaused = false
        if cancelledTrack != nil {
            endLiveActivityIfQueueFinished(finalPhase: .cancelled)
        } else {
            clearLiveActivity()
        }
        if backgroundDownloadsEnabled, !activeIDsToCancel.isEmpty {
            for activeID in activeIDsToCancel {
                cancelledBackgroundTrackIDs.insert(activeID)
            }
            Task {
                for activeID in activeIDsToCancel {
                    await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: activeID)
                }
            }
        }
        log("Download queue cancelled and cleared by user.")
        syncQueuePersistence()
    }

    func enqueue(track: DownloadTrack) {
        _ = enqueueMany([track])
    }

    @discardableResult
    func enqueue(tracks: [DownloadTrack], albumID: String? = nil) -> Int {
        if let albumID {
            albumTrackIDs[albumID] = tracks.map(\.id)
        }
        let added = enqueueMany(tracks)
        return added
    }

    func loadTracks(for album: DownloadAlbum) async -> [DownloadTrack] {
        guard !resolvingAlbumIDs.contains(album.id) else { return [] }
        resolvingAlbumIDs.insert(album.id)
        defer { resolvingAlbumIDs.remove(album.id) }
        switch album.provider {
        case .appleMusic:
            let albumID = album.albumIdentifier ?? album.id
            return await fetchAlbumTracks(albumID: albumID, fallbackAlbumName: album.name, sourceURL: album.sourceURL)
        case .spotify:
            if album.sourceURL.contains("spotify.com") {
                if let (_, tracks) = await fetchSpotifyAlbum(id: album.id, sourceURL: album.sourceURL) {
                    return tracks
                }
                return []
            } else {
                let albumID = album.albumIdentifier ?? album.id
                let amTracks = await fetchAlbumTracks(albumID: albumID, fallbackAlbumName: album.name, sourceURL: album.sourceURL)
                return amTracks.map { track in
                    DownloadTrack(
                        id: track.id,
                        name: track.name,
                        artistLine: track.artistLine,
                        albumName: track.albumName,
                        artworkURL: track.artworkURL,
                        isExplicit: track.isExplicit,
                        sourceURL: track.sourceURL,
                        sourceContext: track.sourceContext,
                        provider: .spotify,
                        artistIdentifier: track.artistIdentifier,
                        albumIdentifier: track.albumIdentifier,
                        previewURL: track.previewURL
                    )
                }
            }
        case .metadata, .itunes, .deezer:
            if let identifier = album.albumIdentifier,
               identifier.hasPrefix("deezer-album-"),
               let numericID = Int(identifier.dropFirst("deezer-album-".count)),
               let albumDetail = await SongMetadata.fetchDeezerAlbum(id: numericID) {
                let tracks = albumDetail.tracks.data.map { metadataTrack(from: $0) }
                if !tracks.isEmpty {
                    return tracks
                }
            }

            if let tracks = metadataAlbumTrackCache[album.id], !tracks.isEmpty {
                return tracks
            }
            let query = "\(album.artistLine) \(album.name)"
            let batch = await fetchMetadataSearchTracks(query: query, limit: 50, deezerIndex: 0, includeITunes: true)
            let matchingTracks = batch.tracks.filter { track in
                DownloadSupport.normalizedSearchValue(track.albumName) == DownloadSupport.normalizedSearchValue(album.name) &&
                matchesArtistLine(track.artistLine, artistName: album.artistLine)
            }
            return matchingTracks.isEmpty ? batch.tracks : matchingTracks
        }
    }

    func loadTracks(forPlaylist playlist: DownloadAlbum) async -> [DownloadTrack] {
        switch playlist.provider {
        case .appleMusic:
            let playlistID = playlist.albumIdentifier ?? playlist.id
            guard let playlistResult = await fetchAppleMusicPlaylist(id: playlistID, sourceURL: playlist.sourceURL) else { return [] }
            return playlistResult.relationships?.tracks?.data.map {
                DownloadTrack(
                    id: $0.id,
                    name: $0.attributes.name,
                    artistLine: $0.attributes.artistName,
                    albumName: $0.attributes.albumName ?? playlist.name,
                    artworkURL: $0.attributes.artwork?.artworkURL(width: 400, height: 400) ?? playlist.artworkURL,
                    isExplicit: $0.attributes.contentRating == "explicit",
                    sourceURL: $0.attributes.url ?? playlist.sourceURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: nil,
                    previewURL: nil
                )
            } ?? []
        case .spotify:
            if playlist.sourceURL.contains("spotify.com") {
                if let (_, tracks) = await fetchSpotifyPlaylist(id: playlist.id, sourceURL: playlist.sourceURL) {
                    return tracks
                }
                return []
            } else {
                let playlistID = playlist.albumIdentifier ?? playlist.id
                guard let playlistResult = await fetchAppleMusicPlaylist(id: playlistID, sourceURL: playlist.sourceURL) else { return [] }
                return playlistResult.relationships?.tracks?.data.map {
                    DownloadTrack(
                        id: $0.id,
                        name: $0.attributes.name,
                        artistLine: $0.attributes.artistName,
                        albumName: $0.attributes.albumName ?? playlist.name,
                        artworkURL: $0.attributes.artwork?.artworkURL(width: 400, height: 400) ?? playlist.artworkURL,
                        isExplicit: $0.attributes.contentRating == "explicit",
                        sourceURL: $0.attributes.url ?? playlist.sourceURL,
                        sourceContext: .song,
                        provider: .spotify,
                        artistIdentifier: nil,
                        albumIdentifier: nil,
                        previewURL: nil
                    )
                } ?? []
            }
        case .metadata, .itunes, .deezer:
            return []
        }
    }

    func enqueue(album: DownloadAlbum) async {
        let tracks = await loadTracks(for: album)
        guard !tracks.isEmpty else {
            errorText = "Could not load tracks for album \(album.name)"
            return
        }

        let added = enqueue(tracks: tracks, albumID: album.id)
        if added == 0 {
            errorText = "All tracks from \(album.name) are already queued or downloaded."
        } else {
            log("Queued \(added) tracks from album \(album.name)")
        }
    }

    func retry(trackID: String) {
        guard let track = knownTracksByID[trackID] else { return }
        errorText = nil
        trackFailureReasons.removeValue(forKey: trackID)
        trackQualityNotes.removeValue(forKey: trackID)
        _ = enqueueMany([track])
    }

    func removeFailed(trackID: String) {
        guard trackStates[trackID] == .failed else { return }
        trackStates.removeValue(forKey: trackID)
        trackFailureReasons.removeValue(forKey: trackID)
        queueOrder.removeAll { $0 == trackID }
        if totalQueueCount > completedQueueCount {
            totalQueueCount = max(0, totalQueueCount - 1)
        }
        if backgroundDownloadsEnabled {
            cancelledBackgroundTrackIDs.insert(trackID)
            Task {
                await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: trackID)
            }
        }
        syncQueuePersistence()
    }

    func clearAllFailed() {
        let failedIDs = Set(queueOrder.filter { trackStates[$0] == .failed })
        guard !failedIDs.isEmpty else { return }
        for id in failedIDs {
            trackStates.removeValue(forKey: id)
            trackFailureReasons.removeValue(forKey: id)
        }
        queueOrder.removeAll { failedIDs.contains($0) }
        if totalQueueCount > completedQueueCount {
            totalQueueCount = max(completedQueueCount, totalQueueCount - failedIDs.count)
        }
        if backgroundDownloadsEnabled {
            for id in failedIDs {
                cancelledBackgroundTrackIDs.insert(id)
            }
            Task {
                for id in failedIDs {
                    await BackgroundAudioDownloadManager.shared.cancelDownloads(forTrackID: id)
                }
            }
        }
        syncQueuePersistence()
    }

    func removeQueued(trackID: String) {
        guard trackStates[trackID] == .queued else { return }
        pendingQueue.removeAll { $0.id == trackID }
        trackStates.removeValue(forKey: trackID)
        queueOrder.removeAll { $0 == trackID }
        totalQueueCount = max(0, totalQueueCount - 1)
        completedQueueCount = min(completedQueueCount, totalQueueCount)
        syncQueuePersistence()
    }

    func retry(album: DownloadAlbum) async {
        errorText = nil

        if let knownTrackIDs = albumTrackIDs[album.id], !knownTrackIDs.isEmpty {
            let knownTracks = knownTrackIDs.compactMap { knownTracksByID[$0] }
            if !knownTracks.isEmpty {
                let added = enqueue(tracks: knownTracks, albumID: album.id)
                if added == 0 {
                    errorText = "No failed tracks from \(album.name) are available to retry."
                }
                return
            }
        }

        await enqueue(album: album)
    }

    func retry(playlist: DownloadAlbum) async {
        errorText = nil

        if let knownTrackIDs = albumTrackIDs[playlist.id], !knownTrackIDs.isEmpty {
            let knownTracks = knownTrackIDs.compactMap { knownTracksByID[$0] }
            if !knownTracks.isEmpty {
                let added = enqueue(tracks: knownTracks, albumID: playlist.id)
                if added == 0 {
                    errorText = "No failed tracks from \(playlist.name) are available to retry."
                }
                return
            }
        }

        let tracks = await loadTracks(forPlaylist: playlist)
        guard !tracks.isEmpty else {
            errorText = "Could not load tracks for playlist \(playlist.name)"
            return
        }

        let added = enqueue(tracks: tracks, albumID: playlist.id)
        if added == 0 {
            errorText = "All tracks from \(playlist.name) are already queued or downloaded."
        }
    }

    func search(query: String, provider: DownloadView.SearchProvider) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            artistResults = []
            songResults = []
            albumResults = []
            playlistResults = []
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            return
        }
        lastSearchQuery = trimmed
        lastSearchProvider = provider
        metadataCachedSearchTracks = []
        metadataCachedSearchAlbums = []
        metadataCachedSearchPlaylists = []
        metadataAlbumTrackCache = [:]
        metadataDeezerOffset = 0
        metadataCanFetchMoreDeezer = false
        isSearching = true
        errorText = nil
        defer { isSearching = false }

        if let directLink = parseDirectLink(from: trimmed) {
            let handled = await handleDirectLinkSearch(directLink)
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            if handled {
                return
            }
        }

        if isUnsupportedPastedTidalLink(trimmed) {
            errorText = "Tidal pasted links are not supported. Paste an Apple Music link instead."
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            return
        }

        switch provider {
        case .appleMusic:
            artistResults = []
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: trimmed, limit: songPageSize, offset: 0)
            let albums = await searchAlbums(query: trimmed, limit: albumPageSize, offset: 0)
            let playlists = await searchPlaylists(query: trimmed, limit: playlistPageSize, offset: 0)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

            songResults = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            albumResults = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults = playlists.map { item in
                let playlistURL = "https://music.apple.com/\(region)/playlist/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: playlistURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            canLoadMoreSongs = songsHaveMore
            canLoadMoreAlbums = albums.count == albumPageSize
            canLoadMorePlaylists = playlists.count == playlistPageSize

        case .spotify:
            artistResults = []

            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: trimmed, limit: songPageSize, offset: 0)
            let albums = await searchAlbums(query: trimmed, limit: albumPageSize, offset: 0)
            let playlists = await searchPlaylists(query: trimmed, limit: playlistPageSize, offset: 0)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

            songResults = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .spotify,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            albumResults = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults = playlists.map { item in
                let playlistURL = "https://music.apple.com/\(region)/playlist/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: playlistURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            canLoadMoreSongs = songsHaveMore
            canLoadMoreAlbums = albums.count == albumPageSize
            canLoadMorePlaylists = playlists.count == playlistPageSize

        case .metadata:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: true
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false

        case .itunes:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: true,
                includeDeezer: false
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = 0
            metadataCanFetchMoreDeezer = false
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false

        case .deezer:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: false,
                includeDeezer: true
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMoreSongs() async {
        guard !isLoadingMoreSongs, canLoadMoreSongs, !lastSearchQuery.isEmpty else { return }
        isLoadingMoreSongs = true
        defer { isLoadingMoreSongs = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = songResults.count
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: lastSearchQuery, limit: songPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedSongs = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }
            songResults.append(contentsOf: mappedSongs.filter { incoming in
                !songResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreSongs = songsHaveMore
        case .spotify:
            let offset = songResults.count
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: lastSearchQuery, limit: songPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedSongs = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .spotify,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }
            songResults.append(contentsOf: mappedSongs.filter { incoming in
                !songResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreSongs = songsHaveMore
        case .metadata:
            await expandMetadataSearchCacheIfNeeded(minimumTrackCount: songResults.count + songPageSize)
            let nextCount = min(songResults.count + songPageSize, metadataCachedSearchTracks.count)
            songResults = Array(metadataCachedSearchTracks.prefix(nextCount))
            albumResults = Array(metadataCachedSearchAlbums.prefix(max(albumResults.count, min(albumPageSize, metadataCachedSearchAlbums.count))))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        case .itunes:
            canLoadMoreSongs = false
        case .deezer:
            await expandMetadataSearchCacheIfNeeded(minimumTrackCount: songResults.count + songPageSize)
            let nextCount = min(songResults.count + songPageSize, metadataCachedSearchTracks.count)
            songResults = Array(metadataCachedSearchTracks.prefix(nextCount))
            albumResults = Array(metadataCachedSearchAlbums.prefix(max(albumResults.count, min(albumPageSize, metadataCachedSearchAlbums.count))))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMoreAlbums() async {
        guard !isLoadingMoreAlbums, canLoadMoreAlbums, !lastSearchQuery.isEmpty else { return }
        isLoadingMoreAlbums = true
        defer { isLoadingMoreAlbums = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = albumResults.count
            let albums = await searchAlbums(query: lastSearchQuery, limit: albumPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedAlbums = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            albumResults.append(contentsOf: mappedAlbums.filter { incoming in
                !albumResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreAlbums = albums.count == albumPageSize
        case .spotify:
            let offset = albumResults.count
            let albums = await searchAlbums(query: lastSearchQuery, limit: albumPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedAlbums = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            albumResults.append(contentsOf: mappedAlbums.filter { incoming in
                !albumResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreAlbums = albums.count == albumPageSize
        case .metadata:
            let desiredAlbumCount = albumResults.count + albumPageSize
            await expandMetadataSearchCacheIfNeeded(minimumAlbumCount: desiredAlbumCount)
            albumResults = Array(metadataCachedSearchAlbums.prefix(min(desiredAlbumCount, metadataCachedSearchAlbums.count)))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        case .itunes:
            canLoadMoreAlbums = false
        case .deezer:
            let desiredAlbumCount = albumResults.count + albumPageSize
            await expandMetadataSearchCacheIfNeeded(minimumAlbumCount: desiredAlbumCount)
            albumResults = Array(metadataCachedSearchAlbums.prefix(min(desiredAlbumCount, metadataCachedSearchAlbums.count)))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMorePlaylists() async {
        guard !isLoadingMorePlaylists, canLoadMorePlaylists, !lastSearchQuery.isEmpty else { return }
        isLoadingMorePlaylists = true
        defer { isLoadingMorePlaylists = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = playlistResults.count
            let playlists = await searchPlaylists(query: lastSearchQuery, limit: playlistPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedPlaylists = playlists.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/playlist/\(item.id)",
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults.append(contentsOf: mappedPlaylists.filter { incoming in
                !playlistResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMorePlaylists = playlists.count == playlistPageSize
        case .spotify:
            let offset = playlistResults.count
            let playlists = await searchPlaylists(query: lastSearchQuery, limit: playlistPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedPlaylists = playlists.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/playlist/\(item.id)",
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults.append(contentsOf: mappedPlaylists.filter { incoming in
                !playlistResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMorePlaylists = playlists.count == playlistPageSize
        case .metadata, .itunes, .deezer:
            canLoadMorePlaylists = false
        }
    }

    func loadArtistProfile(for artist: DownloadArtist) async -> DownloadArtistProfile {
        switch artist.provider {
        case .appleMusic:
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let filteredSongs = await fetchAppleMusicArtistSongs(artistName: artist.name)
            let tracks = filteredSongs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            let filteredAlbums = await fetchAppleMusicArtistAlbums(artistName: artist.name)
            let mappedAlbums = filteredAlbums.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/album/\(item.id)",
                    provider: .appleMusic,
                    artistIdentifier: artist.id,
                    albumIdentifier: item.id
                )
            }

            return DownloadArtistProfile(tracks: tracks, albums: uniqueAlbums(mappedAlbums))

        case .metadata, .spotify, .itunes, .deezer:
            if artist.id.hasPrefix("deezer-artist-"),
               let numericID = Int(artist.id.dropFirst("deezer-artist-".count)) {
                let profile = await buildDeezerArtistProfile(id: numericID, fallbackName: artist.name)
                if !profile.tracks.isEmpty || !profile.albums.isEmpty {
                    return profile
                }
            }
            return await buildMetadataArtistProfile(for: artist.name)
        }
    }

    private func buildDeezerArtistProfile(id: Int, fallbackName: String) async -> DownloadArtistProfile {
        async let topTracksResult = SongMetadata.fetchDeezerArtistTopTracks(id: id, limit: 100)
        async let albumsResult = SongMetadata.fetchDeezerArtistAlbums(id: id, limit: 100)

        let tracks = await topTracksResult.map { metadataTrack(from: $0) }
        let albums = await albumsResult.map { summary in
            DownloadAlbum(
                id: "deezer-album-\(summary.id)",
                name: summary.title,
                artistLine: fallbackName,
                artworkURL: URL(string: summary.cover_xl),
                sourceURL: "https://www.deezer.com/album/\(summary.id)",
                provider: .metadata,
                artistIdentifier: "deezer-artist-\(id)",
                albumIdentifier: "deezer-album-\(summary.id)"
            )
        }
        return DownloadArtistProfile(tracks: tracks, albums: albums)
    }

    private func buildMetadataArtistProfile(for artistName: String) async -> DownloadArtistProfile {
        let batch = await fetchMetadataSearchTracks(
            query: artistName,
            limit: 100,
            deezerIndex: 0,
            includeITunes: true
        )
        let tracks = uniqueTracksForMetadataProfile(batch.tracks).filter {
            matchesArtistLine($0.artistLine, artistName: artistName)
        }
        let albums = uniqueAlbumsForMetadataProfile(buildMetadataAlbums(from: tracks))
        return DownloadArtistProfile(
            tracks: Array(tracks.prefix(100)),
            albums: Array(albums.prefix(100))
        )
    }

    private func handleDirectLinkSearch(_ link: DirectLinkKind) async -> Bool {
        artistResults = []
        songResults = []
        albumResults = []
        playlistResults = []
        pendingDirectLinkAction = nil

        switch link {
        case .appleSong(let id, let sourceURL):
            guard let song = await AppleMusicAPI.shared.fetchSong(id: id, urlHint: sourceURL) else {
                errorText = "Could not load that Apple Music song link."
                return true
            }
            let track = makeAppleMusicTrack(from: song, sourceURLOverride: sourceURL)
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .appleAlbum(let id, let sourceURL):
            guard let album = await fetchAppleMusicAlbum(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music album link."
                return true
            }
            let albumResult = makeAppleMusicAlbum(from: album, sourceURLOverride: sourceURL)
            let tracks = await fetchAlbumTracks(albumID: id, fallbackAlbumName: album.attributes?.name ?? "Unknown Album", sourceURL: sourceURL)
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .appleArtist(let id, let sourceURL):
            guard let artistData = await fetchAppleMusicArtist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music artist link."
                return true
            }
            let artist = DownloadArtist(
                id: artistData.id,
                name: artistData.attributes.name,
                provider: .appleMusic,
                artworkURL: artistData.attributes.artwork?.artworkURL(width: 400, height: 400)
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .applePlaylist(let id, let sourceURL):
            guard let playlist = await fetchAppleMusicPlaylist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music playlist link."
                return true
            }
            let tracks = playlist.relationships?.tracks?.data.map {
                makeAppleMusicTrack(from: $0)
            } ?? []
            let playlistContainer = DownloadAlbum(
                id: playlist.id,
                name: playlist.attributes.name,
                artistLine: playlist.attributes.curatorName ?? "Apple Music Playlist",
                artworkURL: playlist.attributes.artwork?.artworkURL(width: 400, height: 400) ?? tracks.first?.artworkURL,
                sourceURL: sourceURL,
                provider: .appleMusic,
                artistIdentifier: nil,
                albumIdentifier: playlist.id
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .spotifyTrack(let id, let sourceURL):
            guard let track = await fetchSpotifyTrack(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify track link."
                return true
            }
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .spotifyAlbum(let id, let sourceURL):
            guard let (albumResult, tracks) = await fetchSpotifyAlbum(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify album link."
                return true
            }
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .spotifyArtist(let id, let sourceURL):
            guard let artist = await fetchSpotifyArtist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify artist link."
                return true
            }
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .spotifyPlaylist(let id, let sourceURL):
            guard let (playlistContainer, tracks) = await fetchSpotifyPlaylist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify playlist link."
                return true
            }
            albumTrackIDs[playlistContainer.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .deezerTrack(let id, let sourceURL):
            guard let numericID = Int(id), let song = await SongMetadata.fetchDeezerTrack(id: numericID) else {
                errorText = "Could not load that Deezer track link."
                return true
            }
            let track = metadataTrack(from: song, sourceURLOverride: sourceURL)
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .deezerAlbum(let id, let sourceURL):
            guard let numericID = Int(id), let albumDetail = await SongMetadata.fetchDeezerAlbum(id: numericID) else {
                errorText = "Could not load that Deezer album link."
                return true
            }
            let tracks = albumDetail.tracks.data.map { metadataTrack(from: $0) }
            guard let firstTrack = tracks.first else {
                errorText = "Could not load that Deezer album link."
                return true
            }
            let albumResult = DownloadAlbum(
                id: firstTrack.albumIdentifier ?? "deezer-album-\(albumDetail.id)",
                name: albumDetail.title,
                artistLine: albumDetail.artist.name,
                artworkURL: URL(string: albumDetail.cover_xl),
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: firstTrack.artistIdentifier,
                albumIdentifier: firstTrack.albumIdentifier
            )
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .deezerArtist(let id, _):
            guard let numericID = Int(id), let artistDetail = await SongMetadata.fetchDeezerArtist(id: numericID) else {
                errorText = "Could not load that Deezer artist link."
                return true
            }
            let artist = DownloadArtist(
                id: "deezer-artist-\(artistDetail.id)",
                name: artistDetail.name,
                provider: .metadata,
                artworkURL: URL(string: artistDetail.picture_xl)
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .deezerPlaylist(let id, let sourceURL):
            guard let numericID = Int(id), let playlistDetail = await SongMetadata.fetchDeezerPlaylist(id: numericID) else {
                errorText = "Could not load that Deezer playlist link."
                return true
            }
            let tracks = playlistDetail.tracks.data.map { metadataTrack(from: $0) }
            guard !tracks.isEmpty else {
                errorText = "Could not load that Deezer playlist link."
                return true
            }
            let playlistContainerID = "deezer-playlist-\(playlistDetail.id)"
            let playlistContainer = DownloadAlbum(
                id: playlistContainerID,
                name: playlistDetail.title,
                artistLine: playlistDetail.creator.name,
                artworkURL: URL(string: playlistDetail.picture_xl),
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: playlistContainerID
            )
            albumTrackIDs[playlistContainerID] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .deezerShortLink(let sourceURL):
            if let resolvedURL = await resolveDeezerShortLink(sourceURL),
               let mappedDeezerLink = parseDirectLink(from: resolvedURL) {
                return await handleDirectLinkSearch(mappedDeezerLink)
            }
            errorText = "Could not resolve that Deezer link."
            return true
        }
    }

    private func parseDirectLink(from value: String) -> DirectLinkKind? {
        guard let components = URLComponents(string: value),
              let host = components.host?.lowercased() else {
            return nil
        }

        let sourceURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        if host.contains("music.apple.com") {
            if let songID = components.queryItems?.first(where: { $0.name == "i" })?.value, !songID.isEmpty {
                return .appleSong(id: songID, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "song"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleSong(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .applePlaylist(id: id, sourceURL: sourceURL)
            }
        } else if host.contains("spotify.com") {
            if let index = pathParts.firstIndex(of: "track"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyTrack(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyPlaylist(id: id, sourceURL: sourceURL)
            }
        } else if host.contains("deezer.page.link") || host == "link.deezer.com" {
            return .deezerShortLink(sourceURL: sourceURL)
        } else if host.contains("deezer.com") {
            if let index = pathParts.firstIndex(of: "track"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerTrack(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerPlaylist(id: id, sourceURL: sourceURL)
            }
        }

        return nil
    }

    private func isUnsupportedPastedTidalLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let host = components.host?.lowercased() else {
            return false
        }
        return host.contains("tidal.com")
    }

    private func resolveDeezerShortLink(_ sourceURL: String) async -> String? {
        guard let url = URL(string: sourceURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let finalURL = response.url, finalURL.host?.lowercased().contains("deezer.com") == true else {
                return nil
            }
            return finalURL.absoluteString
        } catch {
            log("Deezer short link resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeAppleMusicTrack(
        from item: AppleMusicAPI.AppleMusicSong,
        sourceURLOverride: String? = nil,
        provider: DownloadView.SearchProvider = .appleMusic,
        trackIDOverride: String? = nil
    ) -> DownloadTrack {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let songURL = sourceURLOverride ?? item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
        return DownloadTrack(
            id: trackIDOverride ?? item.id,
            name: item.attributes.name,
            artistLine: item.attributes.artistName,
            albumName: item.attributes.albumName ?? "Unknown Album",
            artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
            isExplicit: item.attributes.contentRating == "explicit",
            sourceURL: songURL,
            sourceContext: .song,
            provider: provider,
            artistIdentifier: item.relationships?.artists?.data.first?.id,
            albumIdentifier: item.relationships?.albums?.data.first?.id,
            previewURL: nil
        )
    }

    private func makeAppleMusicAlbum(
        from item: AppleMusicAPI.AppleMusicSong,
        provider: DownloadView.SearchProvider = .appleMusic,
        sourceURLOverride: String? = nil
    ) -> DownloadAlbum? {
        guard let albumID = item.relationships?.albums?.data.first?.id else {
            return nil
        }
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        return DownloadAlbum(
            id: albumID,
            name: item.attributes.albumName ?? "Unknown Album",
            artistLine: item.attributes.artistName,
            artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
            sourceURL: sourceURLOverride ?? "https://music.apple.com/\(region)/album/\(albumID)",
            provider: provider,
            artistIdentifier: item.relationships?.artists?.data.first?.id,
            albumIdentifier: albumID
        )
    }

    private func makeAppleMusicAlbum(
        from item: AppleMusicAlbumDetailsData,
        sourceURLOverride: String? = nil
    ) -> DownloadAlbum {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let albumID = item.id ?? item.attributes?.playParams?.id ?? "unknown-album"
        return DownloadAlbum(
            id: albumID,
            name: item.attributes?.name ?? "Unknown Album",
            artistLine: item.attributes?.artistName ?? "Unknown Artist",
            artworkURL: item.attributes?.artwork?.artworkURL(width: 400, height: 400),
            sourceURL: sourceURLOverride ?? "https://music.apple.com/\(region)/album/\(albumID)",
            provider: .appleMusic,
            artistIdentifier: nil,
            albumIdentifier: albumID
        )
    }

    private func fetchAppleMusicArtistSongs(artistName: String) async -> [AppleMusicAPI.AppleMusicSong] {
        let pageSize = 50
        let maxPages = 5
        var offset = 0
        var collected: [AppleMusicAPI.AppleMusicSong] = []
        var seenIDs = Set<String>()

        for _ in 0..<maxPages {
            let page = await AppleMusicAPI.shared.searchSongs(query: artistName, limit: pageSize, offset: offset)
            if page.isEmpty { break }

            let filteredPage = page.filter {
                matchesArtistLine($0.attributes.artistName, artistName: artistName)
            }

            for song in filteredPage where !seenIDs.contains(song.id) {
                seenIDs.insert(song.id)
                collected.append(song)
            }

            if page.count < pageSize { break }
            offset += pageSize
        }

        return collected
    }

    private func fetchAppleMusicArtistAlbums(artistName: String) async -> [AppleMusicAlbumResult] {
        let pageSize = 50
        let maxPages = 5
        var offset = 0
        var collected: [AppleMusicAlbumResult] = []
        var seenIDs = Set<String>()

        for _ in 0..<maxPages {
            let page = await searchAlbums(query: artistName, limit: pageSize, offset: offset)
            if page.isEmpty { break }

            let filteredPage = page.filter {
                matchesArtistLine($0.attributes.artistName, artistName: artistName)
            }

            for album in filteredPage where !seenIDs.contains(album.id) {
                seenIDs.insert(album.id)
                collected.append(album)
            }

            if page.count < pageSize { break }
            offset += pageSize
        }

        return collected
    }

    private func fetchAppleMusicAlbum(id: String, sourceURL: String? = nil) async -> AppleMusicAlbumDetailsData? {
        guard let fallbackAlbum = await AppleMusicAPI.shared.fetchAlbumPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        let fallbackTracks = await AppleMusicAPI.shared.fetchAlbumTracksPublic(id: id, urlHint: sourceURL)
        return AppleMusicAlbumDetailsData(
            id: fallbackAlbum.id,
            attributes: AppleMusicDirectAlbumAttributes(
                name: fallbackAlbum.name,
                artistName: fallbackAlbum.artistName,
                artwork: fallbackAlbum.artwork,
                playParams: AppleMusicPlayParams(id: fallbackAlbum.id)
            ),
            relationships: AppleMusicAlbumRelationships(
                tracks: AppleMusicAlbumTracksPage(data: fallbackTracks.map {
                    AppleMusicAlbumTrack(
                        id: $0.id,
                        attributes: AppleMusicAlbumTrackAttributes(
                            name: $0.attributes.name,
                            artistName: $0.attributes.artistName,
                            albumName: $0.attributes.albumName,
                            url: $0.attributes.url,
                            contentRating: $0.attributes.contentRating,
                            artwork: $0.attributes.artwork
                        )
                    )
                })
            )
        )
    }

    private func fetchAppleMusicArtist(id: String, sourceURL: String? = nil) async -> AppleMusicArtistResult? {
        guard let fallbackArtist = await AppleMusicAPI.shared.fetchArtistPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        return AppleMusicArtistResult(
            id: fallbackArtist.id,
            attributes: AppleMusicArtistAttributes(
                name: fallbackArtist.name,
                artwork: fallbackArtist.artwork
            )
        )
    }

    private func fetchAppleMusicPlaylist(id: String, sourceURL: String? = nil) async -> AppleMusicPlaylistResult? {
        guard let fallbackPlaylist = await AppleMusicAPI.shared.fetchPlaylistPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        let fallbackTracks = await AppleMusicAPI.shared.fetchPlaylistTracksPublic(id: id, urlHint: sourceURL)
        return AppleMusicPlaylistResult(
            id: fallbackPlaylist.id,
            attributes: AppleMusicPlaylistAttributes(
                name: fallbackPlaylist.name,
                curatorName: fallbackPlaylist.curatorName,
                artwork: fallbackPlaylist.artwork
            ),
            relationships: AppleMusicPlaylistRelationships(
                tracks: AppleMusicPlaylistTracksPage(data: fallbackTracks)
            )
        )
    }

    private func fetchMetadataSearchTracks(
        query: String,
        limit: Int,
        deezerIndex: Int,
        includeITunes: Bool,
        includeDeezer: Bool = true
    ) async -> MetadataSearchBatch {
        async let deezerResults = includeDeezer ? SongMetadata.searchDeezer(query: query, limit: limit, index: deezerIndex) : []
        async let iTunesResults = includeITunes ? SongMetadata.searchiTunes(query: query, limit: min(limit, 50)) : []

        let deezerSongs = await deezerResults
        let iTunesSongs = await iTunesResults
        let tracks = iTunesSongs.compactMap(metadataTrack(from:)) + deezerSongs.map { self.metadataTrack(from: $0) }
        return MetadataSearchBatch(tracks: tracks, deezerCount: deezerSongs.count)
    }

    private func expandMetadataSearchCacheIfNeeded(minimumTrackCount: Int? = nil, minimumAlbumCount: Int? = nil) async {
        while metadataCanFetchMoreDeezer {
            let hasEnoughTracks = minimumTrackCount.map { metadataCachedSearchTracks.count >= $0 } ?? false
            let hasEnoughAlbums = minimumAlbumCount.map { metadataCachedSearchAlbums.count >= $0 } ?? false

            if minimumTrackCount != nil, hasEnoughTracks {
                break
            }
            if minimumAlbumCount != nil, hasEnoughAlbums {
                break
            }

            let batch = await fetchMetadataSearchTracks(
                query: lastSearchQuery,
                limit: songPageSize,
                deezerIndex: metadataDeezerOffset,
                includeITunes: false
            )
            metadataDeezerOffset += batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize

            let existingIDs = Set(metadataCachedSearchTracks.map(\.id))
            let freshTracks = batch.tracks.filter { !existingIDs.contains($0.id) }
            if freshTracks.isEmpty {
                break
            }

            metadataCachedSearchTracks = uniqueTracks(metadataCachedSearchTracks + freshTracks)
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
        }
    }


    private func processQueueIfNeeded() async {
        if backgroundDownloadsEnabled && !isAppActive {
            startBackgroundQueueIfNeeded()
            return
        }
        guard !isPaused else { return }

        while activeDownloadTrackIDs.count < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            log("Dequeued track \(track.id) (\(track.name)) remaining=\(pendingQueue.count) active=\(activeDownloadTrackIDs.count + 1)/\(maxConcurrentDownloads)")
            startForegroundWorker(for: track)
        }
    }

    private func startForegroundWorker(for track: DownloadTrack) {
        errorText = nil
        activeDownloadTrackIDs.insert(track.id)
        trackStates[track.id] = .downloading
        downloadProgressByTrackID[track.id] = 0
        downloadSpeedByTrackID[track.id] = 0
        beginBackgroundTaskIfNeeded()
        pushLiveActivityUpdate(phaseOverride: .preparing)
        syncQueuePersistence()

        let spacing: Duration = isLosslessDownloadFormat ? .milliseconds(900) : .milliseconds(300)
        foregroundWorkerTasks[track.id] = Task { [weak self] in
            await self?.downloadStartPacer.waitForNextSlot(minSpacing: spacing)
            await self?.runForegroundWorker(track)
        }
    }

    private func runForegroundWorker(_ track: DownloadTrack) async {
        do {
            let outcome = try await downloadWithFallbacks(track: track)
            log("Download finished via \(outcome.backendLabel): \(outcome.fileURL.lastPathComponent)")
            try await finalizeDownloadedTrack(fileURL: outcome.fileURL, track: track, backendLabel: outcome.backendLabel)
        } catch {
            if Task.isCancelled {
                let isBackgroundHandoff = pendingBackgroundHandoffTrackIDs.remove(track.id) != nil
                log(isBackgroundHandoff ? "Download cancelled for background handoff." : "Download cancelled/paused by user.")
                trackStates[track.id] = .idle
                if isPaused || isBackgroundHandoff {
                    pendingQueue.insert(track, at: 0)
                }
                finishForegroundWorker(for: track.id, incrementCompleted: false)
                if isPaused {
                    pushLiveActivityUpdate(phaseOverride: .paused)
                } else if !isBackgroundHandoff {
                    endLiveActivityIfQueueFinished(finalPhase: .cancelled)
                }
                return
            }
            let message = downloadFailureMessage(for: track, error: error)
            log("Download failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
            finishForegroundWorker(for: track.id, incrementCompleted: true)
            endLiveActivityIfQueueFinished(finalPhase: .failed)
            return
        }

        finishForegroundWorker(for: track.id, incrementCompleted: true)
        endLiveActivityIfQueueFinished(finalPhase: .completed)
    }

    private func finishForegroundWorker(for trackID: String, incrementCompleted: Bool) {
        foregroundWorkerTasks[trackID] = nil
        activeDownloadTrackIDs.remove(trackID)
        downloadProgressByTrackID[trackID] = nil
        downloadSpeedByTrackID[trackID] = nil
        if incrementCompleted {
            completedQueueCount += 1
        }
        if activeDownloadTrackIDs.isEmpty && pendingQueue.isEmpty {
            endBackgroundTaskIfNeeded()
        }
        syncQueuePersistence()
        if !isPaused {
            Task { await processQueueIfNeeded() }
        }
    }

    private func startBackgroundQueueIfNeeded() {
        guard backgroundDownloadsEnabled else { return }
        guard !isAppActive else { return }
        guard !isPaused else { return }
        guard !pendingQueue.isEmpty else { return }
        guard canAdvanceBackgroundQueueNow else {
            log("Background queue has pending tracks, but next track will wait until the app is active again.")
            syncQueuePersistence()
            return
        }

        while activeDownloadTrackIDs.count < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            log("Starting background-native queue step for \(track.id) (\(track.name)) remaining=\(pendingQueue.count) active=\(activeDownloadTrackIDs.count + 1)/\(maxConcurrentDownloads)")
            errorText = nil
            activeDownloadTrackIDs.insert(track.id)
            trackStates[track.id] = .downloading
            downloadProgressByTrackID[track.id] = 0
            downloadSpeedByTrackID[track.id] = 0
            pushLiveActivityUpdate(phaseOverride: .preparing)
            syncQueuePersistence()
            primeBackgroundPreparation()

            let spacing: Duration = isLosslessDownloadFormat ? .milliseconds(900) : .milliseconds(300)
            Task { [weak self] in
                await self?.downloadStartPacer.waitForNextSlot(minSpacing: spacing)
                await self?.processBackgroundQueuedTrack(track)
            }
        }
    }

    private func processBackgroundQueuedTrack(_ track: DownloadTrack) async {
        let taskState = BackgroundTaskState()
        taskState.id = UIApplication.shared.beginBackgroundTask(withName: "DownloadTrack-\(track.id)") {
            guard taskState.id != .invalid else { return }
            Logger.shared.log("[Download] Background task expired for \(track.id) while queue was active")
            UIApplication.shared.endBackgroundTask(taskState.id)
            taskState.id = .invalid
        }
        defer {
            if taskState.id != .invalid {
                UIApplication.shared.endBackgroundTask(taskState.id)
                taskState.id = .invalid
            }
        }
        do {
            let outcome: BackendDownloadOutcome
            if let plan = await consumePreparedBackgroundPlan(for: track) {
                log("Using prepared background plan for \(track.id) with \(plan.candidates.count) candidate(s).")
                do {
                    if let preparedOutcome = try await executeCandidatesUntilSuccess(
                        plan.candidates,
                        trackID: track.id,
                        suggestedName: plan.suggestedName,
                        fallbackExtension: plan.fallbackExtension
                    ) {
                        outcome = preparedOutcome
                    } else {
                        outcome = try await downloadWithFallbacks(track: track)
                    }
                } catch {
                    log("Prepared background plan failed for \(track.id): \(error.localizedDescription). Falling back to full resolution.")
                    outcome = try await downloadWithFallbacks(track: track)
                }
            } else {
                outcome = try await downloadWithFallbacks(track: track)
            }
            log("Background-native queue finished via \(outcome.backendLabel): \(outcome.fileURL.lastPathComponent)")
            try await finalizeDownloadedTrack(fileURL: outcome.fileURL, track: track, backendLabel: outcome.backendLabel)
        } catch {
            if Task.isCancelled {
                log("Background-native queue cancelled/paused by user.")
                trackStates[track.id] = .idle
                if isPaused {
                    pendingQueue.insert(track, at: 0)
                }
                clearActiveBackgroundTrack(track.id)
                if isPaused {
                    pushLiveActivityUpdate(phaseOverride: .paused)
                } else {
                    endLiveActivityIfQueueFinished(finalPhase: .cancelled)
                }
                syncQueuePersistence()
                return
            }

            let message = downloadFailureMessage(for: track, error: error)
            log("Background-native queue failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
        }

        completedQueueCount += 1
        clearActiveBackgroundTrack(track.id)
        if trackStates[track.id] == .done {
            await showDownloadCompletion(for: track, completedCount: completedQueueCount)
        } else {
            endLiveActivityIfQueueFinished(finalPhase: .failed)
        }
        syncQueuePersistence()
        continueBackgroundQueueIfAllowed()
    }

    private func clearActiveBackgroundTrack(_ trackID: String) {
        activeDownloadTrackIDs.remove(trackID)
        downloadProgressByTrackID[trackID] = nil
        downloadSpeedByTrackID[trackID] = nil
    }

    private func showDownloadCompletion(for track: DownloadTrack, completedCount: Int) async {
        if completedCount >= totalQueueCount || (pendingQueue.isEmpty && activeDownloadTrackIDs.isEmpty) {
            endLiveActivityIfQueueFinished(finalPhase: .allCompleted)
            return
        }

        pushLiveActivityUpdate(phaseOverride: .completed)
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    private func primeBackgroundPreparation() {
        guard backgroundDownloadsEnabled else { return }
        for track in pendingQueue.prefix(3) {
            scheduleBackgroundPreparationIfNeeded(for: track)
        }
    }

    private func continueBackgroundQueueIfAllowed() {
        guard backgroundDownloadsEnabled else { return }
        guard !pendingQueue.isEmpty else { return }
        guard !isPaused else { return }

        if isAppActive {
            Task { await processQueueIfNeeded() }
        } else if canAdvanceBackgroundQueueNow {
            primeBackgroundPreparation()
            startBackgroundQueueIfNeeded()
        } else {
            log("Current background transfer finished. Remaining queued tracks will resume when the app becomes active.")
            syncQueuePersistence()
        }
    }

    func appDidBecomeActive() {
        isAppActive = true
        Task { await processQueueIfNeeded() }
    }

    func appDidEnterBackground() {
        isAppActive = false
        guard backgroundDownloadsEnabled else { return }
        guard !foregroundWorkerTasks.isEmpty else {
            startBackgroundQueueIfNeeded()
            return
        }

        log("App entered background with \(foregroundWorkerTasks.count) foreground download(s) in flight — handing off to background transfer.")
        for (trackID, task) in foregroundWorkerTasks {
            pendingBackgroundHandoffTrackIDs.insert(trackID)
            task.cancel()
        }
    }

    private func scheduleBackgroundPreparationIfNeeded(for track: DownloadTrack) {
        guard backgroundDownloadsEnabled else { return }
        guard preparedBackgroundPlansByTrackID[track.id] == nil else { return }
        guard backgroundPreparationTasks[track.id] == nil else { return }

        backgroundPreparationTasks[track.id] = Task { [weak self] in
            guard let self else { return nil }
            return await self.prepareBackgroundDownloadPlan(for: track)
        }
    }

    private func consumePreparedBackgroundPlan(for track: DownloadTrack) async -> PreparedBackgroundDownloadPlan? {
        if let plan = preparedBackgroundPlansByTrackID.removeValue(forKey: track.id) {
            backgroundPreparationTasks[track.id] = nil
            return plan
        }

        if let task = backgroundPreparationTasks.removeValue(forKey: track.id) {
            let plan = await task.value
            return plan
        }

        return nil
    }

    private func prepareBackgroundDownloadPlan(for track: DownloadTrack) async -> PreparedBackgroundDownloadPlan? {
        let suggestedName = "\(track.artistLine) - \(track.name)"
        let fallbackExtension = "flac"

        do {
            let resolvedSource = await resolvedPrimaryDownloadSource(for: track)
            let candidates = try await primaryCandidates(for: resolvedSource, track: track)
            guard !candidates.isEmpty else {
                log("Background preparation produced no candidates for \(track.id).")
                return nil
            }
            log("Prepared background plan for \(track.id) with \(candidates.count) candidate(s).")
            let plan = PreparedBackgroundDownloadPlan(
                candidates: candidates,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension
            )
            preparedBackgroundPlansByTrackID[track.id] = plan
            return plan
        } catch {
            log("Background preparation failed for \(track.id): \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func enqueueMany(_ tracks: [DownloadTrack]) -> Int {
        let validTracks = tracks.filter { canEnqueue(trackID: $0.id) }
        guard !validTracks.isEmpty else { return 0 }

        if totalQueueCount == completedQueueCount && activeDownloadTrackIDs.isEmpty && pendingQueue.isEmpty {
            totalQueueCount = 0
            completedQueueCount = 0
        }

        for track in validTracks {
            cancelledBackgroundTrackIDs.remove(track.id)
            knownTracksByID[track.id] = track
            if !queueOrder.contains(track.id) {
                queueOrder.append(track.id)
            }
            pendingQueue.append(track)
            trackStates[track.id] = .queued
            totalQueueCount += 1
        }

        syncQueuePersistence()
        if !isPaused {
            if backgroundDownloadsEnabled && !isAppActive {
                primeBackgroundPreparation()
            }
            Task { await processQueueIfNeeded() }
        }
        return validTracks.count
    }

    private func enrichDownloadedSong(_ initialSong: SongMetadata, sourceTrack: DownloadTrack) async -> SongMetadata {
        await SongMetadata.enrichDownloadedSong(initialSong, sourceTrack: sourceTrack)
    }

    private func downloadedFileLooksLikeAudio(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 32)) ?? Data()
        guard !header.isEmpty else { return false }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "opus":
            guard header.count >= 36 else { return false }
            return String(data: header.prefix(4), encoding: .ascii) == "OggS" &&
                String(data: header[28..<36], encoding: .ascii) == "OpusHead"
        case "flac":
            return header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "fLaC"
        case "mp3":
            if header.count >= 3 && String(data: header.prefix(3), encoding: .ascii) == "ID3" {
                return true
            }
            guard header.count >= 2 else { return false }
            return header[0] == 0xFF && (header[1] & 0xE0) == 0xE0
        case "m4a", "mp4", "aac", "alac":
            guard header.count >= 12 else { return false }
            return String(data: header[4..<8], encoding: .ascii) == "ftyp"
        case "wav", "wave":
            guard header.count >= 12 else { return false }
            return String(data: header.prefix(4), encoding: .ascii) == "RIFF" &&
                String(data: header[8..<12], encoding: .ascii) == "WAVE"
        default:
            if header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "fLaC" {
                return true
            }
            if header.count >= 3 && String(data: header.prefix(3), encoding: .ascii) == "ID3" {
                return true
            }
            if header.count >= 12 &&
                String(data: header[4..<8], encoding: .ascii) == "ftyp" {
                return true
            }
            if header.count >= 12 &&
                String(data: header.prefix(4), encoding: .ascii) == "RIFF" &&
                String(data: header[8..<12], encoding: .ascii) == "WAVE" {
                return true
            }
            if header.count >= 36 &&
                String(data: header.prefix(4), encoding: .ascii) == "OggS" &&
                String(data: header[28..<36], encoding: .ascii) == "OpusHead" {
                return true
            }
            if header.count >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                return true
            }
            return false
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundDownloadsEnabled else { return }
        guard backgroundTaskID == .invalid else { return }
        let taskState = BackgroundTaskState()
        taskState.id = UIApplication.shared.beginBackgroundTask(withName: "DownloadQueue") {
            guard taskState.id != .invalid else { return }
            Logger.shared.log("[Download] Background task expired while queue was active")
            let expiredID = taskState.id
            UIApplication.shared.endBackgroundTask(expiredID)
            taskState.id = .invalid
            Task { @MainActor [weak self] in
                self?.clearBackgroundTaskID(expiredID)
            }
        }
        backgroundTaskID = taskState.id
    }

    private func clearBackgroundTaskID(_ id: UIBackgroundTaskIdentifier) {
        if backgroundTaskID == id {
            backgroundTaskID = .invalid
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func finalizeDownloadedTrack(
        fileURL: URL,
        track: DownloadTrack,
        backendLabel: String
    ) async throws {
        log("Finalizing \(track.id) via \(backendLabel) from \(fileURL.lastPathComponent)")
        if backgroundDownloadsEnabled && cancelledBackgroundTrackIDs.remove(track.id) != nil {
            trackStates[track.id] = .idle
            log("Ignoring completed background transfer for cancelled track \(track.name) [\(track.id)]")
            return
        }

        if backgroundDownloadsEnabled && hasHandedOffDownloadedFile(trackID: track.id) {
            trackStates[track.id] = .done
            log("Skipping duplicate background handoff for \(track.name) [\(track.id)]")
            return
        }

        var song = try await SongMetadata.fromURL(fileURL)
        if backgroundDownloadsEnabled {
            trackStates[track.id] = .done
            handOffDownloadedFileForMainImport(song.localURL, track: track)
            log("Queued downloaded file for main import pipeline: \(song.title) [\(track.id)]")
        } else {
            song = await enrichDownloadedSong(song, sourceTrack: track)
            song = persistDownloadedSongIfNeeded(song)
            emittedSongs.append(song)
            trackStates[track.id] = .done
            log("Track finished with immediate metadata enrichment: \(song.title) [\(track.id)]")
        }
    }

    private func recoverBackgroundDownloadIfNeeded() async {
        guard backgroundDownloadsEnabled else {
            if !restoredActiveTrackIDs.isEmpty {
                log("Background download recovery skipped because background downloads are disabled.")
            }
            restoredActiveTrackIDs = []
            return
        }
        guard !restoredActiveTrackIDs.isEmpty else { return }

        let idsToRecover = restoredActiveTrackIDs
        restoredActiveTrackIDs = []
        for activeID in idsToRecover {
            await recoverSingleBackgroundDownload(activeID: activeID)
        }
    }

    private func recoverSingleBackgroundDownload(activeID: String) async {
        guard let track = knownTracksByID[activeID] else { return }

        let attached = await bindRecoveredBackgroundDownload(activeID: activeID, track: track)

        if attached {
            activeDownloadTrackIDs.insert(activeID)
            trackStates[activeID] = .downloading
            downloadProgressByTrackID[activeID] = 0
            downloadSpeedByTrackID[activeID] = 0
            pushLiveActivityUpdate(phaseOverride: .downloading)
            log("Reattached to active background download for \(track.name).")
            syncQueuePersistence()
            return
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if await bindRecoveredBackgroundDownload(activeID: activeID, track: track) {
            activeDownloadTrackIDs.insert(activeID)
            trackStates[activeID] = .downloading
            downloadProgressByTrackID[activeID] = 0
            downloadSpeedByTrackID[activeID] = 0
            log("Reattached to active background download for \(track.name) after retry.")
            syncQueuePersistence()
            return
        }

        if hasHandedOffDownloadedFile(trackID: activeID) {
            log("Recovered active download for \(track.name) was already handed off. Marking complete.")
            trackStates[activeID] = .done
            completedQueueCount = min(completedQueueCount + 1, totalQueueCount)
            syncQueuePersistence()
            continueBackgroundQueueIfAllowed()
            return
        }

        log("Failed to reattach to background download for \(track.name) after retry. Requeueing.")
        pendingQueue.insert(track, at: 0)
        trackStates[activeID] = .queued
        syncQueuePersistence()

        if !isPaused {
            if backgroundDownloadsEnabled {
                continueBackgroundQueueIfAllowed()
            } else {
                Task { await processQueueIfNeeded() }
            }
        }
    }

    private func bindRecoveredBackgroundDownload(activeID: String, track: DownloadTrack) async -> Bool {
        await BackgroundAudioDownloadManager.shared.bindToActiveDownload(
            forTrackID: activeID,
            progress: { [weak self] progress, speedBps in
                self?.updateVisibleDownloadProgress(progress, speedBps: speedBps, trackID: activeID)
            },
            completion: { [weak self] result in
                guard let self else { return }
                Task { await self.handleRecoveredBackgroundDownloadResult(result, for: track) }
            }
        )
    }

    private func handleRecoveredBackgroundDownloadResult(
        _ result: Result<BackgroundDownloadResult, Error>,
        for track: DownloadTrack
    ) async {
        guard !cancelledBackgroundTrackIDs.contains(track.id) else {
            log("Ignoring recovered background result for \(track.id) — it was removed from the queue.")
            clearActiveBackgroundTrack(track.id)
            cancelledBackgroundTrackIDs.remove(track.id)
            return
        }
        switch result {
        case .success(let backgroundResult):
            do {
                if recoveredBackgroundResultNeedsRetry(backgroundResult) {
                    log("Recovered background transfer for \(track.name) finished on an intermediate response. Requeueing track.")
                    clearActiveBackgroundTrack(track.id)
                    trackStates[track.id] = .queued
                    pendingQueue.insert(track, at: 0)
                    syncQueuePersistence()
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                    return
                }

                try await finalizeDownloadedTrack(
                    fileURL: backgroundResult.fileURL,
                    track: track,
                    backendLabel: backgroundResult.context.backendLabel
                )
                completedQueueCount += 1
                clearActiveBackgroundTrack(track.id)
                if trackStates[track.id] == .done {
                    await showDownloadCompletion(for: track, completedCount: completedQueueCount)
                } else {
                    endLiveActivityIfQueueFinished(finalPhase: .failed)
                }
                log("Recovered background download finished via \(backgroundResult.context.backendLabel): \(backgroundResult.fileURL.lastPathComponent)")
                syncQueuePersistence()
                if !pendingQueue.isEmpty {
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                }
            } catch {
                let message = downloadFailureMessage(for: track, error: error)
                log("Recovered background download failed validation (\(error.localizedDescription)): \(message)")
                errorText = message
                trackFailureReasons[track.id] = message
                trackStates[track.id] = .failed
                completedQueueCount += 1
                clearActiveBackgroundTrack(track.id)
                endLiveActivityIfQueueFinished(finalPhase: .failed)
                syncQueuePersistence()
                if !pendingQueue.isEmpty {
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                }
            }
        case .failure(let error):
            let message = downloadFailureMessage(for: track, error: error)
            log("Recovered background download failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
            completedQueueCount += 1
            clearActiveBackgroundTrack(track.id)
            endLiveActivityIfQueueFinished(finalPhase: .failed)
            syncQueuePersistence()
            if !pendingQueue.isEmpty {
                if backgroundDownloadsEnabled {
                    continueBackgroundQueueIfAllowed()
                } else {
                    Task { await processQueueIfNeeded() }
                }
            }
        }
    }

    private func recoveredBackgroundResultNeedsRetry(_ result: BackgroundDownloadResult) -> Bool {
        let mimeType = (result.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if mimeType.contains("application/json") || mimeType.contains("text/json") {
            return true
        }
        return !downloadedFileLooksLikeAudio(result.fileURL)
    }

    private func downloadWithFallbacks(track: DownloadTrack) async throws -> BackendDownloadOutcome {
        let resolvedSource = await resolvedPrimaryDownloadSource(for: track)
        log("Using source URL (\(resolvedSource.platform.displayName)): \(resolvedSource.url)")

        let candidates = try await primaryCandidates(for: resolvedSource, track: track)
        if !candidates.isEmpty {
            do {
                if let outcome = try await executeCandidatesUntilSuccess(
                    candidates,
                    trackID: track.id,
                    suggestedName: "\(track.artistLine) - \(track.name)",
                    fallbackExtension: "flac"
                ) {
                    return outcome
                }
            } catch {
                if Task.isCancelled {
                    throw error
                }
                log("Primary backend candidates failed for \(track.name): \(error.localizedDescription)")
            }
        }

        if resolvedSource.platform != .deezer {
            log("Attempting last-resort Deezer mapping for \(track.name)...")
            let deezerURL = await mapTrackToDeezerURL(track)
            if deezerURL == nil && resolvedSource.platform == .appleMusic {
                throw DownloadError.trackNotFound
            }
            if let deezerURL {
                let deezerSource = DownloadSourceChoice(
                    platform: .deezer,
                    url: deezerURL,
                    backendGenreSource: DownloadPlatform.deezer.backendGenreSource
                )
                let deezerCandidates = try await primaryCandidates(for: deezerSource, track: track)
                if !deezerCandidates.isEmpty {
                    if let outcome = try await executeCandidatesUntilSuccess(
                        deezerCandidates,
                        trackID: track.id,
                        suggestedName: "\(track.artistLine) - \(track.name)",
                        fallbackExtension: "flac"
                    ) {
                        return outcome
                    }
                }
            }
        }

        throw DownloadError.mappingFailed("All configured download backends failed.")
    }

    private func preferredDownloadSource(for sourceURL: String) -> DownloadSourceChoice {
        let platform: DownloadPlatform
        if sourceURL.contains("music.apple.com") || sourceURL.contains("itunes.apple.com") {
            platform = .appleMusic
        } else if sourceURL.contains("spotify.com") {
            platform = .spotify
        } else if sourceURL.contains("deezer.com") {
            platform = .deezer
        } else if sourceURL.contains("qobuz.com") {
            platform = .qobuz
        } else if sourceURL.contains("tidal.com") {
            platform = .tidal
        } else if sourceURL.contains("music.amazon.") || sourceURL.contains("amazon.com/music") || sourceURL.contains("amazon.com/gp/product/") {
            platform = .amazon
        } else if sourceURL.contains("pandora.com") {
            platform = .pandora
        } else if sourceURL.contains("soundcloud.com") {
            platform = .soundcloud
        } else if sourceURL.contains("music.youtube.com") || sourceURL.contains("youtube.com") || sourceURL.contains("youtu.be") {
            platform = .youtubeMusic
        } else {
            platform = .unknown
        }
        return DownloadSourceChoice(platform: platform, url: sourceURL, backendGenreSource: platform.backendGenreSource)
    }

    private func resolvedPrimaryDownloadSource(for track: DownloadTrack) async -> DownloadSourceChoice {
        var source = preferredDownloadSource(for: track.sourceURL)
        if source.platform == .appleMusic, let deezerURL = await mapTrackToDeezerURL(track) {
            source = DownloadSourceChoice(
                platform: .deezer,
                url: deezerURL,
                backendGenreSource: DownloadPlatform.deezer.backendGenreSource
            )
        }
        return source
    }

    private func primaryCandidates(
        for source: DownloadSourceChoice,
        track: DownloadTrack? = nil
    ) async throws -> [BackendCandidate] {
        guard source.platform == .appleMusic || source.platform == .spotify || source.platform == .deezer || source.platform == .unknown else {
            return []
        }
        return try await downloadBackendCandidates(for: source, track: track)
    }

    private func downloadBackendCandidates(
        for source: DownloadSourceChoice,
        track: DownloadTrack? = nil
    ) async throws -> [BackendCandidate] {
        let urlString = "\(Config.byeTunesApiUrl)/api/download"
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL(urlString)
        }

        let desiredFormat = desiredDownloadFormat()
        let wantsSyncedLyrics =
            UserDefaults.standard.bool(forKey: "fetchLyrics") ||
            UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")

        func makeCandidate(label: String, format: String, overrideURL: String? = nil) throws -> BackendCandidate {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "url": overrideURL ?? source.url,
                "format": format,
                "genreSource": source.backendGenreSource,
                "syncedLyrics": wantsSyncedLyrics
            ])
            return BackendCandidate(label: label, request: request, customDownload: nil, requestedFormat: format)
        }

        var candidates = [try makeCandidate(label: Config.downloadBackendLabel, format: desiredFormat)]
        if desiredFormat.lowercased() != "mp3" {
            candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (MP3 Fallback)", format: "mp3"))
        }

        if source.platform == .appleMusic, let track, let deezerURL = await mapTrackToDeezerURL(track) {
            candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (Deezer)", format: desiredFormat, overrideURL: deezerURL))
            if desiredFormat.lowercased() != "mp3" {
                candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (Deezer MP3 Fallback)", format: "mp3", overrideURL: deezerURL))
            }
        }

        return candidates
    }

    private func desiredDownloadFormat() -> String {
        return UserDefaults.standard.string(forKey: "yoinkifyFormat") ?? "flac"
    }

    private func executeCandidatesUntilSuccess(
        _ candidates: [BackendCandidate],
        trackID: String,
        suggestedName: String,
        fallbackExtension: String
    ) async throws -> BackendDownloadOutcome? {
        guard !candidates.isEmpty else {
            throw DownloadError.mappingFailed("No usable backend request was created.")
        }

        var lastError: Error = DownloadError.mappingFailed("All backend requests failed.")

        for candidate in candidates {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            do {
                let candidateFallbackExtension = DownloadSupport.fallbackExtension(
                    forRequestedFormat: candidate.requestedFormat,
                    defaultingTo: fallbackExtension
                )
                let fileURL: URL
                if let customDownload = candidate.customDownload {
                    fileURL = try await customDownload(trackID, suggestedName, candidateFallbackExtension)
                } else if let request = candidate.request {
                    fileURL = try await executeDownloadRequest(
                        request,
                        trackID: trackID,
                        backendLabel: candidate.label,
                        suggestedName: suggestedName,
                        fallbackExtension: candidateFallbackExtension,
                        requestedFormat: candidate.requestedFormat
                    )
                } else {
                    throw DownloadError.mappingFailed("No usable backend request was created for \(candidate.label).")
                }
                log("\(candidate.label) backend succeeded.")
                BackendHealthStore.shared.recordSuccess(label: candidate.label)
                return BackendDownloadOutcome(fileURL: fileURL, backendLabel: candidate.label)
            } catch {
                if Task.isCancelled {
                    throw error
                }
                lastError = error
                log("\(candidate.label) backend failed: \(error.localizedDescription)")
                BackendHealthStore.shared.recordFailure(label: candidate.label, error: error.localizedDescription)
            }
        }

        throw lastError
    }

    private func executeDownloadRequest(
        _ request: URLRequest,
        trackID: String,
        backendLabel: String,
        suggestedName: String,
        fallbackExtension: String,
        requestedFormat: String? = nil,
        depth: Int = 0
    ) async throws -> URL {
        if depth > 4 {
            throw DownloadError.mappingFailed("Too many redirect/manifest hops.")
        }

        var request = request
        applyZarzHeaders(to: &request)
        log("Requesting \(redactedDownloadURLString(request.url))")

        let shouldUseBackgroundTransfer = backgroundDownloadsEnabled && !isAppActive
        log("executeDownloadRequest track=\(trackID) backend=\(backendLabel) depth=\(depth) method=\(request.httpMethod ?? "GET") background=\(shouldUseBackgroundTransfer)")
        let data: Data
        let response: URLResponse
        let backgroundFileURL: URL?
        if shouldUseBackgroundTransfer {
            let backgroundResult = try await BackgroundAudioDownloadManager.shared.download(
                request: request,
                context: BackgroundDownloadRequestContext(
                    trackID: trackID,
                    backendLabel: backendLabel,
                    suggestedName: suggestedName,
                    fallbackExtension: fallbackExtension
                ),
                progress: { [weak self] progress, speedBps in
                    self?.updateVisibleDownloadProgress(progress, speedBps: speedBps, trackID: trackID)
                }
            )
            backgroundFileURL = backgroundResult.fileURL
            data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: backgroundResult.fileURL, options: .mappedIfSafe)
            }.value
            response = backgroundResult.response
        } else {
            let fetched = try await fetchDataWithProgress(for: request) { [weak self] progress, speedBps in
                self?.updateVisibleDownloadProgress(progress, speedBps: speedBps, trackID: trackID)
            }
            backgroundFileURL = nil
            data = fetched.0
            response = fetched.1
        }
        try validateHTTP(response: response, data: data)

        if let manifestURL = extractManifestURL(from: data) {
            log("Resolved manifest media URL: \(redactedDownloadURLString(manifestURL))")
            let redirectedRequest = URLRequest(url: manifestURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                trackID: trackID,
                backendLabel: backendLabel,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
                requestedFormat: requestedFormat,
                depth: depth + 1
            )
        }

        if let redirectedURL = extractRedirectURL(from: data) {
            log("Received JSON redirect: \(redactedDownloadURLString(redirectedURL))")
            let redirectedRequest = URLRequest(url: redirectedURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                trackID: trackID,
                backendLabel: backendLabel,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
                requestedFormat: requestedFormat,
                depth: depth + 1
            )
        }

        let httpResponse = response as? HTTPURLResponse
        let mimeType = httpResponse?.value(forHTTPHeaderField: "Content-Type")

        guard !data.isEmpty else {
            throw DownloadError.emptyResponse
        }

        if let mimeType, mimeType.contains("application/json"), extractRedirectURL(from: data) == nil {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 json>"
            throw DownloadError.remoteFailure(bodyText)
        }

        recordQualityNoteIfNeeded(trackID: trackID, requestedFormat: requestedFormat, httpResponse: httpResponse)

        if let backgroundFileURL {
            return backgroundFileURL
        }

        let fileExtension = DownloadSupport.fileExtension(for: mimeType, fallback: fallbackExtension)
        return try saveDownloadedData(data, suggestedName: suggestedName, fileExtension: fileExtension)
    }

    private func recordQualityNoteIfNeeded(trackID: String, requestedFormat: String?, httpResponse: HTTPURLResponse?) {
        guard let requestedFormat else { return }
        guard let deliveredFormat = httpResponse?.value(forHTTPHeaderField: "X-Audio-Format") else { return }

        guard deliveredFormat.caseInsensitiveCompare(requestedFormat) != .orderedSame else {
            trackQualityNotes.removeValue(forKey: trackID)
            return
        }

        let source = httpResponse?.value(forHTTPHeaderField: "X-Audio-Source")
        let quality = httpResponse?.value(forHTTPHeaderField: "X-Audio-Quality")
        var note = "Requested \(requestedFormat.uppercased()), got \(deliveredFormat.uppercased())"
        if let quality, deliveredFormat.caseInsensitiveCompare("mp3") == .orderedSame {
            note += " \(quality)kbps"
        }
        note += ". Lossless wasn't available for this track"
        if let source {
            note += " (source: \(source.capitalized))"
        }
        trackQualityNotes[trackID] = note
        log("Quality note for \(trackID): \(note)")
    }

    private func redactedDownloadURLString(_ url: URL?) -> String {
        guard let url else { return "<unknown>" }
        if url.host?.caseInsensitiveCompare(Config.byeTunesApiHost) == .orderedSame {
            return Config.downloadBackendLabel
        }
        return url.absoluteString
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw DownloadError.httpError(http.statusCode, body)
        }
    }

    private func extractManifestURL(from data: Data) -> URL? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let manifest = findFirstString(in: obj, matching: ["manifest"]),
           let resolved = decodeManifestMediaURL(manifest) {
            return resolved
        }

        if let direct = findFirstURLString(
            in: obj,
            matching: ["manifest_url", "manifestUrl", "stream_url", "streamUrl", "media_url", "mediaUrl"]
        ), let url = URL(string: direct) {
            return url
        }

        return nil
    }

    private func decodeManifestMediaURL(_ manifest: String) -> URL? {
        let candidates = [manifest, manifest.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")]
        for candidate in candidates {
            let padded = padBase64(candidate)
            guard let data = Data(base64Encoded: padded) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let urls = obj["urls"] as? [String], let first = urls.first, let url = URL(string: first) {
                return url
            }
            let keys = ["url", "manifest_url", "media_url"]
            for key in keys {
                if let value = obj[key] as? String, let url = URL(string: value) {
                    return url
                }
            }
        }
        return nil
    }

    private func extractProviderDownloadURL(from object: [String: Any]) -> URL? {
        if let manifest = findFirstString(in: object, matching: ["manifest"]),
           let decoded = decodeManifestMediaURL(manifest) {
            return decoded
        }

        if let direct = findFirstURLString(
            in: object,
            matching: [
                "stream_url",
                "streamUrl",
                "direct_download_url",
                "directDownloadUrl",
                "download_url",
                "downloadUrl",
                "media_url",
                "mediaUrl",
                "url",
                "link"
            ]
        ), let url = URL(string: direct) {
            return url
        }

        return nil
    }

    private func findFirstURLString(in object: Any, matching preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = findFirstString(in: object, matching: [key]), URL(string: value) != nil {
                return value
            }
        }

        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let match = findFirstURLString(in: value, matching: preferredKeys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstURLString(in: value, matching: preferredKeys) {
                    return match
                }
            }
        } else if let string = object as? String, URL(string: string) != nil {
            return string
        }

        return nil
    }

    private func findFirstString(in object: Any, matching keys: [String]) -> String? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })

        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if normalizedKeys.contains(key.lowercased()), let stringValue = value as? String, !stringValue.isEmpty {
                    return stringValue
                }
            }

            for value in dictionary.values {
                if let match = findFirstString(in: value, matching: keys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstString(in: value, matching: keys) {
                    return match
                }
            }
        }

        return nil
    }

    private func findFirstBool(in object: Any, matching keys: [String]) -> Bool? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })

        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                guard normalizedKeys.contains(key.lowercased()) else { continue }
                if let boolValue = value as? Bool {
                    return boolValue
                }
                if let stringValue = value as? String {
                    switch stringValue.lowercased() {
                    case "true", "1", "yes":
                        return true
                    case "false", "0", "no":
                        return false
                    default:
                        break
                    }
                }
                if let intValue = value as? Int {
                    return intValue != 0
                }
            }

            for value in dictionary.values {
                if let match = findFirstBool(in: value, matching: keys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstBool(in: value, matching: keys) {
                    return match
                }
            }
        }

        return nil
    }

    private func padBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private func extractRedirectURL(from data: Data) -> URL? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let value = findFirstURLString(
            in: obj,
            matching: [
                "url",
                "download_url",
                "downloadUrl",
                "redirect_url",
                "redirectUrl",
                "direct_download_url",
                "directDownloadUrl",
                "stream_url",
                "streamUrl",
                "media_url",
                "mediaUrl",
                "link"
            ]
        ), let url = URL(string: value) {
            return url
        }
        return nil
    }

    private func saveDownloadedData(_ data: Data, suggestedName: String, fileExtension: String) throws -> URL {
        let base = DownloadSupport.tidyFilename(suggestedName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadCache", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var url = directory.appendingPathComponent("\(base).\(fileExtension)")
            var suffix = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = directory.appendingPathComponent("\(base)-\(suffix).\(fileExtension)")
                suffix += 1
            }

            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw DownloadError.fileSaveFailed(error.localizedDescription)
        }
    }

    private func persistDownloadedSongIfNeeded(_ song: SongMetadata) -> SongMetadata {
        guard UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else {
            return song
        }

        let directory = SongMetadata.persistentDownloadsDirectory()
        let needsSecurityScope = directory.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log("Failed to create persistent download folder: \(error.localizedDescription)")
            return song
        }

        let ext = song.localURL.pathExtension.isEmpty ? "flac" : song.localURL.pathExtension
        let baseName = DownloadSupport.tidyFilename("\(song.artist) - \(song.title)")
        var destination = directory.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) && destination.path != song.localURL.path {
            destination = directory.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
            suffix += 1
        }

        if destination.path == song.localURL.path {
            return song
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: song.localURL, to: destination)
            var updatedSong = song
            updatedSong.localURL = destination
            return updatedSong
        } catch {
            log("Failed to persist downloaded song \(song.title): \(error.localizedDescription)")
            return song
        }
    }

    private func matchKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func mapTrackToDeezerURL(_ track: DownloadTrack) async -> String? {
        let titleKey = matchKey(track.name)
        let artistKeys = track.artistLine
            .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
            .map { matchKey($0) }
            .filter { !$0.isEmpty }
        guard !titleKey.isEmpty else { return nil }

        let queries = ["\(track.name) \(track.artistLine)", track.name]
        for query in queries {
            let results = await SongMetadata.searchDeezer(query: query, limit: 25)
            let match = results.first { result in
                let resultTitle = matchKey(result.title)
                let resultArtist = matchKey(result.artist.name)
                let titleMatches = resultTitle == titleKey || resultTitle.hasPrefix(titleKey) || titleKey.hasPrefix(resultTitle)
                let artistMatches = artistKeys.isEmpty || artistKeys.contains { $0 == resultArtist || $0.contains(resultArtist) || resultArtist.contains($0) }
                return titleMatches && artistMatches
            }
            if let match {
                let url = match.link ?? "https://www.deezer.com/track/\(match.id)"
                log("Deezer match for \(track.name) - \(track.artistLine): \(url)")
                return url
            }
        }
        log("No Deezer match found for \(track.name) - \(track.artistLine)")
        return nil
    }

    private func fetchDataWithProgress(
        for request: URLRequest,
        onProgress: @escaping (Double, Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let downloader = ProgressiveDataFetcher()
        return try await downloader.fetch(request: request) { progress, speedBps in
            Task { @MainActor in
                onProgress(progress, speedBps)
            }
        }
    }

    private func applyZarzHeaders(to request: inout URLRequest) {
        guard request.url?.host?.contains("zarz.moe") == true else { return }
        request.setValue("SpotiFLAC-Mobile/4.5.5", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
    }

    private func searchAlbums(query: String, limit: Int, offset: Int = 0) async -> [AppleMusicAlbumResult] {
        let fallback = await AppleMusicAPI.shared.searchAlbumsPublic(query: query, limit: limit, offset: offset)
        if !fallback.isEmpty {
            log("Album search is using Apple Music public search page.")
        }
        return fallback.map {
            AppleMusicAlbumResult(
                id: $0.id,
                attributes: AppleMusicAlbumResultAttributes(
                    name: $0.name,
                    artistName: $0.artistName,
                    artwork: $0.artwork
                )
            )
        }
    }

    private func searchPlaylists(query: String, limit: Int, offset: Int = 0) async -> [AppleMusicPlaylistResult] {
        let fallback = await AppleMusicAPI.shared.searchPlaylistsPublic(query: query, limit: limit, offset: offset)
        if !fallback.isEmpty {
            log("Playlist search is using Apple Music public search page.")
        }
        return fallback.map {
            AppleMusicPlaylistResult(
                id: $0.id,
                attributes: AppleMusicPlaylistAttributes(
                    name: $0.name,
                    curatorName: $0.curatorName,
                    artwork: $0.artwork
                ),
                relationships: nil
            )
        }
    }


    private func metadataTrack(from song: iTunesSong) -> DownloadTrack? {
        guard
            let trackID = song.trackId,
            let title = song.trackName,
            let artist = song.artistName
        else { return nil }

        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let albumID = song.collectionId.map { "itunes-album-\($0)" } ?? "itunes-album-\(DownloadSupport.normalizedSearchValue(artist))-\(DownloadSupport.normalizedSearchValue(song.collectionName ?? "Unknown Album"))"
        let artworkURL = song.artworkUrl100?
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")

        return DownloadTrack(
            id: "itunes-\(trackID)",
            name: title,
            artistLine: artist,
            albumName: song.collectionName ?? "Unknown Album",
            artworkURL: artworkURL.flatMap(URL.init(string:)),
            isExplicit: false,
            sourceURL: song.trackViewUrl ?? "https://music.apple.com/\(region)/song/\(trackID)",
            sourceContext: .song,
            provider: .metadata,
            artistIdentifier: song.artistId.map { "itunes-artist-\($0)" },
            albumIdentifier: albumID,
            previewURL: song.previewUrl.flatMap(URL.init(string:))
        )
    }

    private func metadataTrack(from song: DeezerSong, sourceURLOverride: String? = nil) -> DownloadTrack {
        return DownloadTrack(
            id: "deezer-\(song.id)",
            name: song.title,
            artistLine: song.artist.name,
            albumName: song.album.title,
            artworkURL: URL(string: song.album.cover_xl),
            isExplicit: song.explicit_lyrics ?? false,
            sourceURL: sourceURLOverride ?? song.link ?? "https://www.deezer.com/track/\(song.id)",
            sourceContext: .song,
            provider: .metadata,
            artistIdentifier: "deezer-artist-\(song.artist.id)",
            albumIdentifier: "deezer-album-\(song.album.id)",
            previewURL: song.preview.flatMap(URL.init(string:))
        )
    }

    private func buildMetadataAlbums(from tracks: [DownloadTrack]) -> [DownloadAlbum] {
        var grouped: [String: [DownloadTrack]] = [:]
        var orderedKeys: [String] = []

        for track in tracks {
            let key = track.albumIdentifier ?? "metadata-album-\(DownloadSupport.normalizedSearchValue(track.artistLine))-\(DownloadSupport.normalizedSearchValue(track.albumName))"
            if grouped[key] == nil {
                grouped[key] = []
                orderedKeys.append(key)
            }
            grouped[key]?.append(track)
        }

        metadataAlbumTrackCache = grouped

        return orderedKeys.compactMap { key in
            guard let groupTracks = grouped[key], let firstTrack = groupTracks.first else { return nil }
            return DownloadAlbum(
                id: key,
                name: firstTrack.albumName,
                artistLine: mostCommonArtistLine(in: groupTracks),
                artworkURL: firstTrack.artworkURL,
                sourceURL: firstTrack.sourceURL,
                provider: .metadata,
                artistIdentifier: firstTrack.artistIdentifier,
                albumIdentifier: key
            )
        }
    }

    private func mostCommonArtistLine(in tracks: [DownloadTrack]) -> String {
        var counts: [String: Int] = [:]
        for track in tracks {
            counts[track.artistLine, default: 0] += 1
        }
        let mostCommon = counts.max { lhs, rhs in lhs.value < rhs.value }?.key
        return (mostCommon?.isEmpty == false) ? mostCommon! : (tracks.first?.artistLine ?? "")
    }

    private func fetchAlbumTracks(albumID: String, fallbackAlbumName: String, sourceURL: String? = nil) async -> [DownloadTrack] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

        let publicTracks = await AppleMusicAPI.shared.fetchAlbumTracksPublic(id: albumID, urlHint: sourceURL)
        return publicTracks.map { item in
            let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
            return DownloadTrack(
                id: item.id,
                name: item.attributes.name,
                artistLine: item.attributes.artistName,
                albumName: item.attributes.albumName ?? fallbackAlbumName,
                artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                isExplicit: item.attributes.contentRating == "explicit",
                sourceURL: songURL,
                sourceContext: .album,
                provider: .appleMusic,
                artistIdentifier: item.relationships?.artists?.data.first?.id,
                albumIdentifier: item.relationships?.albums?.data.first?.id ?? albumID,
                previewURL: nil
            )
        }
    }


    private func fetchSpotifyToken() async -> String? {
        guard let url = URL(string: "https://open.spotify.com/get_access_token?reason=transport&productType=web_player") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["accessToken"] as? String {
                return token
            }
        } catch {
            log("Failed to fetch Spotify token: \(error.localizedDescription)")
        }
        return nil
    }

    private func fetchSpotifyMetadata(url: String) async -> [String: Any]? {
        guard let endpoint = URL(string: "\(Config.byeTunesApiUrl)/api/metadata") else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return json
        } catch {
            log("Spotify metadata fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func spotifyTrackID(fromSpotifyURL spotifyURL: String) -> String? {
        firstRegexCapture(in: spotifyURL, pattern: #"track/([a-zA-Z0-9]+)"#, group: 1)
    }

    private func downloadTrack(fromMetadataItem item: [String: Any], fallbackArtistLine: String, fallbackAlbumName: String, fallbackArtworkURL: URL?, sourceContext: DownloadTrack.SourceContext, albumIdentifier: String?) -> DownloadTrack? {
        guard let trackURLString = item["spotifyUrl"] as? String,
              let trackID = spotifyTrackID(fromSpotifyURL: trackURLString) else { return nil }
        let trackArtworkURL = (item["albumArt"] as? String).flatMap(URL.init(string:)) ?? fallbackArtworkURL
        return DownloadTrack(
            id: trackID,
            name: item["name"] as? String ?? "Unknown Title",
            artistLine: (item["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackArtistLine,
            albumName: item["album"] as? String ?? fallbackAlbumName,
            artworkURL: trackArtworkURL,
            isExplicit: item["explicit"] as? Bool ?? false,
            sourceURL: "https://open.spotify.com/track/\(trackID)",
            sourceContext: sourceContext,
            provider: .metadata,
            artistIdentifier: nil,
            albumIdentifier: albumIdentifier,
            previewURL: nil
        )
    }

    private func fetchSpotifyTrack(id: String, sourceURL: String) async -> DownloadTrack? {
        if let json = await fetchSpotifyMetadata(url: sourceURL), json["type"] as? String == "track" {
            let artistLine = json["artist"] as? String ?? "Unknown Artist"
            let albumName = json["album"] as? String ?? "Unknown Album"
            let artworkURL = (json["albumArt"] as? String).flatMap(URL.init(string:))
            return DownloadTrack(
                id: id,
                name: json["name"] as? String ?? "Unknown Title",
                artistLine: artistLine,
                albumName: albumName,
                artworkURL: artworkURL,
                isExplicit: json["explicit"] as? Bool ?? false,
                sourceURL: sourceURL,
                sourceContext: .song,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: nil,
                previewURL: nil
            )
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/tracks/\(id)") else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    let name = json["name"] as? String ?? "Unknown Title"
                    let artists = json["artists"] as? [[String: Any]] ?? []
                    let artistLine = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    let album = json["album"] as? [String: Any]
                    let albumName = album?["name"] as? String ?? "Unknown Album"
                    let artworkURLString = (album?["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    let explicit = json["explicit"] as? Bool ?? false
                    let previewURLString = json["preview_url"] as? String
                    let previewURL = previewURLString.flatMap(URL.init(string:))
                    
                    return DownloadTrack(
                        id: id,
                        name: name,
                        artistLine: artistLine.isEmpty ? "Unknown Artist" : artistLine,
                        albumName: albumName,
                        artworkURL: artworkURL,
                        isExplicit: explicit,
                        sourceURL: sourceURL,
                        sourceContext: .song,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: album?["id"] as? String,
                        previewURL: previewURL
                    )
                }
            } catch {
                log("Spotify API track fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyTrackFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    private func extractSpotifyJSONLD(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let jsonString = firstRegexCapture(in: html, pattern: pattern, group: 1) else {
            return nil
        }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func fetchSpotifyTrackFromPublicPage(sourceURL: String, fallbackID: String) async -> DownloadTrack? {
        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var title = "Unknown Title"
            var artist = "Unknown Artist"
            var albumName = "Unknown Album"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    title = name
                }
                if let artists = jsonld["byArtist"] as? [[String: Any]] {
                    artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                } else if let artistObj = jsonld["byArtist"] as? [String: Any] {
                    artist = artistObj["name"] as? String ?? "Unknown Artist"
                }
                if let albumObj = jsonld["inAlbum"] as? [String: Any],
                   let aName = albumObj["name"] as? String {
                    albumName = aName
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if title == "Unknown Title" || artist == "Unknown Artist" || albumName == "Unknown Album" {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if title == "Unknown Title", let ogTitleClean = ogTitle {
                    if let range = ogTitleClean.range(of: " - song", options: .caseInsensitive) {
                        title = String(ogTitleClean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let range = ogTitleClean.range(of: " - album", options: .caseInsensitive) {
                        title = String(ogTitleClean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if ogTitleClean.contains("| Spotify") {
                        title = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        title = ogTitleClean
                    }
                }
                
                if let desc = ogDescription {
                    let parts = desc.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if artist == "Unknown Artist", parts.count >= 1 {
                        var rawArtist = parts[0]
                        if rawArtist.hasPrefix("Listen to ") {
                            rawArtist = rawArtist.replacingOccurrences(of: #"Listen to .*? on Spotify\.\s*"#, with: "", options: .regularExpression)
                        }
                        if !rawArtist.isEmpty {
                            artist = rawArtist
                        }
                    }
                    if albumName == "Unknown Album", parts.count >= 3 {
                        let p1Lower = parts[1].lowercased()
                        if p1Lower != "song" && p1Lower != "single" {
                            let hasSongIndicator = parts.contains { $0.lowercased() == "song" || $0.lowercased() == "single" }
                            if hasSongIndicator {
                                albumName = parts[1]
                            }
                        }
                    }
                }
                
                if artist == "Unknown Artist", let ogTitleClean = ogTitle {
                    if let byRange = ogTitleClean.range(of: "by ", options: .backwards) {
                        let afterBy = ogTitleClean[byRange.upperBound...]
                        let cleanArtist = afterBy.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanArtist.isEmpty {
                            artist = cleanArtist
                        }
                    }
                }
                
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            return DownloadTrack(
                id: fallbackID,
                name: title,
                artistLine: artist,
                albumName: albumName,
                artworkURL: artworkURL,
                isExplicit: false,
                sourceURL: sourceURL,
                sourceContext: .song,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: nil,
                previewURL: nil
            )
        } catch {
            log("Spotify public page track fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSpotifyAlbum(id: String, sourceURL: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let json = await fetchSpotifyMetadata(url: sourceURL) {
            let albumName = json["name"] as? String ?? "Unknown Album"
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            let rawTracks = json["tracks"] as? [[String: Any]] ?? []
            let artistLine = rawTracks.first.flatMap { $0["albumArtist"] as? String ?? $0["artist"] as? String } ?? "Unknown Artist"

            let albumResult = DownloadAlbum(
                id: id,
                name: albumName,
                artistLine: artistLine,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: id
            )

            let tracks = rawTracks.compactMap {
                downloadTrack(fromMetadataItem: $0, fallbackArtistLine: artistLine, fallbackAlbumName: albumName, fallbackArtworkURL: artworkURL, sourceContext: .album, albumIdentifier: id)
            }

            if !tracks.isEmpty {
                return (albumResult, tracks)
            }
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/albums/\(id)") else { return nil }
            var albumRequest = URLRequest(url: url)
            albumRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (albumData, response) = try await session.data(for: albumRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: albumData) as? [String: Any] {
                    
                    let albumName = json["name"] as? String ?? "Unknown Album"
                    let artists = json["artists"] as? [[String: Any]] ?? []
                    let artistLine = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    let albumResult = DownloadAlbum(
                        id: id,
                        name: albumName,
                        artistLine: artistLine.isEmpty ? "Unknown Artist" : artistLine,
                        artworkURL: artworkURL,
                        sourceURL: sourceURL,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: id
                    )
                    
                    var tracks: [DownloadTrack] = []

                    if let tracksContainer = json["tracks"] as? [String: Any],
                       let items = tracksContainer["items"] as? [[String: Any]] {
                        for item in items {
                            if let trackID = item["id"] as? String {
                                let trackName = item["name"] as? String ?? "Unknown Title"
                                let trackArtists = item["artists"] as? [[String: Any]] ?? []
                                let trackArtistLine = trackArtists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                                let explicit = item["explicit"] as? Bool ?? false
                                let trackURL = "https://open.spotify.com/track/\(trackID)"

                                tracks.append(DownloadTrack(
                                    id: trackID,
                                    name: trackName,
                                    artistLine: trackArtistLine.isEmpty ? artistLine : trackArtistLine,
                                    albumName: albumName,
                                    artworkURL: artworkURL,
                                    isExplicit: explicit,
                                    sourceURL: trackURL,
                                    sourceContext: .album,
                                    provider: .metadata,
                                    artistIdentifier: nil,
                                    albumIdentifier: id,
                                    previewURL: (item["preview_url"] as? String).flatMap(URL.init(string:))
                                ))
                            }
                        }
                    }

                    return (albumResult, tracks)
                }
            } catch {
                log("Spotify API album fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyAlbumFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    private func fetchSpotifyAlbumFromPublicPage(sourceURL: String, fallbackID: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let embedURL = URL(string: "https://open.spotify.com/embed/album/\(fallbackID)") {
            do {
                let (data, _) = try await session.data(from: embedURL)
                if let html = String(data: data, encoding: .utf8), !html.isEmpty,
                   let parsed = parseSpotifyEmbedHTML(in: html, fallbackID: fallbackID, sourceURL: sourceURL, sourceContext: .album) {
                    return parsed
                }
            } catch {
                log("Spotify public page album embed fetch failed: \(error.localizedDescription)")
            }
        }

        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var albumName = "Unknown Album"
            var artistName = "Unknown Artist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    albumName = name
                }
                if let artists = jsonld["byArtist"] as? [[String: Any]] {
                    artistName = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                } else if let artistObj = jsonld["byArtist"] as? [String: Any] {
                    artistName = artistObj["name"] as? String ?? "Unknown Artist"
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if albumName == "Unknown Album" || artistName == "Unknown Artist" || artworkURL == nil {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if let ogTitleClean = ogTitle {
                    albumName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let range = albumName.range(of: " - album", options: .caseInsensitive) {
                        albumName = String(albumName[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                if let desc = ogDescription {
                    let parts = desc.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count >= 1 {
                        var rawArtist = parts[0]
                        if rawArtist.hasPrefix("Listen to ") {
                            rawArtist = rawArtist.replacingOccurrences(of: #"Listen to .*? on Spotify\.\s*"#, with: "", options: .regularExpression)
                        }
                        if !rawArtist.isEmpty {
                            artistName = rawArtist
                        }
                    }
                }
                
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            let albumResult = DownloadAlbum(
                id: fallbackID,
                name: albumName,
                artistLine: artistName,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: fallbackID
            )
            
            let tracks = extractSpotifyTracksFromHTML(in: html, fallbackArtist: artistName, fallbackAlbumName: albumName, artworkURL: artworkURL, sourceContext: .album)
            let finalTracks = tracks.isEmpty ? [
                DownloadTrack(
                    id: fallbackID,
                    name: albumName,
                    artistLine: artistName,
                    albumName: albumName,
                    artworkURL: artworkURL,
                    isExplicit: false,
                    sourceURL: sourceURL,
                    sourceContext: .album,
                    provider: .metadata,
                    artistIdentifier: nil,
                    albumIdentifier: fallbackID,
                    previewURL: nil
                )
            ] : tracks
            return (albumResult, finalTracks)
        } catch {
            log("Spotify public page album failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSpotifyPlaylistFromPublicPage(sourceURL: String, fallbackID: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let embedURL = URL(string: "https://open.spotify.com/embed/playlist/\(fallbackID)") {
            do {
                let (data, _) = try await session.data(from: embedURL)
                if let html = String(data: data, encoding: .utf8), !html.isEmpty,
                   let parsed = parseSpotifyEmbedHTML(in: html, fallbackID: fallbackID, sourceURL: sourceURL, sourceContext: .song) {
                    var enrichedAlbum = parsed.album
                    let creator = parsed.album.artistLine
                    let trackCount = parsed.tracks.count
                    let desc = "Playlist • \(creator) • \(trackCount) items"
                    enrichedAlbum = DownloadAlbum(
                        id: enrichedAlbum.id,
                        name: enrichedAlbum.name,
                        artistLine: desc,
                        artworkURL: enrichedAlbum.artworkURL,
                        sourceURL: enrichedAlbum.sourceURL,
                        provider: enrichedAlbum.provider,
                        artistIdentifier: enrichedAlbum.artistIdentifier,
                        albumIdentifier: enrichedAlbum.albumIdentifier
                    )
                    return (enrichedAlbum, parsed.tracks)
                }
            } catch {
                log("Spotify public page playlist embed fetch failed: \(error.localizedDescription)")
            }
        }

        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var playlistName = "Unknown Playlist"
            var description = "Spotify Playlist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    playlistName = name
                }
                if let desc = jsonld["description"] as? String {
                    description = desc
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if playlistName == "Unknown Playlist" || artworkURL == nil {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if playlistName == "Unknown Playlist", let ogTitleClean = ogTitle {
                    playlistName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if description == "Spotify Playlist", let desc = ogDescription {
                    description = desc
                }
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            let playlistResult = DownloadAlbum(
                id: fallbackID,
                name: playlistName,
                artistLine: description,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: fallbackID
            )
            
            let tracks = extractSpotifyTracksFromHTML(in: html, fallbackArtist: "Unknown Artist", fallbackAlbumName: playlistName, artworkURL: artworkURL, sourceContext: .song)
            return (playlistResult, tracks)
        } catch {
            log("Spotify public page playlist fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSpotifyArtistFromPublicPage(sourceURL: String, fallbackID: String) async -> DownloadArtist? {
        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var artistName = "Unknown Artist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    artistName = name
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if artistName == "Unknown Artist" {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if let ogTitleClean = ogTitle {
                    artistName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            return DownloadArtist(
                id: fallbackID,
                name: artistName,
                provider: .metadata,
                artworkURL: artworkURL
            )
        } catch {
            log("Spotify public page artist fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSpotifyPlaylist(id: String, sourceURL: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let json = await fetchSpotifyMetadata(url: sourceURL) {
            let playlistName = json["name"] as? String ?? "Unknown Playlist"
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            let rawTracks = json["tracks"] as? [[String: Any]] ?? []
            let description = "Playlist • \(rawTracks.count) items"

            let playlistResult = DownloadAlbum(
                id: id,
                name: playlistName,
                artistLine: description,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: id
            )

            let tracks = rawTracks.compactMap {
                downloadTrack(fromMetadataItem: $0, fallbackArtistLine: "Unknown Artist", fallbackAlbumName: playlistName, fallbackArtworkURL: artworkURL, sourceContext: .song, albumIdentifier: nil)
            }

            if !tracks.isEmpty {
                return (playlistResult, tracks)
            }
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/playlists/\(id)") else { return nil }
            var playlistRequest = URLRequest(url: url)
            playlistRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (playlistData, response) = try await session.data(for: playlistRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: playlistData) as? [String: Any] {
                    
                    let playlistName = json["name"] as? String ?? "Unknown Playlist"
                    let description = json["description"] as? String ?? "Spotify Playlist"
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    let playlistResult = DownloadAlbum(
                        id: id,
                        name: playlistName,
                        artistLine: description,
                        artworkURL: artworkURL,
                        sourceURL: sourceURL,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: id
                    )
                    
                    var tracks: [DownloadTrack] = []

                    if let tracksContainer = json["tracks"] as? [String: Any],
                       let items = tracksContainer["items"] as? [[String: Any]] {
                        for item in items {
                            if let track = item["track"] as? [String: Any],
                               let trackID = track["id"] as? String {
                                let trackName = track["name"] as? String ?? "Unknown Title"
                                let trackArtists = track["artists"] as? [[String: Any]] ?? []
                                let trackArtistLine = trackArtists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                                let explicit = track["explicit"] as? Bool ?? false
                                let trackURL = "https://open.spotify.com/track/\(trackID)"
                                let trackAlbum = track["album"] as? [String: Any]
                                let trackAlbumName = trackAlbum?["name"] as? String ?? "Unknown Album"
                                let trackArtworkURLString = (trackAlbum?["images"] as? [[String: Any]])?.first?["url"] as? String
                                let trackArtworkURL = trackArtworkURLString.flatMap(URL.init(string:))

                                tracks.append(DownloadTrack(
                                    id: trackID,
                                    name: trackName,
                                    artistLine: trackArtistLine.isEmpty ? "Unknown Artist" : trackArtistLine,
                                    albumName: trackAlbumName,
                                    artworkURL: trackArtworkURL ?? artworkURL,
                                    isExplicit: explicit,
                                    sourceURL: trackURL,
                                    sourceContext: .song,
                                    provider: .metadata,
                                    artistIdentifier: nil,
                                    albumIdentifier: trackAlbum?["id"] as? String,
                                    previewURL: (track["preview_url"] as? String).flatMap(URL.init(string:))
                                ))
                            }
                        }
                    }

                    return (playlistResult, tracks)
                }
            } catch {
                log("Spotify API playlist fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyPlaylistFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    private func fetchSpotifyArtist(id: String, sourceURL: String) async -> DownloadArtist? {
        if let json = await fetchSpotifyMetadata(url: sourceURL),
           let name = json["name"] as? String {
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            return DownloadArtist(
                id: id,
                name: name,
                provider: .metadata,
                artworkURL: artworkURL
            )
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/artists/\(id)") else { return nil }
            var artistRequest = URLRequest(url: url)
            artistRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (artistData, response) = try await session.data(for: artistRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: artistData) as? [String: Any] {
                    
                    let name = json["name"] as? String ?? "Unknown Artist"
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    return DownloadArtist(
                        id: id,
                        name: name,
                        provider: .metadata,
                        artworkURL: artworkURL
                    )
                }
            } catch {
                log("Spotify API artist fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyArtistFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    private func extractHTMLMetaContent(property: String, in html: String) -> String? {
        let patterns = [
            #"<meta[^>]*property=["']\#(property)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']\#(property)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let value = firstRegexCapture(in: html, pattern: pattern, group: 1) {
                return htmlDecoded(value)
            }
        }

        return nil
    }

    private func extractHTMLMetaContent(name: String, in html: String) -> String? {
        let patterns = [
            #"<meta[^>]*name=["']\#(name)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*name=["']\#(name)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let value = firstRegexCapture(in: html, pattern: pattern, group: 1) {
                return htmlDecoded(value)
            }
        }

        return nil
    }

    private func extractHTMLTagContent(tag: String, in html: String) -> String? {
        let pattern = #"<\#(tag)[^>]*>(.*?)</\#(tag)>"#
        guard let value = firstRegexCapture(in: html, pattern: pattern, group: 1) else {
            return nil
        }
        return htmlDecoded(value)
    }

    private func firstRegexCapture(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func htmlDecoded(_ value: String) -> String {
        let data = Data(value.utf8)
        if let decoded = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ).string {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexMatches(in text: String, pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard group < match.numberOfRanges,
                  let range = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private func extractSpotifyTracksFromHTML(in html: String, fallbackArtist: String, fallbackAlbumName: String, artworkURL: URL?, sourceContext: DownloadTrack.SourceContext) -> [DownloadTrack] {
        var tracks: [DownloadTrack] = []
        let segments = html.components(separatedBy: "data-testid=\"track-row\"")
        guard segments.count > 1 else { return [] }
        
        for segment in segments.dropFirst() {
            guard let trackID = firstRegexCapture(in: segment, pattern: #"href=["']/track/([a-zA-Z0-9]+)["']"#, group: 1) else {
                continue
            }
            guard let title = firstRegexCapture(in: segment, pattern: #"<span[^>]*>([^<]+)</span>"#, group: 1) else {
                continue
            }

            let artistPattern = #"href=["']/artist/[a-zA-Z0-9]+["'][^>]*>([^<]+)</a>"#
            let artistNames = regexMatches(in: segment, pattern: artistPattern, group: 1)
            let artistLine = artistNames.joined(separator: ", ")
            
            let trackURL = "https://open.spotify.com/track/\(trackID)"
            
            tracks.append(
                DownloadTrack(
                    id: trackID,
                    name: htmlDecoded(title),
                    artistLine: artistLine.isEmpty ? fallbackArtist : htmlDecoded(artistLine),
                    albumName: fallbackAlbumName,
                    artworkURL: artworkURL,
                    isExplicit: false,
                    sourceURL: trackURL,
                    sourceContext: sourceContext,
                    provider: .metadata,
                    artistIdentifier: nil,
                    albumIdentifier: nil,
                    previewURL: nil
                )
            )
        }
        return tracks
    }

    private func parseSpotifyEmbedHTML(in html: String, fallbackID: String, sourceURL: String, sourceContext: DownloadTrack.SourceContext) -> (album: DownloadAlbum, tracks: [DownloadTrack])? {
        let pattern = #"<script[^>]*id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#
        guard let jsonString = firstRegexCapture(in: html, pattern: pattern, group: 1),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let stateData = state["data"] as? [String: Any],
              let entity = stateData["entity"] as? [String: Any] else {
            return nil
        }
        
        let entityName = entity["name"] as? String ?? entity["title"] as? String ?? "Unknown Name"
        let subtitle = entity["subtitle"] as? String ?? ""
        
        var artworkURL: URL?
        if let coverArt = entity["coverArt"] as? [String: Any],
           let sources = coverArt["sources"] as? [[String: Any]],
           let firstSource = sources.first,
           let urlStr = firstSource["url"] as? String {
            artworkURL = URL(string: urlStr)
        }
        
        let albumResult = DownloadAlbum(
            id: fallbackID,
            name: entityName,
            artistLine: subtitle.isEmpty ? (sourceContext == .album ? "Unknown Artist" : "Spotify Playlist") : subtitle,
            artworkURL: artworkURL,
            sourceURL: sourceURL,
            provider: .metadata,
            artistIdentifier: nil,
            albumIdentifier: fallbackID
        )
        
        var parsedTracks: [DownloadTrack] = []
        if let trackList = entity["trackList"] as? [[String: Any]] {
            for trackObj in trackList {
                let uri = trackObj["uri"] as? String ?? ""
                let trackID: String
                if uri.hasPrefix("spotify:track:") {
                    trackID = String(uri.dropFirst("spotify:track:".count))
                } else {
                    continue
                }
                
                let title = trackObj["title"] as? String ?? "Unknown Title"
                let artists = trackObj["subtitle"] as? String ?? ""
                let explicit = trackObj["isExplicit"] as? Bool ?? false
                let trackURL = "https://open.spotify.com/track/\(trackID)"
                
                let previewURLString = (trackObj["audioPreview"] as? [String: Any])?["url"] as? String
                let previewURL = previewURLString.flatMap(URL.init(string:))
                
                parsedTracks.append(
                    DownloadTrack(
                        id: trackID,
                        name: htmlDecoded(title),
                        artistLine: artists.isEmpty ? (subtitle.isEmpty ? "Unknown Artist" : subtitle) : htmlDecoded(artists),
                        albumName: sourceContext == .album ? entityName : "Unknown Album",
                        artworkURL: artworkURL,
                        isExplicit: explicit,
                        sourceURL: trackURL,
                        sourceContext: sourceContext,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: sourceContext == .album ? fallbackID : nil,
                        previewURL: previewURL
                    )
                )
            }
        }
        
        return (albumResult, parsedTracks)
    }

    private func uniqueAlbums(_ albums: [DownloadAlbum]) -> [DownloadAlbum] {
        var seen = Set<String>()
        return albums.filter { album in
            let key = "\(album.provider.rawValue)|\(DownloadSupport.normalizedSearchValue(album.artistLine))|\(DownloadSupport.normalizedSearchValue(album.name))"
            return seen.insert(key).inserted
        }
    }

    private func uniqueTracks(_ tracks: [DownloadTrack]) -> [DownloadTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            let key = "\(track.provider.rawValue)|\(DownloadSupport.normalizedSearchValue(track.artistLine))|\(DownloadSupport.normalizedSearchValue(track.albumName))|\(DownloadSupport.normalizedSearchValue(track.name))"
            return seen.insert(key).inserted
        }
    }

    private func uniqueTracksForMetadataProfile(_ tracks: [DownloadTrack]) -> [DownloadTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            let key = "\(DownloadSupport.normalizedSearchValue(track.artistLine))|\(DownloadSupport.normalizedSearchValue(track.albumName))|\(DownloadSupport.normalizedSearchValue(track.name))"
            return seen.insert(key).inserted
        }
    }

    private func uniqueAlbumsForMetadataProfile(_ albums: [DownloadAlbum]) -> [DownloadAlbum] {
        var seen = Set<String>()
        return albums.filter { album in
            let key = "\(DownloadSupport.normalizedSearchValue(album.artistLine))|\(DownloadSupport.normalizedSearchValue(album.name))"
            return seen.insert(key).inserted
        }
    }

    private func matchesArtistLine(_ artistLine: String, artistName: String) -> Bool {
        let target = DownloadSupport.normalizedSearchValue(artistName)
        let normalizedLine = DownloadSupport.normalizedSearchValue(artistLine)
        guard !target.isEmpty, !normalizedLine.isEmpty else { return false }
        if normalizedLine == target { return true }
        let tokens = DownloadSupport.artistTokens(from: artistLine)
        return tokens.contains(where: { $0 == target || $0.contains(target) || target.contains($0) })
    }

    private func log(_ message: String) {
        Logger.shared.log("[Download] \(message)")
    }

    static let appleMusicUnavailableMessage = "Unable to download using Apple Music. Please paste the Spotify or Deezer URL."

    private func downloadFailureMessage(for track: DownloadTrack, error: Error) -> String {
        if let downloadError = error as? DownloadError, case .trackNotFound = downloadError {
            return Self.appleMusicUnavailableMessage
        }
        return Self.friendlyDownloadFailureMessage(for: error)
    }

    private static func friendlyDownloadFailureMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The download timed out. Check your connection and try again."
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection."
            case .cancelled:
                return "Download cancelled."
            default:
                return "A network error occurred. Please try again."
            }
        }

        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .invalidURL, .mappingFailed, .trackNotFound:
                return "This track isn't available right now."
            case .searchFailed:
                return "Search failed. Please try again."
            case .remoteFailure, .httpError, .emptyResponse:
                return "The download server had a problem. Please try again."
            case .fileSaveFailed:
                return "Couldn't save the downloaded file."
            }
        }

        return "Download failed. Please try again."
    }

    private func pushLiveActivityUpdate(phaseOverride: DownloadLiveActivityAttributes.Phase? = nil) {
        guard backgroundDownloadsEnabled else { return }
        let items: [DownloadLiveActivityAttributes.ActiveItem] = activeDownloadTrackIDs.sorted().compactMap { id in
            guard let track = knownTracksByID[id] else { return nil }
            return DownloadLiveActivityAttributes.ActiveItem(
                trackName: track.name,
                artistName: track.artistLine,
                progress: downloadProgressByTrackID[id] ?? 0
            )
        }
        DownloadLiveActivityManager.shared.update(
            items: items,
            queueText: queueCounterText,
            speedBps: aggregateDownloadSpeedBps,
            phase: phaseOverride ?? (isPaused ? .paused : .downloading)
        )
    }

    private func endLiveActivityIfQueueFinished(finalPhase: DownloadLiveActivityAttributes.Phase) {
        guard backgroundDownloadsEnabled else { return }
        guard activeDownloadTrackIDs.isEmpty, pendingQueue.isEmpty else {
            pushLiveActivityUpdate()
            return
        }
        DownloadLiveActivityManager.shared.end(
            queueText: "\(completedQueueCount)/\(totalQueueCount)",
            phase: finalPhase
        )
    }

    private func clearLiveActivity() {
        guard backgroundDownloadsEnabled else { return }
        DownloadLiveActivityManager.shared.clear()
    }

    private func hasHandedOffDownloadedFile(trackID: String) -> Bool {
        QueuePersistenceStore.loadPendingDownloadedImports().contains { item in
            item.trackID == trackID
        }
    }

    private func handOffDownloadedFileForMainImport(_ fileURL: URL, track: DownloadTrack) {
        var pending = QueuePersistenceStore.loadPendingDownloadedImports()
        if !pending.contains(where: { $0.localURLPath == fileURL.path || $0.trackID == track.id }) {
            pending.append(.init(localURLPath: fileURL.path, trackID: track.id, track: PersistedDownloadTrack(track: track)))
            QueuePersistenceStore.savePendingDownloadedImports(pending)
            NotificationCenter.default.post(name: .importDownloadedSongs, object: [fileURL])
            BackgroundMetadataFetchManager.shared.processPendingDownloadsInBackground()
        } else {
            log("Download handoff already exists for track \(track.id); skipping notification.")
        }
    }

    private func updateVisibleDownloadProgress(_ progress: Double, speedBps: Double, trackID: String) {
        guard activeDownloadTrackIDs.contains(trackID) else { return }
        downloadProgressByTrackID[trackID] = progress
        downloadSpeedByTrackID[trackID] = speedBps
        pushLiveActivityUpdate()
    }


    private func restorePersistedQueue() {
        guard let snapshot = QueuePersistenceStore.loadDownloadQueue() else { return }

        let restoredTracks = snapshot.tracksByID.compactMapValues(\.downloadTrack)
        guard !restoredTracks.isEmpty else {
            QueuePersistenceStore.clearDownloadQueue()
            return
        }

        knownTracksByID = restoredTracks
        queueOrder = snapshot.queueOrder.filter { restoredTracks[$0] != nil }
        totalQueueCount = snapshot.totalQueueCount
        completedQueueCount = snapshot.completedQueueCount
        restoredActiveTrackIDs = snapshot.activeIDs.filter { restoredTracks[$0] != nil }

        for id in snapshot.failedIDs where restoredTracks[id] != nil {
            trackStates[id] = .failed
            trackFailureReasons[id] = snapshot.failureReasons?[id]
        }

        for id in snapshot.doneIDs where restoredTracks[id] != nil {
            trackStates[id] = .done
        }

        let pendingIDs = snapshot.pendingIDs.filter { restoredTracks[$0] != nil }
        pendingQueue = pendingIDs.compactMap { id in
            trackStates[id] = .queued
            return restoredTracks[id]
        }

        if totalQueueCount == 0 && (!pendingQueue.isEmpty || !restoredActiveTrackIDs.isEmpty || !snapshot.failedIDs.isEmpty) {
            totalQueueCount = pendingQueue.count + snapshot.failedIDs.count + restoredActiveTrackIDs.count
        }
        completedQueueCount = min(completedQueueCount, totalQueueCount)

        if !restoredActiveTrackIDs.isEmpty {
            log("Found \(restoredActiveTrackIDs.count) active download(s) to recover from the last session.")
        } else if !pendingQueue.isEmpty {
            log("Restored \(pendingQueue.count) queued download(s) from last session.")
            if backgroundDownloadsEnabled {
                primeBackgroundPreparation()
            }
            Task { await processQueueIfNeeded() }
        } else if !snapshot.failedIDs.isEmpty {
            log("Restored \(snapshot.failedIDs.count) failed download(s) from last session.")
        }
    }

    private func syncQueuePersistence() {
        let failedIDs = queueOrder.filter { trackStates[$0] == .failed }
        let pendingIDs = pendingQueue.map(\.id)
        let hasMeaningfulState = !pendingIDs.isEmpty || !activeDownloadTrackIDs.isEmpty || !failedIDs.isEmpty

        guard hasMeaningfulState else {
            QueuePersistenceStore.clearDownloadQueue()
            return
        }

        let doneIDs = queueOrder.filter { trackStates[$0] == .done }

        let snapshot = PersistedDownloadQueue(
            tracksByID: knownTracksByID.mapValues(PersistedDownloadTrack.init),
            queueOrder: queueOrder,
            pendingIDs: pendingIDs,
            failedIDs: failedIDs,
            activeIDs: Array(activeDownloadTrackIDs),
            doneIDs: doneIDs,
            totalQueueCount: totalQueueCount,
            completedQueueCount: completedQueueCount,
            failureReasons: trackFailureReasons.filter { failedIDs.contains($0.key) }
        )
        QueuePersistenceStore.saveDownloadQueue(snapshot)
    }

    func queueSnapshot() -> DownloadQueueSnapshot {
        var items: [DownloadQueueSnapshot.Item] = []
        for id in queueOrder {
            guard let track = knownTracksByID[id] else { continue }
            let state = trackStates[id] ?? .idle
            guard state != .idle else { continue }

            let queueIndex = pendingQueue.firstIndex(where: { $0.id == id })
            let isActive = activeDownloadTrackIDs.contains(id)
            items.append(
                .init(
                    id: id,
                    name: track.name,
                    artist: track.artistLine,
                    album: track.albumName,
                    state: state,
                    isActive: isActive,
                    progress: isActive ? (downloadProgressByTrackID[id] ?? 0) : 0,
                    queueIndex: queueIndex,
                    failureReason: state == .failed ? trackFailureReasons[id] : nil,
                    qualityNote: state == .done ? trackQualityNotes[id] : nil
                )
            )
        }

        let activeItems = items.filter { $0.isActive }
        let queuedItems = items.filter { $0.queueIndex != nil && !$0.isActive }
            .sorted { ($0.queueIndex ?? 0) < ($1.queueIndex ?? 0) }
        let doneItems = items.filter { $0.state == .done }
        let failedItems = items.filter { $0.state == .failed }

        return DownloadQueueSnapshot(
            activeItems: activeItems,
            queuedItems: queuedItems,
            doneItems: doneItems,
            failedItems: failedItems,
            aggregateProgress: aggregateDownloadProgress,
            queueCounterText: queueCounterText,
            aggregateSpeedBps: aggregateDownloadSpeedBps
        )
    }
}

struct DownloadQueueSnapshot {
    struct Item: Identifiable {
        let id: String
        let name: String
        let artist: String
        let album: String
        let state: DownloadTrackState
        let isActive: Bool
        let progress: Double
        let queueIndex: Int?
        let failureReason: String?
        let qualityNote: String?
    }

    let activeItems: [Item]
    let queuedItems: [Item]
    let doneItems: [Item]
    let failedItems: [Item]
    let aggregateProgress: Double
    let queueCounterText: String
    let aggregateSpeedBps: Double
}

struct DownloadQueueDetailsSheet: View {
    @ObservedObject var vm: DownloadViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var spotifySearchItem: DownloadQueueSnapshot.Item?
    @State private var deezerSearchItem: DownloadQueueSnapshot.Item?
    @State private var copiedItemID: String?
    @State private var copiedDeezerItemID: String?
    @State private var showCopiedBanner = false

    private func trackSearchQuery(for item: DownloadQueueSnapshot.Item) -> String {
        let strippedFeaturing = item.name.replacingOccurrences(
            of: #"\s*[\(\[](?:feat(?:\.|uring)?|ft\.?)\b[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let query = strippedFeaturing
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
        return query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
    }

    private func spotifySearchURL(for item: DownloadQueueSnapshot.Item) -> URL {
        let encoded = trackSearchQuery(for: item)
        return URL(string: "https://open.spotify.com/search/\(encoded)") ?? URL(string: "https://open.spotify.com")!
    }

    private func deezerSearchURL(for item: DownloadQueueSnapshot.Item) -> URL {
        let encoded = trackSearchQuery(for: item)
        return URL(string: "https://www.deezer.com/search/\(encoded)") ?? URL(string: "https://www.deezer.com")!
    }

    private func findOnSpotify(_ item: DownloadQueueSnapshot.Item) {
        UIPasteboard.general.string = "\(item.artist) \(item.name)"
        copiedItemID = item.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
        spotifySearchItem = item
    }

    private func findOnDeezer(_ item: DownloadQueueSnapshot.Item) {
        UIPasteboard.general.string = "\(item.artist) \(item.name)"
        copiedDeezerItemID = item.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedDeezerItemID == item.id {
                copiedDeezerItemID = nil
            }
        }
        deezerSearchItem = item
    }

    var body: some View {
        let snapshot = vm.queueSnapshot()

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        DownloadQueueIndicator(
                            progress: snapshot.aggregateProgress,
                            label: snapshot.queueCounterText
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Download Queue")
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                if vm.isPaused {
                                    Button {
                                        vm.resumeQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "play.fill")
                                                .font(.caption)
                                            Text("Resume")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                                .background(Color.green.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else if vm.shouldShowPauseButton {
                                    Button {
                                        vm.pauseQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pause.fill")
                                                .font(.caption)
                                            Text("Pause")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                                .background(Color.accentColor.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if vm.shouldShowCancelButton {
                                    Button {
                                        vm.cancelQueue()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                            Text("Cancel All")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                                .background(Color.red.opacity(0.08).clipShape(Capsule()))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if !snapshot.activeItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(snapshot.activeItems.count > 1 ? "Overall Progress" : "Current Progress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(snapshot.aggregateProgress * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: snapshot.aggregateProgress)
                                .tint(.accentColor)
                            HStack {
                                Text("Speed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formattedSpeed(snapshot.aggregateSpeedBps))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if !snapshot.activeItems.isEmpty {
                    Section("In Progress") {
                        ForEach(snapshot.activeItems) { item in
                            queueRow(item)
                        }
                    }
                }

                if !snapshot.queuedItems.isEmpty {
                    Section("Queued") {
                        ForEach(snapshot.queuedItems) { item in
                            queueRow(item)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { snapshot.queuedItems[$0].id }
                            DispatchQueue.main.async {
                                for id in ids {
                                    vm.removeQueued(trackID: id)
                                }
                            }
                        }
                    }
                }

                if !snapshot.doneItems.isEmpty {
                    Section("Completed") {
                        ForEach(snapshot.doneItems) { item in
                            queueRow(item)
                        }
                    }
                }

                if !snapshot.failedItems.isEmpty {
                    Section {
                        ForEach(snapshot.failedItems) { item in
                            queueRow(item)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { snapshot.failedItems[$0].id }
                            DispatchQueue.main.async {
                                for id in ids {
                                    vm.removeFailed(trackID: id)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Failed")
                            Spacer()
                            Button("Clear All") {
                                vm.clearAllFailed()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Queue Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $spotifySearchItem) { item in
            ZStack(alignment: .bottom) {
                SafariSheetView(url: spotifySearchURL(for: item))
                    .ignoresSafeArea()

                if showCopiedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied. Paste it in the search bar.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.spring()) {
                    showCopiedBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut) {
                        showCopiedBanner = false
                    }
                }
            }
        }
        .sheet(item: $deezerSearchItem) { item in
            ZStack(alignment: .bottom) {
                SafariSheetView(url: deezerSearchURL(for: item))
                    .ignoresSafeArea()

                if showCopiedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied. Paste it in the search bar.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.spring()) {
                    showCopiedBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut) {
                        showCopiedBanner = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func queueRow(_ item: DownloadQueueSnapshot.Item) -> some View {
        HStack(spacing: 12) {
            Group {
                switch item.state {
                case .downloading:
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                case .queued:
                    Image(systemName: "clock.fill").foregroundStyle(.orange)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Button {
                        vm.retry(trackID: item.id)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                case .idle:
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let failureReason = item.failureReason {
                    Text(failureReason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .padding(.top, 1)

                    if failureReason == DownloadViewModel.appleMusicUnavailableMessage {
                        HStack(spacing: 14) {
                            Button {
                                findOnSpotify(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedItemID == item.id ? "checkmark" : "magnifyingglass")
                                        .font(.caption2)
                                    Text(copiedItemID == item.id ? "Copied, opening Spotify search…" : "Find on Spotify")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)

                            Button {
                                findOnDeezer(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedDeezerItemID == item.id ? "checkmark" : "magnifyingglass")
                                        .font(.caption2)
                                    Text(copiedDeezerItemID == item.id ? "Copied, opening Deezer search…" : "Find on Deezer")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                if item.isActive, item.state == .downloading {
                    ProgressView(value: item.progress)
                        .tint(.accentColor)
                        .padding(.top, 3)
                }
            }

            Spacer()

            if let queueIndex = item.queueIndex, !item.isActive {
                Text("#\(queueIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedSpeed(_ bps: Double) -> String {
        guard bps > 0 else { return "0 KB/s" }
        let kb = bps / 1024
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        return String(format: "%.2f MB/s", kb / 1024)
    }
}

struct SafariSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private final class ProgressiveDataFetcher: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var receivedData = Data()
    private var response: URLResponse?
    private var expectedLength: Int64 = -1
    private var progressHandler: ((Double, Double) -> Void)?
    private var session: URLSession?
    private var startedAt: CFAbsoluteTime = 0
    private var lastSampleAt: CFAbsoluteTime = 0
    private var lastSampleBytes: Int = 0
    private var smoothedSpeedBps: Double = 0
    private var task: URLSessionDataTask?

    func fetch(
        request: URLRequest,
        progress: @escaping (Double, Double) -> Void
    ) async throws -> (Data, URLResponse) {
        progressHandler = progress
        receivedData = Data()
        expectedLength = -1
        response = nil
        startedAt = CFAbsoluteTimeGetCurrent()
        lastSampleAt = startedAt
        lastSampleBytes = 0
        smoothedSpeedBps = 0

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        self.expectedLength = response.expectedContentLength
        if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(0, 0)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsedSinceLastSample = max(now - lastSampleAt, 0.001)
        let bytesSinceLastSample = max(receivedData.count - lastSampleBytes, 0)
        let instantaneousSpeedBps = Double(bytesSinceLastSample) / elapsedSinceLastSample

        if smoothedSpeedBps == 0 {
            smoothedSpeedBps = instantaneousSpeedBps
        } else {
            smoothedSpeedBps = (smoothedSpeedBps * 0.65) + (instantaneousSpeedBps * 0.35)
        }

        lastSampleAt = now
        lastSampleBytes = receivedData.count

        if expectedLength > 0 {
            let fraction = Double(receivedData.count) / Double(expectedLength)
            if let progressHandler {
                let value = max(0, min(fraction, 1))
                DispatchQueue.main.async {
                    progressHandler(value, self.smoothedSpeedBps)
                }
            }
        } else if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(0, self.smoothedSpeedBps)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
        }

        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }

        guard let response else {
            continuation?.resume(throwing: DownloadError.emptyResponse)
            continuation = nil
            return
        }

        if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(1, self.smoothedSpeedBps)
            }
        }
        continuation?.resume(returning: (receivedData, response))
        continuation = nil
    }
}

private struct AppleMusicAlbumSearchResults: Decodable {
    let albums: AppleMusicAlbumPage?
}

private struct AppleMusicAlbumSearchError: Decodable {
    let id: String?
    let title: String?
    let detail: String?
    let status: String?
    let code: String?
}

private struct AppleMusicAlbumPage: Decodable {
    let data: [AppleMusicAlbumResult]
}

private struct AppleMusicAlbumResult: Decodable {
    let id: String
    let attributes: AppleMusicAlbumResultAttributes
}

private struct AppleMusicAlbumResultAttributes: Decodable {
    let name: String
    let artistName: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

private struct AppleMusicPlaylistSearchResults: Decodable {
    let playlists: AppleMusicPlaylistPage?
}

private struct AppleMusicPlaylistPage: Decodable {
    let data: [AppleMusicPlaylistResult]
}

private struct AppleMusicAlbumDetailsData: Decodable {
    let id: String?
    let attributes: AppleMusicDirectAlbumAttributes?
    let relationships: AppleMusicAlbumRelationships?
}

private struct AppleMusicDirectAlbumAttributes: Decodable {
    let name: String
    let artistName: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
    let playParams: AppleMusicPlayParams?
}

private struct AppleMusicPlayParams: Decodable {
    let id: String?
}

private struct AppleMusicAlbumRelationships: Decodable {
    let tracks: AppleMusicAlbumTracksPage?
}

private struct AppleMusicAlbumTracksPage: Decodable {
    let data: [AppleMusicAlbumTrack]
}

private struct AppleMusicAlbumTrack: Decodable {
    let id: String
    let attributes: AppleMusicAlbumTrackAttributes
}

private struct AppleMusicAlbumTrackAttributes: Decodable {
    let name: String
    let artistName: String
    let albumName: String?
    let url: String?
    let contentRating: String?
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

private struct AppleMusicArtistResult: Decodable {
    let id: String
    let attributes: AppleMusicArtistAttributes
}

private struct AppleMusicArtistAttributes: Decodable {
    let name: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

private struct AppleMusicPlaylistResult: Decodable {
    let id: String
    let attributes: AppleMusicPlaylistAttributes
    let relationships: AppleMusicPlaylistRelationships?
}

private struct AppleMusicPlaylistAttributes: Decodable {
    let name: String
    let curatorName: String?
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

private struct AppleMusicPlaylistRelationships: Decodable {
    let tracks: AppleMusicPlaylistTracksPage?
}

private struct AppleMusicPlaylistTracksPage: Decodable {
    let data: [AppleMusicAPI.AppleMusicSong]
}

