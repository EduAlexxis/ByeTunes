import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var manager = DeviceManager.shared
    @State private var status = "Ready"
    @State private var songs: [SongMetadata] = []
    @State private var ringtones: [RingtoneMetadata] = []
    @State private var isInjecting = false
    @State private var selectedTab = 0
    @State private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @State private var showingLogViewer = false
    
    // MARK: - iOS 26+ Version Check (GlassUI Support)
    private var isIOS26OrLater: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 26
    }
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            if !showSplash {
                Group {
                    if hasCompletedOnboarding {
                        if isIOS26OrLater {
                            ModernTabView(
                                manager: manager,
                                songs: $songs,
                                ringtones: $ringtones,
                                isInjecting: $isInjecting,
                                status: $status,
                                selectedTab: $selectedTab,
                                showingLogViewer: $showingLogViewer
                            )
                        } else {
                            LegacyTabBarView(
                                manager: manager,
                                songs: $songs,
                                ringtones: $ringtones,
                                isInjecting: $isInjecting,
                                status: $status,
                                selectedTab: $selectedTab,
                                showingLogViewer: $showingLogViewer
                            )
                        }
                    } else {
                        OnboardingView(
                            manager: manager,
                            isComplete: $hasCompletedOnboarding
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowLogViewer"))) { _ in
            showingLogViewer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddSongToQueue"))) { notification in
            if let song = notification.object as? SongMetadata {
                withAnimation {
                    songs.append(song)
                    selectedTab = 0
                }
            }
        }
        .onAppear {
            cleanupLegacyImportedAudioFiles()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
            
            
            if FileManager.default.fileExists(atPath: manager.pairingFile.path) {
                hasCompletedOnboarding = true
                manager.startHeartbeat()
            }
            
            
            checkPendingInjections()
        }
        .onOpenURL { url in
            
            handleIncomingFile(url)
        }
    }

    private func cleanupLegacyImportedAudioFiles() {
        let docs = URL.documentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let audioExts: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "m4r"]
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard audioExts.contains(ext) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    
    private func handleIncomingFile(_ url: URL) {
        Logger.shared.log("[ContentView] Received file via Open With: \(url.lastPathComponent)")
        
        
        guard url.startAccessingSecurityScopedResource() else {
            Logger.shared.log("[ContentView] Failed to access security-scoped resource")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let ext = url.pathExtension.lowercased()
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming_imports", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
        
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            
            if ext == "m4r" {
                
                let ringtone = RingtoneMetadata.fromURL(destURL)
                ringtones.append(ringtone)
                selectedTab = 1 
                Logger.shared.log("[ContentView] Added ringtone: \(ringtone.name)")
                
                
                autoInjectRingtones([ringtone])
            } else if ["mp3", "m4a", "wav", "flac", "aiff"].contains(ext) {
                
                Task {
                    if let song = try? await SongMetadata.fromURL(destURL) {
                        await MainActor.run {
                            songs.append(song)
                            selectedTab = 0 
                            Logger.shared.log("[ContentView] Added song: \(song.title)")
                            
                            
                            autoInjectSongs([song])
                        }
                    }
                }
            }
        } catch {
            Logger.shared.log("[ContentView] Error copying file: \(error)")
        }
    }
    
    
    private func autoInjectSongs(_ songsToInject: [SongMetadata]) {
        guard manager.heartbeatReady else {
            status = "Device not connected"
            Logger.shared.log("[ContentView] Auto-inject skipped: device not connected")
            return
        }
        
        isInjecting = true
        status = "Auto-injecting..."
        
        manager.injectSongs(songs: songsToInject, progress: { progressText in
            DispatchQueue.main.async {
                self.status = progressText
            }
        }, completion: { success in
            DispatchQueue.main.async {
                self.isInjecting = false
                if success {
                    self.status = "Injected successfully!"
                    
                    for song in songsToInject {
                        self.songs.removeAll { $0.id == song.id }
                        if !SongMetadata.shouldPreserveLocalFile(song.localURL) {
                            try? FileManager.default.removeItem(at: song.localURL)
                        }
                    }
                } else {
                    self.status = "Injection failed"
                }
            }
        })
    }
    
    private func autoInjectRingtones(_ ringtonesToInject: [RingtoneMetadata]) {
        guard manager.heartbeatReady else {
            status = "Device not connected"
            Logger.shared.log("[ContentView] Auto-inject skipped: device not connected")
            return
        }
        
        isInjecting = true
        status = "Auto-injecting ringtone..."
        
        
        let songs = ringtonesToInject.map { ringtone in
            SongMetadata(
                localURL: ringtone.url,
                title: ringtone.name,
                artist: "Ringtone",
                album: "Ringtones",
                genre: "Ringtone",
                year: 2024,
                durationMs: 30000,
                fileSize: ringtone.fileSize,
                remoteFilename: ringtone.remoteFilename,
                artworkData: nil
            )
        }
        
        manager.injectRingtones(ringtones: songs, progress: { progressText in
            DispatchQueue.main.async {
                self.status = progressText
            }
        }, completion: { success in
            DispatchQueue.main.async {
                self.isInjecting = false
                if success {
                    self.status = "Ringtone injected!"
                    
                    for ringtone in ringtonesToInject {
                        self.ringtones.removeAll { $0.id == ringtone.id }
                        try? FileManager.default.removeItem(at: ringtone.url)
                    }
                } else {
                    self.status = "Injection failed"
                }
            }
        })
    }
    
    
    private func checkPendingInjections() {
        guard let defaults = UserDefaults(suiteName: DeviceManager.appGroupID) else { return }
        guard let pendingFiles = defaults.stringArray(forKey: "pendingInjections"), !pendingFiles.isEmpty else { return }
        guard let containerURL = DeviceManager.sharedContainerURL else { return }
        
        
        defaults.removeObject(forKey: "pendingInjections")
        defaults.synchronize()
        
        
        Task {
            for filename in pendingFiles {
                let fileURL = containerURL.appendingPathComponent(filename)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                
                let ext = fileURL.pathExtension.lowercased()
                
                if ext == "m4r" {
                    
                    let ringtone = RingtoneMetadata.fromURL(fileURL)
                    await MainActor.run {
                        ringtones.append(ringtone)
                        selectedTab = 1 
                    }
                } else if ["mp3", "m4a", "wav", "flac", "aiff"].contains(ext) {
                    
                    if let song = try? await SongMetadata.fromURL(fileURL) {
                        await MainActor.run {
                            songs.append(song)
                            selectedTab = 0 
                        }
                    }
                }
            }
        }
    }
}



struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let showRingtonesTab: Bool
    private var downloadTabIndex: Int { showRingtonesTab ? 2 : 1 }
    private var settingsTabIndex: Int { showRingtonesTab ? 3 : 2 }
    
    var body: some View {
        HStack(spacing: 0) {
            
            TabBarButton(
                icon: "music.note",
                title: "Music",
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            

            
            
            if showRingtonesTab {
                TabBarButton(
                    icon: "bell.badge.fill",
                    title: "Ringtones",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }

            TabBarButton(
                icon: "arrow.down.circle",
                title: "Download",
                isSelected: selectedTab == downloadTabIndex
            ) {
                selectedTab = downloadTabIndex
            }
            TabBarButton(
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: selectedTab == settingsTabIndex
            ) {
                selectedTab = settingsTabIndex
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
        )
        .overlay(
            Capsule()
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .blue : .gray)
            .frame(width: 80, height: 50)
            .background(
                isSelected ?
                    Capsule().fill(Color.blue.opacity(0.1)) :
                    Capsule().fill(Color.clear)
            )
        }
    }
}



struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var allowsMultiple: Bool = false
    var asCopy: Bool = true
    let completion: ([URL]?) -> Void
    
    init(types: [UTType], allowsMultiple: Bool = false, asCopy: Bool = true, completion: @escaping ([URL]?) -> Void) {
        self.types = types
        self.allowsMultiple = allowsMultiple
        self.asCopy = asCopy
        self.completion = completion
    }
    
    init(types: [UTType], asCopy: Bool = true, completion: @escaping (URL?) -> Void) {
        self.types = types
        self.allowsMultiple = false
        self.asCopy = asCopy
        self.completion = { urls in
            completion(urls?.first)
        }
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultiple
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]?) -> Void
        
        init(completion: @escaping ([URL]?) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}

#Preview {
    ContentView()
}
