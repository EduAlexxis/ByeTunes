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
    
    // Toast State
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    // Injection count state
    @State private var currentInjectIndex = 0
    @State private var totalInjectCount = 0
    
    // Manual Match State
    @State private var selectedSongForMatch: SongMetadata?

    
    static var supportedAudioTypes: [UTType] {
        var types: [UTType] = [.mp3, .wav, .aiff, .mpeg4Audio, .audio]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        return types
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            // ScrollView removed to disable page scrolling
            VStack(alignment: .leading, spacing: 10) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Music")
                            .font(.system(size: 34, weight: .bold))
                        
                        // Connection indicator
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
                
                // Quick Actions
                VStack(spacing: 12) {
                    // Add songs button - primary action
                    Button {
                        showingMusicPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .font(.body.weight(.medium))
                            Text("Add Songs")
                                .font(.body.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Inject button with progress fill
                    Button {
                        injectSongs()
                    } label: {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color(.systemGray6))
                                
                                // Fill progress
                                if isInjecting {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.black.opacity(0.15))
                                        .frame(width: geo.size.width * injectProgress)
                                        .animation(.easeInOut(duration: 0.3), value: injectProgress)
                                }
                                
                                // Content
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
                    
                    // Inject as Playlist
                    // Inject as Playlist
                    Button {
                        isFetchingPlaylists = true
                        // status = "Fetching playlists..."
                        manager.fetchPlaylists { playlists in
                            self.existingPlaylists = playlists.map { PlaylistModel(name: $0.name, pid: $0.pid) }
                            self.isFetchingPlaylists = false
                            self.showingPlaylistSheet = true
                            // self.status = "Select a playlist"
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
                
                // Persistent Warning when queue is not empty - Placed here to be always visible
                if !songs.isEmpty && !isInjecting {
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

                // Songs List
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Queue")
                            .font(.title3.weight(.semibold))
                        
                        Spacer()
                        
                        if !songs.isEmpty {
                            Text("\(songs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if songs.isEmpty {
                        // Empty state
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
                        // Song list
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                    VStack(spacing: 0) {
                                        // Calculate edit state
                                        let source = UserDefaults.standard.string(forKey: "metadataSource")
                                        let isAPISource = source == "itunes" || source == "deezer"
                                        // User wants to edit even if autofetch is on, so we just check if we have a valid source
                                        let canEdit = isAPISource
                                        
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
                        .frame(maxHeight: .infinity) // Fill remaining space compacted layout provides
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }
                
                Spacer() // Push content to top
            }
            .padding(.bottom, 40) // Padding inside content, not frame
            .padding(.horizontal, 20)
            // Removed frame-constraining padding from here

        
        // Toast Overlay
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
            .padding(.bottom, 100) // Position above nav bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(100)
        }
    } // Close ZStack here
    // Brace removed to continue modifier chain

        .sheet(isPresented: $showingMusicPicker) {
            DocumentPicker(types: Self.supportedAudioTypes, allowsMultiple: true) { urls in
                handleMusicImport(urls: urls)
            }
        }
        .sheet(item: $selectedSongForMatch) { item in
            if let index = songs.firstIndex(where: { $0.id == item.id }) {
                iTunesSearchSheet(song: $songs[index], isPresented: Binding(
                    get: { selectedSongForMatch != nil },
                    set: { if !$0 { selectedSongForMatch = nil } }
                ))
            } else {
                VStack {
                    Text("Error: Song not found")
                    Button("Close") { selectedSongForMatch = nil }
                }
            }
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
            // Custom Header
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
                    // Create New Button
                    Button {
                        showingPlaylistSheet = false
                        // Small delay to allow sheet to dismiss before alert shows
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
                    
                    // Existing List
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
        let useiTunes = (metadataSource == "itunes")
        let autofetch = UserDefaults.standard.bool(forKey: "autofetchMetadata") // Default is false usually if not set, but we handle logic
        // If not set, bool returns false. So we need to consider if "default true" was needed. 
        // User didn't specify default, but implied "if active". 
        // Let's assume default is false unless set. 
        // Wait, user said "if turn off when importing...". 
        // I should set default to true in SettingsView maybe?
        
        Task {
            var importedSongs: [SongMetadata] = []
            
            for url in urls {
                let needsSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if needsSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let destURL = URL.documentsDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: url, to: destURL)
                
                if var song = try? await SongMetadata.fromURL(destURL) {
                    // Enrich if option is enabled AND autofetch is ON
                    if useiTunes && autofetch {
                        song = await SongMetadata.enrichWithiTunesMetadata(song)
                    }
                    importedSongs.append(song)
                }
            }
            
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    songs.append(contentsOf: importedSongs)
                }
            }
        }
    }
    
    func injectSongs() {
        guard !songs.isEmpty else { return }
        
        isInjecting = true
        injectProgress = 0
        totalInjectCount = songs.count
        currentInjectIndex = 0
        
        // Refresh connection first
        manager.startHeartbeat { success in
            guard success else {
                DispatchQueue.main.async {
                    self.showToast(title: "Connection Failed", icon: "exclamationmark.triangle.fill")
                    self.isInjecting = false
                }
                return
            }
            
            // Proceed with injection after connection is fresh
            DispatchQueue.main.async {
                self.startInjectionProcess()
            }
        }
    }
    
    private func startInjectionProcess() {
        // Simulate progress animation
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        manager.injectSongs(songs: songs, progress: { progressText in
            DispatchQueue.main.async {
                // Parse progress text like "Injecting song 3/10" to extract current index
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    // Update progress bar based on actual count
                    self.injectProgress = CGFloat(index) / CGFloat(self.totalInjectCount) * 0.9
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
                        // success
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
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Auto hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                self.showToast = false
            }
        }
    }

    
    func injectAsPlaylist(name: String? = nil, pid: Int64? = nil) {
        guard !songs.isEmpty else { return }
        if name == nil && pid == nil { return }
        
        isInjecting = true
        injectProgress = 0
        let displayParams = name ?? "Existing Playlist"
        
        // Refresh connection first
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
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        manager.injectSongsAsPlaylist(songs: songs, playlistName: name, targetPlaylistPid: pid, progress: { progressText in
            DispatchQueue.main.async {
                // self.status = progressText
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
                        let finalName = name ?? "Selected"
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
