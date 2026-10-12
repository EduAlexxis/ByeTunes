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
    @ObservedObject private var serverStatus = ServerStatusStore.shared
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
                            label: vm.queueCounterText,
                            symbol: vm.queueIndicatorSymbol
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
                if serverStatus.isVisible {
                    ServerStatusBanner(status: serverStatus.resolved, onDismiss: { serverStatus.dismissBanner() })
                }
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
        .onAppear {
            Task { await serverStatus.refresh() }
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
                                        HStack(spacing: 8) {
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
                                        }
                                        .padding(12)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
