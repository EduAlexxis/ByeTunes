import SwiftUI
import Combine
import UIKit

struct DownloadView: View {
    private enum ResultsPage: String {
        case songs = "Songs"
        case albums = "Albums"
    }

    private struct AlbumSelectionState {
        var album: DownloadAlbum?
        var tracks: [DownloadTrack] = []
        var selectedTrackIDs: Set<String> = []
        var isLoading = false
        var errorText: String?

        var isPresented: Bool { album != nil }
        var selectedTracks: [DownloadTrack] {
            tracks.filter { selectedTrackIDs.contains($0.id) }
        }
    }

    @Binding var songs: [SongMetadata]
    @Binding var status: String
    @StateObject private var vm = DownloadViewModel()
    @State private var query = ""
    @State private var handledEmittedCount = 0
    @State private var selectedPage: ResultsPage = .songs
    @State private var showingQueueDetails = false
    @State private var albumSelection = AlbumSelectionState()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Download")
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                    if vm.shouldShowQueueIndicator {
                        Button {
                            showingQueueDetails = true
                        } label: {
                            DownloadQueueIndicator(
                                progress: vm.currentSongProgress,
                                label: vm.queueCounterText
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 0)
                .padding(.horizontal, 20)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Apple Music songs", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await vm.search(query: query) }
                        }

                    if vm.isSearching {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                            vm.songResults = []
                            vm.albumResults = []
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
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }

                HStack {
                    Text("Results")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if !vm.songResults.isEmpty || !vm.albumResults.isEmpty {
                        Text("\(vm.songResults.count) songs • \(vm.albumResults.count) albums")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                if vm.songResults.isEmpty && vm.albumResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(Color(.systemGray3))
                        VStack(spacing: 4) {
                            Text("No results yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Search a song and tap download")
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
                                }
                            } else {
                                if vm.albumResults.isEmpty {
                                    emptyPage("No albums", subtitle: "No album matches for this search")
                                } else {
                                    ForEach(Array(vm.albumResults.enumerated()), id: \.element.id) { index, album in
                                        albumRow(album)
                                        if index < vm.albumResults.count - 1 {
                                            Divider().padding(.leading, 80)
                                        }
                                    }
                                }
                            }
                        }
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
        .sheet(isPresented: $showingQueueDetails) {
            DownloadQueueDetailsSheet(vm: vm)
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
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(.systemBackground))
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

    @ViewBuilder
    private func songRow(_ track: DownloadTrack) -> some View {
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

                        Text("Choose the tracks you want to download, or grab the full album in one tap.")
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
            .navigationTitle("Album Download")
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
            errorText: nil
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
}

#Preview {
    DownloadView(songs: .constant([]), status: .constant("Ready"))
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
}

struct DownloadAlbum: Identifiable {
    let id: String
    let name: String
    let artistLine: String
    let artworkURL: URL?
    let sourceURL: String
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

struct BackendCandidate {
    let label: String
    let request: URLRequest
}

struct BackendDownloadOutcome {
    let fileURL: URL
    let backendLabel: String
}

enum DownloadPlatform: String {
    case appleMusic
    case spotify
    case deezer
    case tidal
    case unknown

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .deezer: return "Deezer"
        case .tidal: return "Tidal"
        case .unknown: return "Unknown"
        }
    }

    var backendGenreSource: String {
        switch self {
        case .appleMusic: return "apple_music"
        case .spotify: return "spotify"
        case .deezer: return "deezer"
        case .tidal: return "tidal"
        case .unknown: return "unknown"
        }
    }
}

struct DownloadSourceChoice {
    let platform: DownloadPlatform
    let url: String
    let backendGenreSource: String
}

enum DownloadError: LocalizedError {
    case invalidURL(String)
    case searchFailed
    case mappingFailed(String)
    case remoteFailure(String)
    case httpError(Int, String)
    case emptyResponse
    case fileSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .searchFailed: return "Search failed."
        case .mappingFailed(let message): return message
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
        if type.contains("flac") { return "flac" }
        if type.contains("mpeg") || type.contains("mp3") { return "mp3" }
        if type.contains("aac") || type.contains("mp4") { return "m4a" }
        if type.contains("wav") { return "wav" }
        return fallback
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

    static func tidalTrackID(from urlString: String) -> String? {
        guard let range = urlString.range(of: "/track/") else { return nil }
        let tail = urlString[range.upperBound...]
        let id = tail.split(separator: "?").first?.split(separator: "/").first
        let value = id.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var songResults: [DownloadTrack] = []
    @Published var albumResults: [DownloadAlbum] = []
    @Published var isSearching = false
    @Published var errorText: String?
    @Published var activeDownloadTrackID: String?
    @Published var emittedSongs: [SongMetadata] = []
    @Published private(set) var totalQueueCount = 0
    @Published private(set) var completedQueueCount = 0
    @Published private(set) var currentSongProgress: Double = 0
    @Published private(set) var currentDownloadSpeedBps: Double = 0

    private let session: URLSession = .shared
    private var pendingQueue: [DownloadTrack] = []
    private var isProcessingQueue = false
    private var trackStates: [String: DownloadTrackState] = [:]
    private var knownTracksByID: [String: DownloadTrack] = [:]
    private var queueOrder: [String] = []
    private var albumTrackIDs: [String: [String]] = [:]
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @Published private var resolvingAlbumIDs: Set<String> = []

    var queueProgress: Double {
        guard totalQueueCount > 0 else { return 0 }
        return Double(completedQueueCount) / Double(totalQueueCount)
    }

    var queueStatusText: String {
        guard totalQueueCount > 0 else { return "Apple Music Search" }
        if let _ = activeDownloadTrackID, completedQueueCount < totalQueueCount {
            return "\(completedQueueCount + 1)/\(totalQueueCount)"
        }
        return "\(completedQueueCount)/\(totalQueueCount)"
    }

    var shouldShowQueueIndicator: Bool {
        totalQueueCount > 0 && (activeDownloadTrackID != nil || !pendingQueue.isEmpty || completedQueueCount < totalQueueCount)
    }

    var queueCounterText: String {
        guard totalQueueCount > 0 else { return "0/0" }
        if activeDownloadTrackID != nil {
            return "\(min(completedQueueCount + 1, totalQueueCount))/\(totalQueueCount)"
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
        return await fetchAlbumTracks(albumID: album.id, fallbackAlbumName: album.name)
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
        _ = enqueueMany([track])
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

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            songResults = []
            albumResults = []
            return
        }
        isSearching = true
        errorText = nil
        defer { isSearching = false }

        let songs = await AppleMusicAPI.shared.searchSongs(query: trimmed, limit: 25)
        let albums = await searchAlbums(query: trimmed, limit: 15)
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

        songResults = songs.map { item in
            let songURL = "https://music.apple.com/\(region)/song/\(item.id)"
            return DownloadTrack(
                id: item.id,
                name: item.attributes.name,
                artistLine: item.attributes.artistName,
                albumName: item.attributes.albumName ?? "Unknown Album",
                artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                isExplicit: item.attributes.contentRating == "explicit",
                sourceURL: songURL,
                sourceContext: .song
            )
        }

        albumResults = albums.map { item in
            let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
            return DownloadAlbum(
                id: item.id,
                name: item.attributes.name,
                artistLine: item.attributes.artistName,
                artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                sourceURL: albumURL
            )
        }
    }

    private func processQueueIfNeeded() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        beginBackgroundTaskIfNeeded()
        defer {
            isProcessingQueue = false
            endBackgroundTaskIfNeeded()
        }

        while !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            errorText = nil
            activeDownloadTrackID = track.id
            trackStates[track.id] = .downloading
            currentSongProgress = 0
            currentDownloadSpeedBps = 0

            do {
                let outcome = try await downloadWithFallbacks(track: track)
                log("Download finished via \(outcome.backendLabel): \(outcome.fileURL.lastPathComponent)")
                var song = try await SongMetadata.fromURL(outcome.fileURL)
                song = await enrichDownloadedSong(song, sourceTrack: track)
                song = persistDownloadedSongIfNeeded(song)
                emittedSongs.append(song)
                trackStates[track.id] = .done
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                log("Download failed: \(message)")
                errorText = message
                trackStates[track.id] = .failed
            }

            completedQueueCount += 1
            activeDownloadTrackID = nil
            currentSongProgress = 0
            currentDownloadSpeedBps = 0
        }
    }

    @discardableResult
    private func enqueueMany(_ tracks: [DownloadTrack]) -> Int {
        let validTracks = tracks.filter { canEnqueue(trackID: $0.id) }
        guard !validTracks.isEmpty else { return 0 }

        if totalQueueCount == completedQueueCount && activeDownloadTrackID == nil && pendingQueue.isEmpty {
            totalQueueCount = 0
            completedQueueCount = 0
        }

        for track in validTracks {
            knownTracksByID[track.id] = track
            if !queueOrder.contains(track.id) {
                queueOrder.append(track.id)
            }
            pendingQueue.append(track)
            trackStates[track.id] = .queued
            totalQueueCount += 1
        }

        Task { await processQueueIfNeeded() }
        return validTracks.count
    }

    private func enrichDownloadedSong(_ initialSong: SongMetadata, sourceTrack: DownloadTrack) async -> SongMetadata {
        var song = initialSong

        song = await SongMetadata.enrichWithExactAppleMusicTrack(song, trackID: sourceTrack.id)

        if song.storeId == 0 {
            song = await SongMetadata.enrichWithAppleMusicMetadata(song)
        }

        if song.lyrics == nil || song.lyrics?.isEmpty == true {
            if let fetchedLyrics = await SongMetadata.fetchLyrics(
                title: song.title,
                artist: song.artist,
                album: song.album,
                durationMs: song.durationMs
            ) {
                song.lyrics = fetchedLyrics
            }
        }

        return song
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "DownloadQueue") { [weak self] in
            Logger.shared.log("[Download] Background task expired while queue was active")
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func downloadWithFallbacks(track: DownloadTrack) async throws -> BackendDownloadOutcome {
        let resolvedSource = try await preferredDownloadSource(for: track.sourceURL)
        log("Using primary source URL (\(resolvedSource.platform.displayName)): \(resolvedSource.url)")

        let primaryCandidates = try primaryCandidates(for: resolvedSource)
        do {
            if let outcome = try await executeCandidatesUntilSuccess(
                primaryCandidates,
                suggestedName: "\(track.artistLine) - \(track.name)",
                fallbackExtension: "flac"
            ) {
                return outcome
            }
        } catch {
            log("Primary backend chain exhausted: \(error.localizedDescription)")
        }

        log("Yoinkify failed. Preparing Tidal fallback backends.")

        let mappedURL = try await fetchMappedURL(for: mappingSeedURL(for: track.sourceURL), platform: .tidal)
        log("Mapped Tidal URL: \(mappedURL)")

        guard let trackID = DownloadSupport.tidalTrackID(from: mappedURL), !trackID.isEmpty else {
            throw DownloadError.mappingFailed("Could not extract Tidal track ID.")
        }

        let fallbackCandidates = tidalCandidates(trackID: trackID)
        guard let outcome = try await executeCandidatesUntilSuccess(
            fallbackCandidates,
            suggestedName: "\(track.artistLine) - \(track.name)",
            fallbackExtension: "flac"
        ) else {
            throw DownloadError.mappingFailed("All configured download backends failed.")
        }

        return outcome
    }

    private func preferredDownloadSource(for sourceURL: String) async throws -> DownloadSourceChoice {
        let platform: DownloadPlatform
        if sourceURL.contains("music.apple.com") || sourceURL.contains("itunes.apple.com") {
            platform = .appleMusic
        } else if sourceURL.contains("spotify.com") {
            platform = .spotify
        } else if sourceURL.contains("deezer.com") {
            platform = .deezer
        } else if sourceURL.contains("tidal.com") {
            platform = .tidal
        } else {
            platform = .unknown
        }
        return DownloadSourceChoice(platform: platform, url: sourceURL, backendGenreSource: platform.backendGenreSource)
    }

    private func primaryCandidates(for source: DownloadSourceChoice) throws -> [BackendCandidate] {
        var candidates: [BackendCandidate] = []

        if let url = URL(string: "https://yoinkify.lol/api/download") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "url": source.url,
                "format": "flac",
                "genreSource": source.backendGenreSource
            ])
            candidates.append(BackendCandidate(label: "Yoinkify", request: request))
        }

        return candidates
    }

    private func tidalCandidates(trackID: String) -> [BackendCandidate] {
        let backends = [
            ("HiFi One", "https://hifi-one.spotisaver.net/track/?id=\(trackID)&quality=LOSSLESS"),
            ("HiFi Two", "https://hifi-two.spotisaver.net/track/?id=\(trackID)&quality=LOSSLESS"),
            ("Triton", "https://triton.squid.wtf/track/?id=\(trackID)&quality=LOSSLESS")
        ]
        return backends.compactMap { makeRequest(label: $0.0, urlString: $0.1) }
    }

    private func executeCandidatesUntilSuccess(
        _ candidates: [BackendCandidate],
        suggestedName: String,
        fallbackExtension: String
    ) async throws -> BackendDownloadOutcome? {
        guard !candidates.isEmpty else {
            throw DownloadError.mappingFailed("No usable backend request was created.")
        }

        var lastError: Error = DownloadError.mappingFailed("All backend requests failed.")

        for candidate in candidates {
            do {
                let fileURL = try await executeDownloadRequest(
                    candidate.request,
                    suggestedName: suggestedName,
                    fallbackExtension: fallbackExtension
                )
                log("\(candidate.label) backend succeeded.")
                return BackendDownloadOutcome(fileURL: fileURL, backendLabel: candidate.label)
            } catch {
                lastError = error
                log("\(candidate.label) backend failed: \(error.localizedDescription)")
            }
        }

        throw lastError
    }

    private func executeDownloadRequest(
        _ request: URLRequest,
        suggestedName: String,
        fallbackExtension: String,
        depth: Int = 0
    ) async throws -> URL {
        if depth > 4 {
            throw DownloadError.mappingFailed("Too many redirect/manifest hops.")
        }

        log("Requesting \(request.url?.absoluteString ?? "<unknown>")")

        let (data, response) = try await fetchDataWithProgress(for: request) { [weak self] progress, speedBps in
            self?.currentSongProgress = progress
            self?.currentDownloadSpeedBps = speedBps
        }
        try validateHTTP(response: response, data: data)

        if let manifestURL = extractManifestURL(from: data) {
            log("Resolved manifest media URL: \(manifestURL)")
            let redirectedRequest = URLRequest(url: manifestURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
                depth: depth + 1
            )
        }

        if let redirectedURL = extractRedirectURL(from: data) {
            log("Received JSON redirect: \(redirectedURL)")
            let redirectedRequest = URLRequest(url: redirectedURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
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

        let fileExtension = DownloadSupport.fileExtension(for: mimeType, fallback: fallbackExtension)
        return try saveDownloadedData(data, suggestedName: suggestedName, fileExtension: fileExtension)
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

        let keys = ["manifest_url", "manifestUrl", "stream_url", "streamUrl", "media_url", "mediaUrl"]
        for key in keys {
            if let value = obj[key] as? String, let url = URL(string: value) {
                return url
            }
        }
        if let dataObj = obj["data"] as? [String: Any] {
            for key in keys {
                if let value = dataObj[key] as? String, let url = URL(string: value) {
                    return url
                }
            }
            if let manifest = dataObj["manifest"] as? String,
               let resolved = decodeManifestMediaURL(manifest) {
                return resolved
            }
        }
        if let manifest = obj["manifest"] as? String,
           let resolved = decodeManifestMediaURL(manifest) {
            return resolved
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

    private func padBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    private func extractRedirectURL(from data: Data) -> URL? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let keys = ["url", "download_url", "downloadUrl", "redirect_url", "redirectUrl", "link"]
        for key in keys {
            if let value = obj[key] as? String, let url = URL(string: value) {
                return url
            }
        }
        if let dataObj = obj["data"] as? [String: Any] {
            for key in keys {
                if let value = dataObj[key] as? String, let url = URL(string: value) {
                    return url
                }
            }
        }
        return nil
    }

    private func saveDownloadedData(_ data: Data, suggestedName: String, fileExtension: String) throws -> URL {
        let base = DownloadSupport.tidyFilename(suggestedName)
        let keepDownloadedSongs = UserDefaults.standard.bool(forKey: "keepDownloadedSongs")
        let directory: URL

        if keepDownloadedSongs {
            directory = SongMetadata.persistentDownloadsDirectory()
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadCache", isDirectory: true)
        }

        let needsSecurityScope = keepDownloadedSongs && directory.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                directory.stopAccessingSecurityScopedResource()
            }
        }

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

    private func fetchMappedURL(for seedURL: String, platform: DownloadPlatform) async throws -> String {
        guard let url = URL(string: "https://api.song.link/v1-alpha.1/links?url=\(seedURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            throw DownloadError.invalidURL(seedURL)
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        try validateHTTP(response: response, data: data)

        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let links = obj["linksByPlatform"] as? [String: Any],
            let entry = links[platform.rawValue] as? [String: Any],
            let mapped = entry["url"] as? String,
            !mapped.isEmpty
        else {
            throw DownloadError.mappingFailed("Song.link could not map URL to \(platform.displayName).")
        }
        return mapped
    }

    private func mappingSeedURL(for sourceURL: String) -> String {
        sourceURL
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

    private func makeRequest(label: String, urlString: String) -> BackendCandidate? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return BackendCandidate(label: label, request: request)
    }

    private func searchAlbums(query: String, limit: Int) async -> [AppleMusicAlbumResult] {
        guard let token = await AppleMusicAPI.shared.getToken() else { return [] }

        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(region)/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "types", value: "albums"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")

        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(AppleMusicAlbumSearchResponse.self, from: data)
            return decoded.results.albums?.data ?? []
        } catch {
            log("Album search failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchAlbumTracks(albumID: String, fallbackAlbumName: String) async -> [DownloadTrack] {
        guard let token = await AppleMusicAPI.shared.getToken() else { return [] }

        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/\(region)/albums/\(albumID)")!
        components.queryItems = [
            URLQueryItem(name: "include", value: "tracks")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")

        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(AppleMusicAlbumDetailsResponse.self, from: data)
            guard
                let albumData = decoded.data.first,
                let tracks = albumData.relationships?.tracks?.data
            else {
                return []
            }

            return tracks.map { item in
                let songURL = "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? fallbackAlbumName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .album
                )
            }
        } catch {
            log("Album tracks fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func log(_ message: String) {
        Logger.shared.log("[Download] \(message)")
    }

    func queueSnapshot() -> DownloadQueueSnapshot {
        var items: [DownloadQueueSnapshot.Item] = []
        for id in queueOrder {
            guard let track = knownTracksByID[id] else { continue }
            let state = trackStates[id] ?? .idle
            guard state != .idle else { continue }

            let queueIndex = pendingQueue.firstIndex(where: { $0.id == id })
            items.append(
                .init(
                    id: id,
                    name: track.name,
                    artist: track.artistLine,
                    album: track.albumName,
                    state: state,
                    isActive: activeDownloadTrackID == id,
                    queueIndex: queueIndex
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
            currentSongProgress: currentSongProgress,
            queueCounterText: queueCounterText,
            currentDownloadSpeedBps: currentDownloadSpeedBps
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
        let queueIndex: Int?
    }

    let activeItems: [Item]
    let queuedItems: [Item]
    let doneItems: [Item]
    let failedItems: [Item]
    let currentSongProgress: Double
    let queueCounterText: String
    let currentDownloadSpeedBps: Double
}

struct DownloadQueueDetailsSheet: View {
    @ObservedObject var vm: DownloadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = vm.queueSnapshot()

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        DownloadQueueIndicator(
                            progress: snapshot.currentSongProgress,
                            label: snapshot.queueCounterText
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download Queue")
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 4)

                    if !snapshot.activeItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Current Progress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(snapshot.currentSongProgress * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: snapshot.currentSongProgress)
                                .tint(.accentColor)
                            HStack {
                                Text("Speed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formattedSpeed(snapshot.currentDownloadSpeedBps))
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
                    Section("Failed") {
                        ForEach(snapshot.failedItems) { item in
                            queueRow(item)
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

        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let task = session.dataTask(with: request)
            task.resume()
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

private struct AppleMusicAlbumSearchResponse: Decodable {
    let results: AppleMusicAlbumSearchResults
}

private struct AppleMusicAlbumSearchResults: Decodable {
    let albums: AppleMusicAlbumPage?
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

private struct AppleMusicAlbumDetailsResponse: Decodable {
    let data: [AppleMusicAlbumDetailsData]
}

private struct AppleMusicAlbumDetailsData: Decodable {
    let relationships: AppleMusicAlbumRelationships?
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
    let contentRating: String?
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}
