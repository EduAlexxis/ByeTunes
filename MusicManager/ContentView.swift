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
                // Main App
                ZStack(alignment: .bottom) {
                    // Background that extends to edges
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    Group {
                        if selectedTab == 0 {
                            MusicView(
                                manager: manager,
                                songs: $songs,
                                isInjecting: $isInjecting,
                                status: $status
                            )
                        } else if selectedTab == 1 {
                            RingtonesView(manager: manager, ringtones: $ringtones)
                        } else {
                            SettingsView(
                                manager: manager,
                                status: $status
                            )
                        }
                    }
                    .padding(.bottom, 80)
                    
                    FloatingTabBar(selectedTab: $selectedTab)
                        .padding(.bottom, 0)
                }
                .sheet(isPresented: $showingLogViewer) {
                    LogViewer()
                }
                .ignoresSafeArea(.keyboard)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 1.2))
                ))
            } else {
                // Onboarding
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
        .onAppear {
            // Splash Screen Timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
            
            // Check if pairing file already exists
            if FileManager.default.fileExists(atPath: manager.pairingFile.path) {
                hasCompletedOnboarding = true
                manager.startHeartbeat()
            }
            
            // Check for pending injections from Share Extension
            checkPendingInjections()
        }
        .onOpenURL { url in
            // File shared to our app
            handleIncomingFile(url)
        }
    }
    
    // MARK: - Shared Files
    private func handleIncomingFile(_ url: URL) {
        print("[ContentView] Received file via Open With: \(url.lastPathComponent)")
        
        // Need permission to read the file
        guard url.startAccessingSecurityScopedResource() else {
            print("[ContentView] Failed to access security-scoped resource")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let ext = url.pathExtension.lowercased()
        
        // Copy to our sandbox
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destURL = documentsURL.appendingPathComponent(url.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            
            if ext == "m4r" {
                // It's a ringtone
                let ringtone = RingtoneMetadata.fromURL(destURL)
                ringtones.append(ringtone)
                selectedTab = 1 // Switch to Ringtones tab
                print("[ContentView] Added ringtone: \(ringtone.name)")
                
                // Auto-inject ringtone
                autoInjectRingtones([ringtone])
            } else if ["mp3", "m4a", "wav", "flac", "aiff"].contains(ext) {
                // It's a song
                Task {
                    if let song = try? await SongMetadata.fromURL(destURL) {
                        await MainActor.run {
                            songs.append(song)
                            selectedTab = 0 // Switch to Music tab
                            print("[ContentView] Added song: \(song.title)")
                            
                            // Auto-inject song
                            autoInjectSongs([song])
                        }
                    }
                }
            }
        } catch {
            print("[ContentView] Error copying file: \(error)")
        }
    }
    
    // MARK: - Auto Inject
    private func autoInjectSongs(_ songsToInject: [SongMetadata]) {
        guard manager.heartbeatReady else {
            status = "Device not connected"
            print("[ContentView] Auto-inject skipped: device not connected")
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
                    // Done, clear them out
                    for song in songsToInject {
                        self.songs.removeAll { $0.id == song.id }
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
            print("[ContentView] Auto-inject skipped: device not connected")
            return
        }
        
        isInjecting = true
        status = "Auto-injecting ringtone..."
        
        // Injector expects SongMetadata so we wrap it
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
                    // Clear them out
                    for ringtone in ringtonesToInject {
                        self.ringtones.removeAll { $0.id == ringtone.id }
                    }
                } else {
                    self.status = "Injection failed"
                }
            }
        })
    }
    
    // MARK: - Share Extension Integration
    private func checkPendingInjections() {
        guard let defaults = UserDefaults(suiteName: DeviceManager.appGroupID) else { return }
        guard let pendingFiles = defaults.stringArray(forKey: "pendingInjections"), !pendingFiles.isEmpty else { return }
        guard let containerURL = DeviceManager.sharedContainerURL else { return }
        
        // Clear the pending list first
        defaults.removeObject(forKey: "pendingInjections")
        defaults.synchronize()
        
        // Load the files as SongMetadata or RingtoneMetadata
        Task {
            for filename in pendingFiles {
                let fileURL = containerURL.appendingPathComponent(filename)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                
                let ext = fileURL.pathExtension.lowercased()
                
                if ext == "m4r" {
                    // Handle as ringtone
                    let ringtone = RingtoneMetadata.fromURL(fileURL)
                    await MainActor.run {
                        ringtones.append(ringtone)
                        selectedTab = 1 // Switch to Ringtones tab
                    }
                } else if ["mp3", "m4a", "wav", "flac", "aiff"].contains(ext) {
                    // Handle as music
                    if let song = try? await SongMetadata.fromURL(fileURL) {
                        await MainActor.run {
                            songs.append(song)
                            selectedTab = 0 // Switch to Music tab
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Music Tab
            TabBarButton(
                icon: "music.note",
                title: "Music",
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            

            
            // Ringtones Tab
            TabBarButton(
                icon: "bell.badge.fill",
                title: "Ringtones",
                isSelected: selectedTab == 1
            ) {
                selectedTab = 1
            }
            
            // Settings Tab
            TabBarButton(
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: selectedTab == 2
            ) {
                selectedTab = 2
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
            .frame(width: 70, height: 50)
            .background(
                isSelected ?
                    Capsule().fill(Color.blue.opacity(0.1)) :
                    Capsule().fill(Color.clear)
            )
        }
    }
}

// MARK: - UIKit Document Picker Wrapper

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var allowsMultiple: Bool = false
    let completion: ([URL]?) -> Void
    
    init(types: [UTType], allowsMultiple: Bool = false, completion: @escaping ([URL]?) -> Void) {
        self.types = types
        self.allowsMultiple = allowsMultiple
        self.completion = completion
    }
    
    init(types: [UTType], completion: @escaping (URL?) -> Void) {
        self.types = types
        self.allowsMultiple = false
        self.completion = { urls in
            completion(urls?.first)
        }
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
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
