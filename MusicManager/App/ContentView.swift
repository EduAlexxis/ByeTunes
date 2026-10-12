import SwiftUI
import UniformTypeIdentifiers

struct AppUpdateInfo: Identifiable, Equatable {
    let id = UUID()
    let version: String
    let releaseURL: URL
    let name: String
}

enum AppUpdateChecker {
    static let currentVersion = "2.6"

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
        }
    }

    static func checkForUpdate() async throws -> AppUpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/EduAlexxis/ByeTunes/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("ByeTunes/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = normalizedVersion(release.tagName)
        guard isVersion(latestVersion, newerThan: currentVersion),
              let releaseURL = URL(string: release.htmlURL) else {
            return nil
        }

        return AppUpdateInfo(
            version: latestVersion,
            releaseURL: releaseURL,
            name: release.name ?? release.tagName
        )
    }

    static func normalizedVersion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }

    private static func versionParts(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var manager = DeviceManager.shared
    @State private var status = "Ready"
    @State private var songs: [SongMetadata] = []
    @State private var ringtones: [RingtoneMetadata] = []
    @State private var isInjecting = false
    @State private var selectedTab = 0
    @State private var hasCompletedOnboarding = false
    @AppStorage("tutorialComplete") private var tutorialComplete = false
    @State private var showSplash = true
    @State private var showingLogViewer = false
    @State private var showingRPPairingUpgradePicker = false
    @State private var rpPairingUpgradeError: String?
    @State private var availableUpdate: AppUpdateInfo?
    @State private var dismissedUpdateVersion: String?

    // MARK: - iOS 26+ Version Check (GlassUI Support)
    private var isIOS26OrLater: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion >= 26
    }

    private var downloadTabIndex: Int {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let showRingtonesTab = (16...18).contains(major)
        return showRingtonesTab ? 2 : 1
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

            if !showSplash && hasCompletedOnboarding && !tutorialComplete {
                TutorialOverlayView(
                    isComplete: $tutorialComplete,
                    songs: $songs,
                    selectedTab: $selectedTab,
                    downloadTabIndex: downloadTabIndex
                )
                .zIndex(1)
            }

            if !showSplash && manager.shouldPromptForRPPairingUpgrade {
                RPPairingUpgradePrompt(
                    errorMessage: rpPairingUpgradeError,
                    importAction: {
                        showingRPPairingUpgradePicker = true
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2)
            }

            if !showSplash,
               let availableUpdate,
               dismissedUpdateVersion != availableUpdate.version {
                AppUpdatePrompt(
                    update: availableUpdate,
                    dismissAction: {
                        dismissedUpdateVersion = availableUpdate.version
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(3)
            }
        }
        .sheet(isPresented: $showingRPPairingUpgradePicker) {
            DocumentPicker(types: [.data, .xml, .propertyList, .item]) { url in
                handleRPPairingUpgradeImport(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowLogViewer"))) { _ in
            showingLogViewer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetOnboardingFlow"))) { _ in
            hasCompletedOnboarding = false
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
            manager.refreshExpectedPairingFileState()
            hasCompletedOnboarding = manager.hasValidExpectedPairingFile
            if manager.hasValidExpectedPairingFile {
                manager.startHeartbeat()
            }
            
            restorePersistedSongQueueIfNeeded()
            checkPendingInjections()
            checkForAppUpdate()
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "byetunes" {
                let host = (url.host ?? "").lowercased()
                if host == "download" {
                    selectedTab = downloadTabIndex
                    return
                }
            }

            let host = (url.host ?? "").lowercased()
            if host.contains("spotify.com") || host.contains("music.apple.com") {
                if let normalized = LinkNormalizer.normalize(url) {
                    self.selectedTab = downloadTabIndex
                    NotificationCenter.default.post(name: NSNotification.Name("IncomingMusicLink"), object: normalized.normalizedURL.absoluteString)
                }
                return
            }

            if host.contains("deezer.com") || host.contains("deezer.page.link") {
                self.selectedTab = downloadTabIndex
                NotificationCenter.default.post(name: NSNotification.Name("IncomingMusicLink"), object: url.absoluteString)
                return
            }

            handleIncomingFile(url)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                attemptAutoReconnectIfNeeded()
            } else if newPhase == .background {
                manager.stopHeartbeat()
            }
        }
        .onChange(of: songsPersistenceSignature) { _ in
            persistSongQueue(songs)
        }
    }

    private var songsPersistenceSignature: [String] {
        songs.map { song in
            [
                song.localURL.path,
                song.title,
                song.artist,
                song.album,
                song.remoteFilename,
                String(song.fileSize),
                String(song.durationMs),
                String(song.trackNumber ?? 0),
                String(song.discNumber ?? 0)
            ].joined(separator: "|")
        }
    }

    private func checkForAppUpdate() {
        Task {
            do {
                let update = try await AppUpdateChecker.checkForUpdate()
                await MainActor.run {
                    availableUpdate = update
                }
            } catch {
                Logger.shared.log("[Update] Version check failed: \(error.localizedDescription)")
            }
        }
    }

    private func attemptAutoReconnectIfNeeded() {
        guard scenePhase == .active, !showSplash, hasCompletedOnboarding else { return }

        manager.refreshExpectedPairingFileState()
        guard manager.hasValidExpectedPairingFile,
              !manager.heartbeatReady,
              manager.connectionStatus != "Connecting..." else { return }

        manager.startHeartbeat()
    }

    private func handleRPPairingUpgradeImport(url: URL?) {
        guard let url else { return }

        do {
            try manager.importPairingFile(from: url)
            rpPairingUpgradeError = nil
            hasCompletedOnboarding = true
            manager.startHeartbeat()
        } catch {
            rpPairingUpgradeError = error.localizedDescription
        }
    }

    private func cleanupLegacyImportedAudioFiles() {
        let docs = URL.documentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let audioExts: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "opus", "m4r"]
        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard audioExts.contains(ext) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func restorePersistedSongQueueIfNeeded() {
        guard songs.isEmpty else { return }
        let restored = QueuePersistenceStore.loadMusicQueue()
        guard !restored.isEmpty else { return }
        songs = restored
        Logger.shared.log("[ContentView] Restored \(restored.count) queued song(s) from last session")
    }

    private func persistSongQueue(_ updatedSongs: [SongMetadata]) {
        if updatedSongs.isEmpty {
            QueuePersistenceStore.clearMusicQueue()
        } else {
            QueuePersistenceStore.saveMusicQueue(updatedSongs)
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
                Task {
                    let ringtone = await RingtoneMetadata.fromURL(destURL)
                    await MainActor.run {
                        ringtones.append(ringtone)
                        selectedTab = 1
                        Logger.shared.log("[ContentView] Added ringtone: \(ringtone.name)")
                        autoInjectRingtones([ringtone])
                    }
                }
            } else if ["mp3", "m4a", "wav", "flac", "aiff", "opus"].contains(ext) {
                
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
                    
                    let ringtone = await RingtoneMetadata.fromURL(fileURL)
                    await MainActor.run {
                        ringtones.append(ringtone)
                        selectedTab = 1 
                    }
                } else if ["mp3", "m4a", "wav", "flac", "aiff", "opus"].contains(ext) {
                    
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


private struct RPPairingUpgradePrompt: View {
    let errorMessage: String?
    let importAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 8) {
                    Text("RP Pairing File Required")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("iOS 26.4 or newer needs an RP Pairing File before ByeTunes can connect. Import the new file to continue.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: importAction) {
                    HStack {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Import RP Pairing File")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("This message will stay here until the RP Pairing File is imported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
    }
}

private struct AppUpdatePrompt: View {
    let update: AppUpdateInfo
    let dismissAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)

                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 8) {
                    Text("Update Available")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("ByeTunes \(update.version) is available. Download the latest release from GitHub when you are ready.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link(destination: update.releaseURL) {
                    HStack {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Open Releases")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: dismissAction) {
                    Text("Later")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
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
