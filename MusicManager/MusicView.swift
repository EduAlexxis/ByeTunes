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
    
    
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    
    
    @State private var currentInjectIndex = 0
    @State private var totalInjectCount = 0
    
    
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
                                        
                                        let source = UserDefaults.standard.string(forKey: "metadataSource")
                                        let isAPISource = source == "itunes" || source == "deezer"
                                        let isCustomSource = source == "custom"
                                         
                                        let canEdit = isAPISource || isCustomSource
                                        
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
                if UserDefaults.standard.string(forKey: "metadataSource") == "custom" {
                    ManualMetadataEditor(song: $songs[index], isPresented: Binding(
                        get: { selectedSongForMatch != nil },
                        set: { if !$0 { selectedSongForMatch = nil } }
                    ))
                } else {
                    iTunesSearchSheet(song: $songs[index], isPresented: Binding(
                        get: { selectedSongForMatch != nil },
                        set: { if !$0 { selectedSongForMatch = nil } }
                    ))
                }
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
        let useiTunes = (metadataSource == "itunes")
        let autofetch = UserDefaults.standard.bool(forKey: "autofetchMetadata") 
        
        
        Task {
            var importedSongs: [SongMetadata] = []
            
            for url in urls {
                // Since we are using asCopy: true, we don't need security scoped access
                
                let destURL = URL.documentsDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: url, to: destURL)
                
                if var song = try? await SongMetadata.fromURL(destURL) {
                    
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
        
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.injectProgress < 0.9 {
                self.injectProgress += 0.02
            }
        }
        
        manager.injectSongs(songs: songs, progress: { progressText in
            DispatchQueue.main.async {
                
                if let range = progressText.range(of: #"(\d+)/\d+"#, options: .regularExpression),
                   let index = Int(progressText[range].split(separator: "/").first ?? "") {
                    self.currentInjectIndex = index
                    
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
                        
                        // Cleanup files after successful injection
                        for song in self.songs {
                            try? FileManager.default.removeItem(at: song.localURL)
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

    
    func injectAsPlaylist(name: String? = nil, pid: Int64? = nil) {
        guard !songs.isEmpty else { return }
        if name == nil && pid == nil { return }
        
        isInjecting = true
        injectProgress = 0

        
        
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
                        
                        // Cleanup files after successful playlist injection
                        for song in self.songs {
                            try? FileManager.default.removeItem(at: song.localURL)
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
