import SwiftUI
import UniformTypeIdentifiers

struct MusicView: View {

    // MARK: - State
    @ObservedObject var manager: DeviceManager
    @Binding var songs: [SongMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    
    struct PlaylistModel: Identifiable, Hashable {
        let name: String
        let pid: Int64
        var id: Int64 { pid }
    }
    @State var showingMusicPicker = false
    @State var injectProgress: CGFloat = 0
    @State var showPlaylistAlert = false
    @State var playlistName = ""
    @State var showingPlaylistSheet = false
    @State var existingPlaylists: [PlaylistModel] = []
    @State var isFetchingPlaylists = false
    
    @State var isImporting = false
    @State var currentImportIndex = 0
    @State var totalImportCount = 0
    @State var importPhaseTitle = "Importing Songs"
    
    
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastIcon = ""
    
    
    @State var currentInjectIndex = 0
    @State var totalInjectCount = 0
    @State var isMinimalBatchInjectionMode = false
    @State var showingBatchMetadataEditor = false
    
    
    @State var selectedSongForMatch: SongMetadata?
    @State var pendingImportedSongs: [SongMetadata] = []
    @State var pendingAlreadyImportedCount = 0
    @State var pendingImportSkippedCount = 0
    @State var detectedDuplicates: [DuplicateCandidate] = []
    @State var duplicateImportSelection: [UUID: Bool] = [:]
    @State var showingDuplicateSheet = false

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

    var importStagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("music_import_staging", isDirectory: true)
    }

    var shouldHideQueueDuringLargeImport: Bool {
        isImporting && totalImportCount >= Self.largeBatchThreshold
    }

    var shouldHideQueueDuringLargeInjection: Bool {
        isInjecting && isMinimalBatchInjectionMode
    }

    var shouldUseCompactQueueForLargeBatch: Bool {
        songs.count >= Self.largeBatchThreshold
    }

    var shouldUseMinimalQueueUI: Bool {
        shouldHideQueueDuringLargeImport || shouldHideQueueDuringLargeInjection || shouldUseCompactQueueForLargeBatch
    }

    var shouldShowBatchMetadataEditorTrigger: Bool {
        !songs.isEmpty && songs.count >= Self.largeBatchThreshold && !isImporting
    }

    // MARK: - Constants
    static let largeBatchThreshold = 50
    
    // MARK: - Body
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
        .sheet(isPresented: $showingPlaylistSheet) {
            playlistSelectionSheet
        }
    }
    
}
