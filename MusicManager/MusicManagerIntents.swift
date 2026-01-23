import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - Inject Music

@available(iOS 16.0, *)
struct InjectMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Inject Music"
    static var description = IntentDescription("Injects audio files to your device's music library")
    
    // Need to open app so we can talk to the device
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Audio Files", description: "Select audio files to inject", supportedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, UTType("com.apple.m4a-audio")!, UTType("org.xiph.flac")!])
    var audioFiles: [IntentFile]
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = DeviceManager.shared
        
        // Try to connect if we're not already
        if !manager.heartbeatReady {
            manager.startHeartbeat()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        guard manager.heartbeatReady else {
            return .result(dialog: "Device not connected. Please ensure your device is connected and try again.")
        }
        
        var songs: [SongMetadata] = []
        
        for file in audioFiles {
            let data = file.data
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            
            do {
                try data.write(to: tempURL)
                if let song = try? await SongMetadata.fromURL(tempURL) {
                    songs.append(song)
                }
            } catch {
                print("[Shortcuts] Couldn't save file: \(error)")
            }
        }
        
        guard !songs.isEmpty else {
            return .result(dialog: "No valid audio files found.")
        }
        
        let count = songs.count
        
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            manager.injectSongs(songs: songs, progress: { _ in }, completion: { result in
                continuation.resume(returning: result)
            })
        }
        
        if success {
            return .result(dialog: "✓ Injected \(count) song(s)")
        } else {
            return .result(dialog: "✗ Injection failed")
        }
    }
}

// MARK: - Inject Ringtone

@available(iOS 16.0, *)
struct InjectRingtoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Inject Ringtone"
    static var description = IntentDescription("Injects an audio file as a ringtone to your device")
    
    // Need to open app so we can talk to the device
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Ringtone File", description: "Select a ringtone file to inject", supportedContentTypes: [.audio, .mp3, UTType("com.apple.m4a-audio")!])
    var ringtoneFile: IntentFile
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = DeviceManager.shared
        
        // Try to connect if we're not already
        if !manager.heartbeatReady {
            manager.startHeartbeat()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        guard manager.heartbeatReady else {
            return .result(dialog: "Device not connected. Please ensure your device is connected and try again.")
        }
        
        let data = ringtoneFile.data
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(ringtoneFile.filename)
        
        do {
            try data.write(to: tempURL)
        } catch {
            return .result(dialog: "Error saving ringtone file.")
        }
        
        let ringtone = RingtoneMetadata.fromURL(tempURL)
        
        // Pack it as a SongMetadata since that's what the injector expects
        let song = SongMetadata(
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
        
        let name = ringtone.name
        
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            manager.injectRingtones(ringtones: [song], progress: { _ in }, completion: { result in
                continuation.resume(returning: result)
            })
        }
        
        if success {
            return .result(dialog: "✓ Injected '\(name)' as ringtone")
        } else {
            return .result(dialog: "✗ Ringtone injection failed")
        }
    }
}

// MARK: - Shortcuts Provider

@available(iOS 16.0, *)
struct MusicManagerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: InjectMusicIntent(),
            phrases: [
                "Inject music with \(.applicationName)",
                "Add songs to \(.applicationName)",
                "Import music to \(.applicationName)"
            ],
            shortTitle: "Inject Music",
            systemImageName: "music.note"
        )
        
        AppShortcut(
            intent: InjectRingtoneIntent(),
            phrases: [
                "Inject ringtone with \(.applicationName)",
                "Add ringtone to \(.applicationName)",
                "Import ringtone to \(.applicationName)"
            ],
            shortTitle: "Inject Ringtone",
            systemImageName: "bell.fill"
        )
    }
}
