import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {
    @ObservedObject var manager: DeviceManager
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
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    @State private var currentInjectIndex = 0
    @State private var totalInjectCount = 0
    
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
        return types
    }

    private var importStagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("music_import_staging", isDirectory: true)
    }

    private var shouldHideQueueDuringLargeImport: Bool {
        isImporting && totalImportCount > 100
    }
    
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
                        showingMusicPicker = true
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                                    .padding(.trailing, 4)
                                Text("\(importPhaseTitle) \(currentImportIndex)/\(totalImportCount)...")
                                    .font(.body.weight(.medium))
                            } else {
                                Image(systemName: "plus")
                                    .font(.body.weight(.medium))
                                Text("Add Songs")
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
                
                if !songs.isEmpty && !isInjecting && !shouldHideQueueDuringLargeImport {
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
                        
                        if shouldHideQueueDuringLargeImport {
                            Text("Appears after import")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if !songs.isEmpty {
                            Text("\(songs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if shouldHideQueueDuringLargeImport {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(.systemGray5), lineWidth: 8)
                                        .frame(width: 48, height: 48)
                                    Circle()
                                        .trim(from: 0, to: totalImportCount > 0 ? CGFloat(currentImportIndex) / CGFloat(totalImportCount) : 0)
                                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                        .frame(width: 48, height: 48)
                                        .rotationEffect(.degrees(-90))
                                    Text(totalImportCount > 0 ? "\(currentImportIndex)" : "0")
                                        .font(.system(size: 13, weight: .semibold))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(importPhaseTitle)
                                        .font(.headline)
                                    Text("Large import mode keeps the queue hidden until everything is ready.")
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
                                    Text(totalImportCount > 0 ? "\(currentImportIndex)/\(totalImportCount)" : "0/0")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.secondary)
                                }

                                ProgressView(value: totalImportCount > 0 ? Double(currentImportIndex) / Double(totalImportCount) : 0)
                                    .tint(.accentColor)
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
                                            }
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
        guard let urls = urls, !urls.isEmpty else { return }
        
        let metadataSource = UserDefaults.standard.string(forKey: "metadataSource") ?? "local"
        let autofetch = UserDefaults.standard.bool(forKey: "autofetchMetadata")
        let fetchLyrics = UserDefaults.standard.bool(forKey: "fetchLyrics")
        
        let stagingDirectory = importStagingDirectory
        
        Task {
            var stagedURLs: [URL] = []
            var skippedCount = 0
            var shouldExtractArtworkDuringImport = true
            
            func isSupportedAudio(_ url: URL) -> Bool {
                let ext = url.pathExtension.lowercased()
                return ["mp3", "wav", "aiff", "m4a", "flac"].contains(ext)
            }
            
            func stageFile(_ sourceURL: URL) {
                guard isSupportedAudio(sourceURL) else { return }
                
                let safeName = sourceURL.lastPathComponent
                let uniqueFolder = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let destURL = uniqueFolder.appendingPathComponent(safeName)
                
                do {
                    try FileManager.default.createDirectory(at: uniqueFolder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    stagedURLs.append(destURL)
                } catch {
                    Task { @MainActor in
                        Logger.shared.log("[MusicView] Copy failed for \(safeName): \(error)")
                    }
                    
                    if FileManager.default.fileExists(atPath: sourceURL.path) {
                        do {
                            try FileManager.default.createDirectory(at: uniqueFolder, withIntermediateDirectories: true)
                            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                            try data.write(to: destURL, options: .atomic)
                            stagedURLs.append(destURL)
                            Task { @MainActor in
                                Logger.shared.log("[MusicView] Data fallback copy succeeded for \(safeName)")
                            }
                        } catch {
                            skippedCount += 1
                            Task { @MainActor in
                                Logger.shared.log("[MusicView] Data fallback copy failed for \(safeName): \(error)")
                            }
                        }
                    } else {
                        skippedCount += 1
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
                    song = SongMetadata(
                        localURL: localURL,
                        title: localURL.deletingPathExtension().lastPathComponent,
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
                    await Logger.shared.log("[MusicView] Fallback metadata used for \(localURL.lastPathComponent)")
                }
                
                song = sanitizeImportedSong(song)
                
                song = await enrichSongWithSelectedMetadata(
                    song,
                    metadataSource: metadataSource,
                    autofetch: autofetch
                )
                
                song = sanitizeImportedSong(song)
                
                let appleSubscriptionLyrics = UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")
                if fetchLyrics && !appleSubscriptionLyrics && (song.lyrics == nil || song.lyrics?.isEmpty == true) {
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

            do {
                if FileManager.default.fileExists(atPath: stagingDirectory.path) {
                    try? FileManager.default.removeItem(at: stagingDirectory)
                }
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[MusicView] Failed to create staging directory: \(error)")
            }
            
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                    
                    let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                    while let fileURL = enumerator?.nextObject() as? URL {
                        stageFile(fileURL)
                    }
                } else {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                    stageFile(url)
                }
            }
            
            await MainActor.run {
                self.isImporting = true
                self.totalImportCount = stagedURLs.count
                self.currentImportIndex = 0
                self.importPhaseTitle = "Importing Songs"
            }
            
            let enrichmentConcurrency: Int
            switch stagedURLs.count {
            case 251...:
                enrichmentConcurrency = 1
            case 101...250:
                enrichmentConcurrency = 2
            default:
                enrichmentConcurrency = 4
            }
            shouldExtractArtworkDuringImport = stagedURLs.count <= 100
            Logger.shared.log("[MusicView] Staging completed. Staged \(stagedURLs.count) file(s), skipped \(skippedCount).")
            Logger.shared.log("[MusicView] Using enrichment concurrency: \(enrichmentConcurrency)")
            let importChunkSize = stagedURLs.count > 200 ? 100 : stagedURLs.count
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

                // For large imports, extract artwork in batches to control memory pressure.
                // The database builder requires artworkData (not just the thumbnail preview)
                // to write artwork records into the MediaLibrary database.
                let batchSize = importedSongIDs.count > 250 ? 25 : 50
                for batchStart in stride(from: 0, to: importedSongIDs.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, importedSongIDs.count)
                    let batch = Array(importedSongIDs[batchStart..<batchEnd])

                    await withTaskGroup(of: (id: UUID, artworkData: Data?, previewData: Data?).self) { group in
                        for songID in batch {
                            group.addTask {
                                guard let currentSong = await MainActor.run(body: {
                                    songs.first(where: { $0.id == songID })
                                }) else {
                                    return (id: songID, artworkData: nil, previewData: nil)
                                }

                                // Skip if artworkData is already populated from earlier enrichment
                                if currentSong.artworkData != nil {
                                    return (
                                        id: songID,
                                        artworkData: currentSong.artworkData,
                                        previewData: currentSong.artworkPreviewData
                                    )
                                }

                                let fullData: Data?
                                let thumbData: Data?
                                do {
                                    // For very large imports, cap artwork at 800x800 to save memory
                                    let maxDim: CGFloat = importedSongIDs.count > 250 ? 800 : 1200
                                    (fullData, thumbData) = await SongMetadata.extractEmbeddedArtworkWithThumbnail(
                                        from: currentSong.localURL,
                                        maxDimension: maxDim,
                                        thumbnailDimension: 120
                                    )
                                }
                                return (id: songID, artworkData: fullData, previewData: thumbData)
                            }
                        }

                        for await result in group {
                            await MainActor.run {
                                if let songIndex = songs.firstIndex(where: { $0.id == result.id }) {
                                    if let artworkData = result.artworkData {
                                        songs[songIndex].artworkData = artworkData
                                    }
                                    if let previewData = result.previewData {
                                        songs[songIndex].artworkPreviewData = previewData
                                    }
                                }
                            }
                        }
                    }

                    await MainActor.run {
                        self.currentImportIndex = min(batchEnd, importedSongIDs.count)
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
        }
    }

    private func enrichSongWithSelectedMetadata(
        _ song: SongMetadata,
        metadataSource: String,
        autofetch: Bool
    ) async -> SongMetadata {
        guard autofetch else { return song }

        switch metadataSource {
        case "apple":
            return await SongMetadata.enrichWithAppleMusicMetadata(song)

        case "itunes":
            return await SongMetadata.enrichWithiTunesMetadata(song)

        case "deezer":
            return await SongMetadata.enrichWithDeezerMetadata(song)

        case "youtube":
            return await SongMetadata.enrichWithYouTubeMetadata(song)

        case "all":
            return await enrichSongUsingAllProviders(song)

        case "local":
            if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
                return await SongMetadata.matchAppleMusicMetadata(song)
            }
            return song

        default:
            return song
        }
    }

    private func enrichSongUsingAllProviders(_ original: SongMetadata) async -> SongMetadata {
        var merged = original

        let providers: [(String, (SongMetadata) async -> SongMetadata)] = [
            ("apple", { await SongMetadata.enrichWithAppleMusicMetadata($0) }),
            ("itunes", { await SongMetadata.enrichWithiTunesMetadata($0) }),
            ("deezer", { await SongMetadata.enrichWithDeezerMetadata($0) }),
            ("youtube", { await SongMetadata.enrichWithYouTubeMetadata($0) })
        ]

        for (name, provider) in providers {
            let candidate = await provider(merged)
            merged = mergeSongMetadata(base: merged, candidate: candidate)
            Logger.shared.log("[MusicView] Applied metadata provider: \(name)")
        }

        if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
            let appleRich = await SongMetadata.matchAppleMusicMetadata(merged)
            merged = mergeSongMetadata(base: merged, candidate: appleRich)
        }

        return merged
    }

    private func mergeSongMetadata(base: SongMetadata, candidate: SongMetadata) -> SongMetadata {
        var result = base

        if shouldReplaceTitle(base.title), !isMeaningfulEmpty(candidate.title) {
            result.title = candidate.title
        }

        if shouldReplaceArtist(base.artist), !isMeaningfulEmpty(candidate.artist) {
            result.artist = candidate.artist
        }

        if shouldReplaceAlbum(base.album), !isMeaningfulEmpty(candidate.album) {
            result.album = candidate.album
        }

        if result.albumArtist == nil || isMeaningfulEmpty(result.albumArtist ?? "") {
            if let albumArtist = candidate.albumArtist, !isMeaningfulEmpty(albumArtist) {
                result.albumArtist = albumArtist
            }
        }

        if shouldReplaceGenre(base.genre), !isMeaningfulEmpty(candidate.genre) {
            result.genre = candidate.genre
        }

        if result.year <= 0 || result.year == Calendar.current.component(.year, from: Date()) {
            if candidate.year > 0 {
                result.year = candidate.year
            }
        }

        if result.artworkData == nil, let artworkData = candidate.artworkData {
            result.artworkData = artworkData
        }

        if result.artworkPreviewData == nil, let artworkPreviewData = candidate.artworkPreviewData {
            result.artworkPreviewData = artworkPreviewData
        }

        if result.trackNumber == nil, let trackNumber = candidate.trackNumber {
            result.trackNumber = trackNumber
        }

        if result.trackCount == nil, let trackCount = candidate.trackCount {
            result.trackCount = trackCount
        }

        if result.discNumber == nil, let discNumber = candidate.discNumber {
            result.discNumber = discNumber
        }

        if result.discCount == nil, let discCount = candidate.discCount {
            result.discCount = discCount
        }

        if result.lyrics == nil || result.lyrics?.isEmpty == true {
            if let lyrics = candidate.lyrics, !lyrics.isEmpty {
                result.lyrics = lyrics
            }
        }

        return result
    }

    private func sanitizeImportedSong(_ song: SongMetadata) -> SongMetadata {
        var cleaned = song

        let rawFilename = song.localURL.deletingPathExtension().lastPathComponent
        let normalizedFilename = normalizedImportedFilename(rawFilename)
        let parsed = parseArtistAndTitle(from: normalizedFilename)

        let cleanedTitle = stripLeadingImportGarbage(song.title)
        let cleanedArtist = stripLeadingImportGarbage(song.artist)
        let cleanedAlbum = stripLeadingImportGarbage(song.album)

        if shouldReplaceTitle(cleanedTitle) || cleanedTitle == normalizedFilename {
            cleaned.title = parsed.title ?? normalizedFilename
        } else {
            cleaned.title = cleanedTitle
        }

        if shouldReplaceArtist(cleanedArtist) {
            cleaned.artist = parsed.artist ?? "Unknown Artist"
        } else {
            cleaned.artist = cleanedArtist
        }

        cleaned.album = shouldReplaceAlbum(cleanedAlbum) ? "Unknown Album" : cleanedAlbum
        cleaned.genre = shouldReplaceGenre(song.genre) ? "Music" : stripLeadingImportGarbage(song.genre)

        if let albumArtist = song.albumArtist {
            let cleanedAlbumArtist = stripLeadingImportGarbage(albumArtist)
            cleaned.albumArtist = shouldReplaceArtist(cleanedAlbumArtist) ? nil : cleanedAlbumArtist
        }

        if cleaned.trackNumber == nil, let parsedTrack = parsed.trackNumber {
            cleaned.trackNumber = parsedTrack
        }

        return cleaned
    }

    private func normalizedImportedFilename(_ value: String) -> String {
        var cleaned = value

        cleaned = cleaned.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^\d{5,}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s*-\s*"#,
            with: " - ",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripLeadingImportGarbage(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"^\d{5,}\s+"#,
            with: "",
            options: .regularExpression
        )

        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseArtistAndTitle(from filename: String) -> (artist: String?, title: String?, trackNumber: Int?) {
        let parts = filename
            .components(separatedBy: " - ")
            .map { stripLeadingImportGarbage($0) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return (nil, nil, nil)
        }

        if parts.count >= 3, let trackNumber = Int(parts[0]), parts[0].count <= 3 {
            let artist = stripLeadingImportGarbage(parts[1])
            let title = stripLeadingImportGarbage(parts[2...].joined(separator: " - "))
            return (
                artist.isEmpty ? nil : artist,
                title.isEmpty ? nil : title,
                trackNumber
            )
        }

        if parts.count == 2 {
            let p1 = stripLeadingImportGarbage(parts[0])
            let p2 = stripLeadingImportGarbage(parts[1])

            if let trackNumber = Int(p1), p1.count <= 3 {
                return (nil, p2.isEmpty ? nil : p2, trackNumber)
            }

            let p1Lower = p1.lowercased()
            let p2Lower = p2.lowercased()

            let p1LooksLikeTitle =
                p1Lower.contains("official") ||
                p1Lower.contains("audio") ||
                p1Lower.contains("video") ||
                p1Lower.contains("lyrics")

            let p2LooksLikeTitle =
                p2Lower.contains("official") ||
                p2Lower.contains("audio") ||
                p2Lower.contains("video") ||
                p2Lower.contains("lyrics")

            let p1LooksLikeArtist =
                p1Lower.contains("feat") || p1Lower.contains("ft.") || p1.contains(",")

            let p2LooksLikeArtist =
                p2Lower.contains("feat") || p2Lower.contains("ft.") || p2.contains(",")

            if p1LooksLikeTitle && !p2LooksLikeTitle {
                return (p2.isEmpty ? nil : p2, p1.isEmpty ? nil : p1, nil)
            }

            if p2LooksLikeArtist && !p1LooksLikeArtist {
                return (p2.isEmpty ? nil : p2, p1.isEmpty ? nil : p1, nil)
            }

            return (p1.isEmpty ? nil : p1, p2.isEmpty ? nil : p2, nil)
        }

        return (nil, filename.isEmpty ? nil : filename, nil)
    }

    private func shouldReplaceTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let lowered = trimmed.lowercased()
        if lowered == "unknown title" { return true }

        let looksLikeStagedFilename = trimmed.range(
            of: #"^[0-9A-Fa-f-]{36}[_\-\s]+"#,
            options: .regularExpression
        ) != nil

        let looksLikeNumericGarbage = trimmed.range(
            of: #"^\d{5,}\s+\S+"#,
            options: .regularExpression
        ) != nil

        return looksLikeStagedFilename || looksLikeNumericGarbage
    }

    private func shouldReplaceArtist(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let lowered = trimmed.lowercased()
        if lowered == "unknown artist" { return true }

        let looksLikeStagedFilename = trimmed.range(
            of: #"^[0-9A-Fa-f-]{36}[_\-\s]+"#,
            options: .regularExpression
        ) != nil

        let looksLikeNumericGarbage = trimmed.range(
            of: #"^\d{5,}\s+\S+"#,
            options: .regularExpression
        ) != nil

        return looksLikeStagedFilename || looksLikeNumericGarbage
    }

    private func shouldReplaceAlbum(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return trimmed.isEmpty || lowered == "unknown album"
    }

    private func shouldReplaceGenre(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return trimmed.isEmpty || lowered == "unknown genre" || lowered == "music"
    }

    private func isMeaningfulEmpty(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func injectSongs() {
        guard !songs.isEmpty else { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        
        manager.startHeartbeat { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.startInjectionProcess()
            }
        }
    }
    
    private func startInjectionProcess() {
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
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
                    
                    while lastProcessedIndex < index && !self.songs.isEmpty {
                        _ = self.songs.removeFirst()
                        lastProcessedIndex += 1
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
                        self.showToast(title: "Injection Failed", icon: "xmark.circle.fill")
                    }
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
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )
        let finalName = cleanedName.replacingOccurrences(
            of: #"^\d{5,}[_\-\s]+"#,
            with: "",
            options: .regularExpression
        )
        let ext = song.localURL.pathExtension
        return ext.isEmpty ? finalName : "\(finalName).\(ext)"
    }

    private func detectDuplicates(incoming: [SongMetadata], existing: [SongMetadata]) -> [DuplicateCandidate] {
        var seenBySignature: [String: SongMetadata] = [:]
        existing.forEach { seenBySignature[duplicateSignature(for: $0)] = $0 }
        var found: [DuplicateCandidate] = []

        for song in incoming {
            let sig = duplicateSignature(for: song)
            if let matched = seenBySignature[sig] {
                let reason = existing.contains(where: { $0.id == matched.id })
                    ? "Matches a song already in queue"
                    : "Matches another selected import"
                found.append(DuplicateCandidate(incoming: song, matched: matched, reason: reason))
            } else {
                seenBySignature[sig] = song
            }
        }
        return found
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
        
        manager.startHeartbeat { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                }
                return
            }
             
            DispatchQueue.main.async {
                self.startPlaylistInjection(name: name, pid: pid)
            }
        }
    }

    private func startPlaylistInjection(name: String?, pid: Int64?) {
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
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
                    
                    while lastProcessedIndex < index && !self.songs.isEmpty {
                        _ = self.songs.removeFirst()
                        lastProcessedIndex += 1
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
                        self.showToast(title: "Playlist Failed", icon: "xmark.circle.fill")
                    }
                }
            }
        }
    }
}
