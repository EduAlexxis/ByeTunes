import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var manager: DeviceManager
    @ObservedObject private var backgroundMetadataFetchManager = BackgroundMetadataFetchManager.shared
    @Binding var songs: [SongMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    
    struct PlaylistModel: Identifiable, Hashable {
        let name: String
        let pid: Int64
        var id: Int64 { pid }
    }
    @State private var showingMusicPicker = false
    @State private var injectProgress: CGFloat = 0
    @State private var showPlaylistAlert = false
    @State private var playlistName = ""
    @State private var showingPlaylistSheet = false
    @State private var existingPlaylists: [PlaylistModel] = []
    @State private var isFetchingPlaylists = false
    
    @State private var isImporting = false
    @State private var currentImportIndex = 0
    @State private var totalImportCount = 0
    @State private var importPhaseTitle = "Importing Songs"
    @State private var pendingDownloadedImportURLs: [URL] = []
    @AppStorage("backgroundDownloadsEnabled") private var backgroundDownloadsEnabled = false
    
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    
    @State private var currentInjectIndex = 0
    @State private var totalInjectCount = 0
    @State private var isMinimalBatchInjectionMode = false
    @State private var showingBatchMetadataEditor = false
    
    
    @State private var selectedSongForMatch: SongMetadata?
    @State private var pendingImportedSongs: [SongMetadata] = []
    @State private var pendingAlreadyImportedCount = 0
    @State private var pendingImportSkippedCount = 0
    @State private var detectedDuplicates: [DuplicateCandidate] = []
    @State private var duplicateImportSelection: [UUID: Bool] = [:]
    @State private var showingDuplicateSheet = false

    struct DuplicateCandidate: Identifiable {
        let id = UUID()
        var incoming: SongMetadata
        let matched: SongMetadata
        let reason: String
    }

    
    static var supportedAudioTypes: [UTType] {
        var types: [UTType] = [.mp3, .wav, .aiff, .mpeg4Audio, .audio, .folder]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let opus = UTType(filenameExtension: "opus") { types.append(opus) }
        return types
    }

    private var importStagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("music_import_staging", isDirectory: true)
    }

    private var shouldHideQueueDuringLargeImport: Bool {
        isImporting && totalImportCount >= Self.largeBatchThreshold
    }

    private var shouldHideQueueDuringLargeInjection: Bool {
        isInjecting && isMinimalBatchInjectionMode
    }

    private var shouldUseCompactQueueForLargeBatch: Bool {
        songs.count >= Self.largeBatchThreshold
    }

    private var shouldUseMinimalQueueUI: Bool {
        shouldHideQueueDuringLargeImport || shouldHideQueueDuringLargeInjection || shouldUseCompactQueueForLargeBatch
    }

    private var shouldShowBatchMetadataEditorTrigger: Bool {
        !songs.isEmpty && songs.count >= Self.largeBatchThreshold && !isImporting
    }

    private var pendingDownloadedMetadataCount: Int {
        pendingDownloadedImportURLs.count
    }

    private var isAutoFetchingMetadata: Bool {
        backgroundDownloadsEnabled
            && BackgroundMetadataFetchManager.isEnabled
            && pendingDownloadedMetadataCount > 0
            && backgroundMetadataFetchManager.isProcessing
    }

    private static let largeBatchThreshold = 50
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            
            VStack(alignment: .leading, spacing: 10) {
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Music")
                            .font(.system(size: 34, weight: .bold))
                        
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.heartbeatReady ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(manager.connectionStatus)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 0)
                
                
                VStack(spacing: 12) {
                    
                    Button {
                        if isAutoFetchingMetadata {
                            BackgroundMetadataFetchManager.shared.cancel()
                        } else if backgroundDownloadsEnabled && pendingDownloadedMetadataCount > 0 {
                            processDownloadedImportQueueIfNeeded()
                        } else {
                            showingMusicPicker = true
                        }
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                                    .padding(.trailing, 4)
                                Text("\(importPhaseTitle) \(currentImportIndex)/\(totalImportCount)...")
                                    .font(.body.weight(.medium))
                            } else if isAutoFetchingMetadata {
                                ZStack {
                                    HStack(spacing: 0) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                            .padding(.trailing, 4)
                                        Text("Fetching Metadata for \(pendingDownloadedMetadataCount) Song\(pendingDownloadedMetadataCount == 1 ? "" : "s")...")
                                            .font(.body.weight(.medium))
                                    }
                                    HStack {
                                        Spacer()
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .opacity(0.8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Image(systemName: backgroundDownloadsEnabled && pendingDownloadedMetadataCount > 0 ? "sparkles" : "plus")
                                    .font(.body.weight(.medium))
                                Text(backgroundDownloadsEnabled && pendingDownloadedMetadataCount > 0 ? "\(pendingDownloadedMetadataCount) Songs Ready for Metadata" : "Add Songs")
                                    .font(.body.weight(.medium))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isImporting)
                    
                    
                    Button {
                        injectSongs()
                    } label: {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(.systemGray6))
                                
                                
                                if isInjecting {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.black.opacity(0.15))
                                        .frame(width: geo.size.width * injectProgress)
                                        .animation(.easeInOut(duration: 0.3), value: injectProgress)
                                }
                                
                                
                                HStack {
                                    Spacer()
                                    if isInjecting {
                                        Text("Injecting \(currentInjectIndex)/\(totalInjectCount)")
                                            .font(.body.weight(.medium))
                                    } else {
                                        Image(systemName: "arrow.down.to.line")
                                            .font(.body.weight(.medium))
                                        Text("Inject to Device")
                                            .font(.body.weight(.medium))
                                    }
                                    Spacer()
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .disabled(!manager.heartbeatReady || songs.isEmpty || isInjecting)
                    .opacity(songs.isEmpty ? 0.5 : 1)
                    
                    
                    
                    Button {
                        isFetchingPlaylists = true
                        
                        manager.fetchPlaylists { playlists in
                            self.existingPlaylists = playlists.map { PlaylistModel(name: $0.name, pid: $0.pid) }
                            self.isFetchingPlaylists = false
                            self.showingPlaylistSheet = true
                            
                        }
                    } label: {
                        HStack {
                            if isFetchingPlaylists {
                                ProgressView()
                                    .padding(.trailing, 5)
                            } else {
                                Image(systemName: "text.badge.plus")
                                    .font(.body.weight(.medium))
                            }
                            Text(isFetchingPlaylists ? "Fetching..." : "Inject as Playlist")
                                .font(.body.weight(.medium))
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!manager.heartbeatReady || songs.isEmpty || isInjecting)
                    .opacity(songs.isEmpty ? 0.5 : 1)
                }
                
                
                if !songs.isEmpty && !isInjecting && !shouldUseMinimalQueueUI {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("IMPORTANT: Ensure Music App is closed before injecting")
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.leading)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }

                
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Queue")
                            .font(.title3.weight(.semibold))
                        
                        Spacer()
                        
                        if shouldUseMinimalQueueUI {
                            Text("\(songs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if !songs.isEmpty {
                            Text("\(songs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if shouldShowBatchMetadataEditorTrigger && !shouldUseMinimalQueueUI {
                        Button {
                            showingBatchMetadataEditor = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Review Batch Metadata")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(songs.count)")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    if shouldUseMinimalQueueUI {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(.systemGray5), lineWidth: 8)
                                        .frame(width: 48, height: 48)
                                    Circle()
                                        .trim(from: 0, to: progressRingValue)
                                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                        .frame(width: 48, height: 48)
                                        .rotationEffect(.degrees(-90))
                                    Text(progressPrimaryText)
                                        .font(.system(size: 13, weight: .semibold))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(compactQueueTitle)
                                        .font(.headline)
                                    Text(compactQueueSubtitle)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Progress")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(progressCounterText)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.secondary)
                                }

                                ProgressView(value: progressValue)
                                    .tint(.accentColor)
                            }

                            if shouldShowBatchMetadataEditorTrigger {
                                Button {
                                    showingBatchMetadataEditor = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Review Batch Metadata")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("\(songs.count)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(20)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    } else if songs.isEmpty {
                        
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(Color(.systemGray3))
                            
                            VStack(spacing: 4) {
                                Text("No songs in queue")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Tap \"Add Songs\" to get started")
                                    .font(.subheadline)
                                    .foregroundColor(Color(.systemGray))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                    VStack(spacing: 0) {
                                        
                        let canEdit = true

                                        
                                        SongRowView(
                                            song: song,
                                            showEditButton: canEdit,
                                            onEdit: {
                                                selectedSongForMatch = song
                                            },
                                            onSave: AudioTagWriter.supports(song.localURL) ? {
                                                saveTaggedCopy(of: song)
                                            } : nil
                                        ) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                songs.removeAll { $0.id == song.id }
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if canEdit {
                                                selectedSongForMatch = song
                                            }
                                        }
                                        
                                        if index < songs.count - 1 {
                                            Divider()
                                                .padding(.leading, 68)
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
                    }
                }
                
                Spacer() 
            }
            .padding(.bottom, 40) 
            .padding(.horizontal, 20)
            

        
        
        if showToast {
            HStack(spacing: 12) {
                Image(systemName: toastIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                
                Text(toastTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 24)
            .padding(.bottom, 100) 
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
        }
        .sheet(isPresented: $showingMusicPicker) {
            DocumentPicker(types: Self.supportedAudioTypes, allowsMultiple: true) { urls in
                handleMusicImport(urls: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importDownloadedSongs)) { notification in
            let urls = (notification.object as? [URL]) ?? []
            queueDownloadedImports(urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: .backgroundMetadataFetchCompleted)) { _ in
            mergeBackgroundFetchedSongsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            restorePendingDownloadedImportsIfNeeded()
            mergeBackgroundFetchedSongsIfNeeded()
            BackgroundMetadataFetchManager.shared.processPendingDownloadsInBackground()
        }
        .sheet(isPresented: $showingBatchMetadataEditor) {
            BatchMetadataEditorSheet(songs: $songs)
        }
        .sheet(item: $selectedSongForMatch) { item in
            if let index = songs.firstIndex(where: { $0.id == item.id }) {
                ManualMetadataEditor(song: $songs[index], isPresented: Binding(
                    get: { selectedSongForMatch != nil },
                    set: { if !$0 { selectedSongForMatch = nil } }
                ))
            }
        }
        .sheet(isPresented: $showingDuplicateSheet) {
            duplicateReviewSheet
        }
        .alert("Create Playlist", isPresented: $showPlaylistAlert) {
            TextField("Playlist name", text: $playlistName)
            Button("Cancel", role: .cancel) {
                playlistName = ""
            }
            Button("Create") {
                injectAsPlaylist(name: playlistName)
                playlistName = ""
            }
        } message: {
            Text("Enter a name for your new playlist")
        }
        .onAppear {
            restorePendingDownloadedImportsIfNeeded()
            mergeBackgroundFetchedSongsIfNeeded()
            BackgroundMetadataFetchManager.shared.processPendingDownloadsInBackground()
        }
        .sheet(isPresented: $showingPlaylistSheet) {
            playlistSelectionSheet
        }
    }
    
    private var playlistSelectionSheet: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("Select Playlist")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button {
                    showingPlaylistSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 10)
            .background(Color(.systemBackground))
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    Button {
                        showingPlaylistSheet = false
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showPlaylistAlert = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Text("Create New Playlist")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("EXISTING PLAYLISTS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        if existingPlaylists.isEmpty {
                            Text("No playlists found")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        } else {
                            ForEach(existingPlaylists) { playlist in
                                Button {
                                    showingPlaylistSheet = false
                                    injectAsPlaylist(name: playlist.name, pid: playlist.pid)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.1))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Text(playlist.name)
                                            .font(.system(size: 17))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    func handleMusicImport(urls: [URL]?) {
        guard let urls, !urls.isEmpty else { return }
        Task {
            await importSongs(urls: urls, stageInputFiles: true, preserveDownloadedFiles: false)
        }
    }

    private func queueDownloadedImports(_ urls: [URL]) {
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else { return }

        var existingPaths = Set(pendingDownloadedImportURLs.map(\.path))
        var newPersisted = QueuePersistenceStore.loadPendingDownloadedImports()

        for url in validURLs where existingPaths.insert(url.path).inserted {
            pendingDownloadedImportURLs.append(url)
            if !newPersisted.contains(where: { $0.localURLPath == url.path }) {
                newPersisted.append(.init(localURLPath: url.path, trackID: nil))
            }
        }

        QueuePersistenceStore.savePendingDownloadedImports(newPersisted)
    }

    private func restorePendingDownloadedImportsIfNeeded() {
        let restored = QueuePersistenceStore.loadPendingDownloadedImports()
            .map { URL(fileURLWithPath: $0.localURLPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !restored.isEmpty else { return }

        let existingPaths = Set(pendingDownloadedImportURLs.map(\.path))
        let newURLs = restored.filter { !existingPaths.contains($0.path) }
        guard !newURLs.isEmpty else { return }

        pendingDownloadedImportURLs.append(contentsOf: newURLs)
    }

    private func pruneStalePendingDownloadedImports() {
        guard !pendingDownloadedImportURLs.isEmpty else { return }
        let stillPendingPaths = Set(QueuePersistenceStore.loadPendingDownloadedImports().map(\.localURLPath))
        pendingDownloadedImportURLs.removeAll { !stillPendingPaths.contains($0.path) }
    }

    private func mergeBackgroundFetchedSongsIfNeeded() {
        pruneStalePendingDownloadedImports()

        let readySongs = BackgroundMetadataFetchManager.shared.drainReadySongs()
        guard !readySongs.isEmpty else { return }

        var existingSignatures = Set(songs.map(duplicateSignature(for:)))
        var merged: [SongMetadata] = []
        for song in readySongs {
            let signature = duplicateSignature(for: song)
            guard existingSignatures.insert(signature).inserted else { continue }
            merged.append(song)
        }

        guard !merged.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            songs.append(contentsOf: merged)
        }
    }

    private func processDownloadedImportQueueIfNeeded() {
        guard !pendingDownloadedImportURLs.isEmpty else { return }
        BackgroundMetadataFetchManager.shared.processPendingDownloadsInBackground()
    }

    private func importSongs(urls: [URL], stageInputFiles: Bool, preserveDownloadedFiles: Bool) async {
        guard !urls.isEmpty else { return }

        let stagingDirectory = importStagingDirectory
        var stagedURLs: [URL] = []
        var skippedCount = 0
        var shouldExtractArtworkDuringImport = true

        func isSupportedAudio(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ["mp3", "wav", "aiff", "m4a", "flac", "opus"].contains(ext)
        }

        func cleanedFallbackImportName(from url: URL) -> String {
            let raw = url.deletingPathExtension().lastPathComponent
            let patterns = [
                #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[ _-]+"#,
                #"^[0-9A-Fa-f]{8,}(?:-[0-9A-Fa-f]{2,})+[ _-]+"#,
                #"^[0-9]{6,}[ _-]+"#,
                #"^[0-9A-Fa-f]{10,}[ _-]+"#
            ]

            var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var didStrip = true
            while didStrip {
                didStrip = false
                for pattern in patterns {
                    let updated = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                    if updated != cleaned {
                        cleaned = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                        didStrip = true
                    }
                }
            }

            return cleaned.isEmpty ? raw : cleaned
        }

        func persistDownloadedSongIfNeeded(_ song: SongMetadata) -> SongMetadata {
            guard preserveDownloadedFiles, UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else {
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
                Logger.shared.log("[MusicView] Failed to create persistent download folder: \(error)")
                return song
            }

            let ext = song.localURL.pathExtension.isEmpty ? "flac" : song.localURL.pathExtension
            let baseName = "\(song.artist) - \(song.title)"
            let safeBaseName = baseName
                .components(separatedBy: CharacterSet(charactersIn: "/:"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var destination = directory.appendingPathComponent("\(safeBaseName.isEmpty ? song.localURL.deletingPathExtension().lastPathComponent : safeBaseName).\(ext)")
            var suffix = 1
            while FileManager.default.fileExists(atPath: destination.path) && destination.path != song.localURL.path {
                destination = directory.appendingPathComponent("\(safeBaseName.isEmpty ? song.localURL.deletingPathExtension().lastPathComponent : safeBaseName)-\(suffix).\(ext)")
                suffix += 1
            }

            if destination.path == song.localURL.path {
                return song
            }

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try AudioTagWriter.copyKeptSong(song, to: destination)
                if !stageInputFiles {
                    try? FileManager.default.removeItem(at: song.localURL)
                }
                var updatedSong = song
                updatedSong.localURL = destination
                return updatedSong
            } catch {
                Logger.shared.log("[MusicView] Failed to persist downloaded song \(song.title): \(error)")
                return song
            }
        }

        func stageFile(_ sourceURL: URL) {
            guard isSupportedAudio(sourceURL) else { return }

            if !stageInputFiles {
                stagedURLs.append(sourceURL)
                return
            }

            let safeName = sourceURL.lastPathComponent
            let ext = sourceURL.pathExtension.lowercased()
            let stagedName = "\(UUID().uuidString)_\(safeName)"
            let destURL = stagingDirectory.appendingPathComponent(stagedName)

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                stagedURLs.append(destURL)
            } catch {
                skippedCount += 1
                Task { @MainActor in
                    Logger.shared.log("[MusicView] Copy failed for \(safeName): \(error)")
                }
                let fallbackURL = stagingDirectory.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.deletingPathExtension().lastPathComponent).\(ext)")
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    do {
                        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                        try data.write(to: fallbackURL, options: .atomic)
                        stagedURLs.append(fallbackURL)
                        Task { @MainActor in
                            Logger.shared.log("[MusicView] Data fallback copy succeeded for \(safeName)")
                        }
                    } catch {
                        Task { @MainActor in
                            Logger.shared.log("[MusicView] Data fallback copy failed for \(safeName): \(error)")
                        }
                    }
                }
            }
        }

        func enrichSong(from localURL: URL) async -> SongMetadata {
            let ext = localURL.pathExtension.lowercased()
            var song: SongMetadata

            if let parsed = try? await SongMetadata.fromURL(localURL, includeArtwork: shouldExtractArtworkDuringImport) {
                song = parsed
            } else {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int) ?? 0
                let cleanedName = cleanedFallbackImportName(from: localURL)
                song = SongMetadata(
                    localURL: localURL,
                    title: cleanedName.isEmpty ? localURL.deletingPathExtension().lastPathComponent : cleanedName,
                    artist: "Unknown Artist",
                    album: "Unknown Album",
                    albumArtist: nil,
                    genre: "Unknown Genre",
                    year: Calendar.current.component(.year, from: Date()),
                    durationMs: 0,
                    fileSize: fileSize,
                    remoteFilename: SongMetadata.generateRemoteFilename(withExtension: ext),
                    artworkData: nil,
                    trackNumber: nil,
                    trackCount: nil,
                    discNumber: nil,
                    discCount: nil,
                    lyrics: nil
                )
                Logger.shared.log("[MusicView] Fallback metadata used for \(localURL.lastPathComponent)")
            }

            if !UserDefaults.standard.bool(forKey: "keepLocalMetadataForLocalFiles") {
                song = await SongMetadata.enrichDownloadedSong(song)
            }

            return persistDownloadedSongIfNeeded(song)
        }

        if stageInputFiles {
            do {
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[MusicView] Failed to create staging directory: \(error)")
            }
        }

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let fileURL = enumerator?.nextObject() as? URL {
                    stageFile(fileURL)
                }
            } else {
                let accessGranted = stageInputFiles ? url.startAccessingSecurityScopedResource() : false
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                stageFile(url)
            }
        }

        await MainActor.run {
            self.isImporting = true
            self.totalImportCount = stagedURLs.count
            self.currentImportIndex = 0
            self.importPhaseTitle = preserveDownloadedFiles ? "Importing Downloads" : "Importing Songs"
        }

        let enrichmentConcurrency: Int
        switch stagedURLs.count {
        case 251...:
            enrichmentConcurrency = 1
        case Self.largeBatchThreshold...250:
            enrichmentConcurrency = 2
        default:
            enrichmentConcurrency = 4
        }
        shouldExtractArtworkDuringImport = stagedURLs.count < Self.largeBatchThreshold
        Logger.shared.log("[MusicView] Import preparation completed. Staged \(stagedURLs.count) file(s), skipped \(skippedCount). stageInputFiles=\(stageInputFiles)")
        Logger.shared.log("[MusicView] Using enrichment concurrency: \(enrichmentConcurrency)")
        let importChunkSize = stagedURLs.count > 200 ? 100 : max(stagedURLs.count, 1)
        Logger.shared.log("[MusicView] Using import chunk size: \(importChunkSize)")
        if !shouldExtractArtworkDuringImport {
            Logger.shared.log("[MusicView] Large import detected. Queue will use lightweight artwork previews; full artwork loads during injection.")
        }

        var foundDuplicates: [DuplicateCandidate] = []
        var seenBySignature: [String: SongMetadata] = [:]
        songs.forEach { seenBySignature[duplicateSignature(for: $0)] = $0 }
        var alreadyImportedCount = 0
        var importedSongIDs: [UUID] = []

        for chunkStart in stride(from: 0, to: stagedURLs.count, by: importChunkSize) {
            let chunkEnd = min(chunkStart + importChunkSize, stagedURLs.count)
            let importChunk = Array(stagedURLs[chunkStart..<chunkEnd])
            var acceptedChunk: [SongMetadata] = []

            for batchStart in stride(from: 0, to: importChunk.count, by: enrichmentConcurrency) {
                let batchEnd = min(batchStart + enrichmentConcurrency, importChunk.count)
                let batch = Array(importChunk[batchStart..<batchEnd])

                await withTaskGroup(of: SongMetadata.self) { group in
                    for stagedURL in batch {
                        group.addTask {
                            await enrichSong(from: stagedURL)
                        }
                    }

                    for await song in group {
                        let sig = duplicateSignature(for: song)
                        if let matched = seenBySignature[sig] {
                            foundDuplicates.append(
                                DuplicateCandidate(
                                    incoming: song,
                                    matched: matched,
                                    reason: "Same title, artist, and album"
                                )
                            )
                        } else {
                            acceptedChunk.append(song)
                            seenBySignature[sig] = song
                        }
                        await MainActor.run {
                            self.currentImportIndex += 1
                        }
                    }
                }
            }

            if !acceptedChunk.isEmpty {
                importedSongIDs.append(contentsOf: acceptedChunk.map(\.id))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.15)) {
                        songs.append(contentsOf: acceptedChunk)
                    }
                }
                alreadyImportedCount += acceptedChunk.count
                acceptedChunk.removeAll(keepingCapacity: false)
            }
        }

        if !shouldExtractArtworkDuringImport, !importedSongIDs.isEmpty {
            await MainActor.run {
                self.importPhaseTitle = "Importing Artwork"
                self.currentImportIndex = 0
                self.totalImportCount = importedSongIDs.count
            }

            for (index, songID) in importedSongIDs.enumerated() {
                guard let currentSong = await MainActor.run(body: {
                    songs.first(where: { $0.id == songID })
                }) else {
                    continue
                }

                let previewData = await SongMetadata.extractEmbeddedArtworkThumbnail(from: currentSong.localURL)
                await MainActor.run {
                    if let songIndex = songs.firstIndex(where: { $0.id == songID }) {
                        songs[songIndex].artworkPreviewData = previewData
                    }
                    self.currentImportIndex = index + 1
                }
            }
        }

        await MainActor.run {
            if foundDuplicates.isEmpty {
                let totalSkipped = skippedCount
                let title: String
                if totalSkipped > 0 {
                    title = "Imported \(alreadyImportedCount), Skipped \(totalSkipped)"
                } else {
                    title = alreadyImportedCount == 1 ? "Imported 1 Song" : "Imported \(alreadyImportedCount) Songs"
                }
                showToast(title: title, icon: "checkmark.circle.fill")
            } else {
                pendingImportedSongs = foundDuplicates.map(\.incoming)
                pendingAlreadyImportedCount = alreadyImportedCount
                pendingImportSkippedCount = skippedCount
                detectedDuplicates = foundDuplicates
                duplicateImportSelection = Dictionary(
                    uniqueKeysWithValues: foundDuplicates.map { ($0.incoming.id, true) }
                )
                showingDuplicateSheet = true
            }

            self.isImporting = false
            self.importPhaseTitle = "Importing Songs"
        }

        await MainActor.run {
            processDownloadedImportQueueIfNeeded()
        }
    }

    
    func injectSongs() {
        guard !songs.isEmpty else { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        isMinimalBatchInjectionMode = songs.count >= Self.largeBatchThreshold
        
        
        manager.startHeartbeat(forceReconnect: true) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                }
                return
            }
            
            
            DispatchQueue.main.async {
                self.startInjectionProcess()
            }
        }
    }
    
    private func startInjectionProcess() {
        
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        var lastProcessedIndex = 0
        let songsToInfect = songs 
        
        manager.injectSongs(songs: songsToInfect, progress: { progressText in
            DispatchQueue.main.async {
                
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
                    
                    if !self.isMinimalBatchInjectionMode {
                        while lastProcessedIndex < index && !self.songs.isEmpty {
                            _ = self.songs.removeFirst()
                            lastProcessedIndex += 1
                        }
                    }
                }
            }
        }) { success in
            DispatchQueue.main.async {
                progressTimer.invalidate()
                
                withAnimation(.easeOut(duration: 0.3)) {
                    self.injectProgress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                    self.injectProgress = 0
                    
                    if success {
                        for song in songsToInfect {
                            if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                                try? FileManager.default.removeItem(at: song.localURL)
                            }
                        }

                        self.showToast(title: "Injection Complete", icon: "checkmark.circle.fill")
                        withAnimation {
                            self.songs.removeAll()
                        }
                    } else {
                        if lastProcessedIndex > 0 {
                            let unconfirmedSongs = Array(songsToInfect.prefix(lastProcessedIndex))
                            withAnimation {
                                self.songs.insert(contentsOf: unconfirmedSongs, at: 0)
                            }
                        }
                        self.showToast(title: "Injection Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }

    
    }

    private var progressCounterText: String {
        if shouldHideQueueDuringLargeInjection {
            return totalInjectCount > 0 ? "\(currentInjectIndex)/\(totalInjectCount)" : "0/0"
        }
        if shouldHideQueueDuringLargeImport {
            return totalImportCount > 0 ? "\(currentImportIndex)/\(totalImportCount)" : "0/0"
        }
        if shouldUseCompactQueueForLargeBatch {
            return "\(songs.count) queued"
        }
        return totalImportCount > 0 ? "\(currentImportIndex)/\(totalImportCount)" : "0/0"
    }

    private var progressValue: Double {
        if shouldHideQueueDuringLargeInjection {
            guard totalInjectCount > 0 else { return 0 }
            return Double(currentInjectIndex) / Double(totalInjectCount)
        }
        if shouldHideQueueDuringLargeImport {
            guard totalImportCount > 0 else { return 0 }
            return Double(currentImportIndex) / Double(totalImportCount)
        }
        if shouldUseCompactQueueForLargeBatch {
            return 1
        }
        guard totalImportCount > 0 else { return 0 }
        return Double(currentImportIndex) / Double(totalImportCount)
    }

    private var progressRingValue: CGFloat {
        CGFloat(min(max(progressValue, 0), 1))
    }

    private var progressPrimaryText: String {
        if shouldHideQueueDuringLargeInjection {
            return totalInjectCount > 0 ? "\(currentInjectIndex)" : "0"
        }
        if shouldHideQueueDuringLargeImport {
            return totalImportCount > 0 ? "\(currentImportIndex)" : "0"
        }
        if shouldUseCompactQueueForLargeBatch {
            return "\(songs.count)"
        }
        return "0"
    }

    private var compactQueueTitle: String {
        if shouldHideQueueDuringLargeInjection {
            return "Injecting Songs"
        }
        if shouldHideQueueDuringLargeImport {
            return importPhaseTitle
        }
        return "Large Batch Ready"
    }

    private var compactQueueSubtitle: String {
        if shouldHideQueueDuringLargeInjection {
            return "Large batch mode keeps the queue lightweight while injection finishes."
        }
        if shouldHideQueueDuringLargeImport {
            return "Large import mode keeps the queue hidden until everything is ready."
        }
        return "Use Review Batch Metadata to make edits before injecting."
    }

    private func saveTaggedCopy(of song: SongMetadata) {
        Task.detached(priority: .userInitiated) {
            do {
                let taggedURL = try AudioTagWriter.makeTaggedCopy(of: song)
                await MainActor.run {
                    ShareSheetHelper.share(items: [taggedURL]) {
                        try? FileManager.default.removeItem(at: taggedURL.deletingLastPathComponent())
                    }
                }
            } catch {
                await MainActor.run {
                    Logger.shared.log("[TagWriter] Failed to save tagged copy of \(song.title): \(error)")
                    showToast(title: "Couldn't Save Song", icon: "xmark.circle.fill")
                }
            }
        }
    }

    private func showToast(title: String, icon: String) {
        withAnimation(.spring()) {
            self.toastTitle = title
            self.toastIcon = icon
            self.showToast = true
        }
        
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.showToast = false
            }
        }
    }

    private var duplicateReviewSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.orange.opacity(0.16))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.orange)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Possible Duplicates")
                                        .font(.title2.weight(.bold))
                                    Text("We found \(detectedDuplicates.count) tracks that look like duplicates. Keep selected ones, or skip them before import.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }

                            HStack(spacing: 10) {
                                duplicateStatChip(
                                    title: "Selected",
                                    value: "\(detectedDuplicates.filter { duplicateImportSelection[$0.incoming.id] ?? true }.count)"
                                )
                                duplicateStatChip(
                                    title: "Detected",
                                    value: "\(detectedDuplicates.count)"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )

                        HStack(spacing: 10) {
                            Button("Select All") {
                                for d in detectedDuplicates {
                                    duplicateImportSelection[d.incoming.id] = true
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())

                            Button("Deselect All") {
                                for d in detectedDuplicates {
                                    duplicateImportSelection[d.incoming.id] = false
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVStack(spacing: 12) {
                            ForEach(detectedDuplicates) { item in
                                Button {
                                    let current = duplicateImportSelection[item.incoming.id] ?? true
                                    duplicateImportSelection[item.incoming.id] = !current
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill((duplicateImportSelection[item.incoming.id] ?? true) ? Color.accentColor : Color(.systemGray5))
                                                .frame(width: 30, height: 30)
                                            Image(systemName: (duplicateImportSelection[item.incoming.id] ?? true) ? "checkmark" : "circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor((duplicateImportSelection[item.incoming.id] ?? true) ? .white : Color(.systemGray3))
                                        }
                                        .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(duplicateDisplayFilename(for: item.incoming))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(2)

                                                Spacer(minLength: 8)

                                                Text("DUPLICATE")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundColor(.orange)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(Color.orange.opacity(0.12))
                                                    .clipShape(Capsule())
                                            }

                                            VStack(alignment: .leading, spacing: 8) {
                                                duplicateComparisonRow(
                                                    icon: "square.and.arrow.down",
                                                    title: "Incoming",
                                                    value: "\(item.incoming.artist) - \(item.incoming.title)"
                                                )
                                                duplicateComparisonRow(
                                                    icon: "music.note",
                                                    title: "Matches",
                                                    value: "\(item.matched.artist) - \(item.matched.title)"
                                                )
                                                HStack(spacing: 6) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                    Text(item.reason)
                                                        .font(.caption2.weight(.medium))
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke((duplicateImportSelection[item.incoming.id] ?? true) ? Color.accentColor.opacity(0.24) : Color(.systemGray5), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                }
                .background(Color(.systemGroupedBackground))

                HStack(spacing: 12) {
                    Button {
                        finalizeImportedSongs(
                            songsToImport: pendingImportedSongs,
                            duplicateIDsToSkip: Set(detectedDuplicates.map { $0.incoming.id }),
                            includeDuplicates: false,
                            initialSkippedCount: pendingImportSkippedCount,
                            alreadyImportedCount: pendingAlreadyImportedCount
                        )
                        clearPendingDuplicateState()
                    } label: {
                        Text("Skip Duplicates")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        let duplicateIDsToSkip = Set(
                            detectedDuplicates
                                .filter { !(duplicateImportSelection[$0.incoming.id] ?? true) }
                                .map { $0.incoming.id }
                        )
                        finalizeImportedSongs(
                            songsToImport: pendingImportedSongs,
                            duplicateIDsToSkip: duplicateIDsToSkip,
                            includeDuplicates: false,
                            initialSkippedCount: pendingImportSkippedCount,
                            alreadyImportedCount: pendingAlreadyImportedCount
                        )
                        clearPendingDuplicateState()
                    } label: {
                        Text("Import Selected")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .background(Color(.systemBackground))
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Duplicate Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearPendingDuplicateState()
                        showToast(title: "Import cancelled", icon: "xmark.circle.fill")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func duplicateStatChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func duplicateComparisonRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
        }
    }

    private func duplicateDisplayFilename(for song: SongMetadata) -> String {
        let originalName = song.localURL.deletingPathExtension().lastPathComponent
        let cleanedName = originalName.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}_"#,
            with: "",
            options: .regularExpression
        )
        let ext = song.localURL.pathExtension
        return ext.isEmpty ? cleanedName : "\(cleanedName).\(ext)"
    }

    private func duplicateSignature(for song: SongMetadata) -> String {
        "\(normalizeDuplicateField(song.title))|\(normalizeDuplicateField(song.artist))|\(normalizeDuplicateField(song.album))"
    }

    private func normalizeDuplicateField(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func finalizeImportedSongs(
        songsToImport: [SongMetadata],
        duplicateIDsToSkip: Set<UUID>,
        includeDuplicates: Bool,
        initialSkippedCount: Int,
        alreadyImportedCount: Int = 0
    ) {
        let acceptedSongs: [SongMetadata]
        let duplicateSkipped = duplicateIDsToSkip.count

        if includeDuplicates {
            acceptedSongs = songsToImport
        } else {
            acceptedSongs = songsToImport.filter { !duplicateIDsToSkip.contains($0.id) }
            let skippedSongs = songsToImport.filter { duplicateIDsToSkip.contains($0.id) }
            for song in skippedSongs {
                if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                    try? FileManager.default.removeItem(at: song.localURL)
                }
            }
        }

        let totalImported = alreadyImportedCount + acceptedSongs.count

        if !acceptedSongs.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) {
                songs.append(contentsOf: acceptedSongs)
            }
        }

        if totalImported > 0 {
            let totalSkipped = initialSkippedCount + duplicateSkipped
            let title: String
            if totalSkipped > 0 {
                title = "Imported \(totalImported), Skipped \(totalSkipped)"
            } else {
                title = totalImported == 1 ? "Imported 1 Song" : "Imported \(totalImported) Songs"
            }
            showToast(title: title, icon: "checkmark.circle.fill")
        } else {
            Logger.shared.log("[MusicView] No songs imported from selection")
            showToast(title: "No songs imported", icon: "exclamationmark.triangle")
        }
    }

    private func clearPendingDuplicateState() {
        pendingImportedSongs.removeAll()
        pendingAlreadyImportedCount = 0
        detectedDuplicates.removeAll()
        duplicateImportSelection.removeAll()
        pendingImportSkippedCount = 0
        showingDuplicateSheet = false
    }

    
    func injectAsPlaylist(name: String? = nil, pid: Int64? = nil) {
        guard !songs.isEmpty else { return }
        if name == nil && pid == nil { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        isMinimalBatchInjectionMode = songs.count >= Self.largeBatchThreshold

        
        
        manager.startHeartbeat(forceReconnect: true) { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                }
                return
            }
             
            DispatchQueue.main.async {
                self.startPlaylistInjection(name: name, pid: pid)
            }
        }
    }

    private func startPlaylistInjection(name: String?, pid: Int64?) {
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        var lastProcessedIndex = 0
        let songsToInfect = songs
        
        manager.injectSongsAsPlaylist(songs: songsToInfect, playlistName: name, targetPlaylistPid: pid, progress: { progressText in
            DispatchQueue.main.async {
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
                    
                    if !self.isMinimalBatchInjectionMode {
                        while lastProcessedIndex < index && !self.songs.isEmpty {
                            _ = self.songs.removeFirst()
                            lastProcessedIndex += 1
                        }
                    }
                }
            }
        }) { success in
            DispatchQueue.main.async {
                progressTimer.invalidate()
                
                withAnimation(.easeOut(duration: 0.3)) {
                    self.injectProgress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isInjecting = false
                    self.isMinimalBatchInjectionMode = false
                    self.injectProgress = 0
                    
                    if success {
                        for song in songsToInfect {
                            if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                                try? FileManager.default.removeItem(at: song.localURL)
                            }
                        }

                        self.showToast(title: "Playlist Updated", icon: "checkmark.circle.fill")
                        withAnimation {
                            self.songs.removeAll()
                        }
                    } else {
                        if lastProcessedIndex > 0 {
                            let unconfirmedSongs = Array(songsToInfect.prefix(lastProcessedIndex))
                            withAnimation {
                                self.songs.insert(contentsOf: unconfirmedSongs, at: 0)
                            }
                        }
                        self.showToast(title: "Playlist Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }
    }
}

private struct BatchMetadataEditorSheet: View {
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
