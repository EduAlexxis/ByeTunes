import Foundation
import UIKit
import Combine
import BackgroundTasks

extension Notification.Name {
    static let backgroundMetadataFetchCompleted = Notification.Name("BackgroundMetadataFetchCompleted")
}

private final class BackgroundTaskState {
    var id: UIBackgroundTaskIdentifier = .invalid
}

@MainActor
final class BackgroundMetadataFetchManager: ObservableObject {
    static let shared = BackgroundMetadataFetchManager()

    static let processingTaskIdentifier = "com.EduAlexxis.MusicManager.metadataRefresh"

    private static let readySongsKey = "backgroundMetadataFetchReadySongs.v1"

    @Published private(set) var isProcessing = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var drainTask: Task<Void, Never>?
    private var inFlightImportPaths: Set<String> = []

    private init() {}

    nonisolated static var isEnabled: Bool {
        if let stored = UserDefaults.standard.object(forKey: "backgroundMetadataFetchEnabled") as? Bool {
            return stored
        }
        return true
    }

    nonisolated func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handleBackgroundProcessingTask(task as! BGProcessingTask)
            }
        }
    }

    nonisolated func scheduleBackgroundProcessing() {
        guard Self.isEnabled else { return }
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.shared.log("[BGMetadata] Failed to schedule background processing task: \(error)")
        }
    }

    private func handleBackgroundProcessingTask(_ task: BGProcessingTask) {
        scheduleBackgroundProcessing()

        guard Self.isEnabled, !isProcessing else {
            task.setTaskCompleted(success: true)
            return
        }

        isProcessing = true
        let drain = Task { @MainActor in
            await drainQueue()
            isProcessing = false
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { [weak self] in
            drain.cancel()
            Task { @MainActor in self?.isProcessing = false }
        }
    }

    func processPendingDownloadsInBackground() {
        guard Self.isEnabled else { return }
        guard !isProcessing else { return }

        isProcessing = true
        beginBackgroundTaskIfNeeded()

        drainTask = Task { @MainActor in
            defer {
                endBackgroundTaskIfNeeded()
                isProcessing = false
                drainTask = nil
            }
            await drainQueue()
        }
    }

    func cancel() {
        guard isProcessing else { return }
        log("Manual cancel requested")
        drainTask?.cancel()
        drainTask = nil
        isProcessing = false
        endBackgroundTaskIfNeeded()
        MetadataBackgroundURLSession.shared.cancelAllTasks()
    }

    func drainReadySongs() -> [SongMetadata] {
        let persisted = load([PersistedSong].self, forKey: Self.readySongsKey) ?? []
        guard !persisted.isEmpty else { return [] }
        UserDefaults.standard.removeObject(forKey: Self.readySongsKey)

        return persisted.compactMap { item in
            let url = URL(fileURLWithPath: item.localURLPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return item.songMetadata(localURL: url)
        }
    }

    private func drainQueue() async {
        while !Task.isCancelled {
            let pending = QueuePersistenceStore.loadPendingDownloadedImports()
            guard let item = pending.first(where: { !inFlightImportPaths.contains($0.localURLPath) }) else { break }

            inFlightImportPaths.insert(item.localURLPath)
            defer { inFlightImportPaths.remove(item.localURLPath) }

            let url = URL(fileURLWithPath: item.localURLPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                removePendingImport(item)
                continue
            }

            var song = await parseSong(at: url)
            let sourceTrack = item.track?.downloadTrack
            song = await SongMetadataNetworking.$useBackgroundSession.withValue(true) {
                await enrich(song, sourceTrack: sourceTrack)
            }
            song = await persistDownloadedSongIfNeeded(song)

            appendReadySong(song)
            removePendingImport(item)
            log("Enriched \(song.title) [\(item.trackID ?? "unknown")] in the background.")
            NotificationCenter.default.post(name: .backgroundMetadataFetchCompleted, object: nil)
        }
    }

    private func parseSong(at url: URL) async -> SongMetadata {
        if let parsed = try? await SongMetadata.fromURL(url, includeArtwork: true) {
            return parsed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        log("Fallback metadata used for \(url.lastPathComponent) during background fetch.")
        return SongMetadata(
            localURL: url,
            title: url.deletingPathExtension().lastPathComponent,
            artist: "Unknown Artist",
            album: "Unknown Album",
            albumArtist: nil,
            genre: "Unknown Genre",
            year: Calendar.current.component(.year, from: Date()),
            durationMs: 0,
            fileSize: fileSize,
            remoteFilename: SongMetadata.generateRemoteFilename(withExtension: url.pathExtension.lowercased()),
            artworkData: nil,
            trackNumber: nil,
            trackCount: nil,
            discNumber: nil,
            discCount: nil,
            lyrics: nil
        )
    }

    private func enrich(_ initialSong: SongMetadata, sourceTrack: DownloadTrack?) async -> SongMetadata {
        await SongMetadata.enrichDownloadedSong(initialSong, sourceTrack: sourceTrack)
    }

    private func persistDownloadedSongIfNeeded(_ song: SongMetadata) async -> SongMetadata {
        guard UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else { return song }

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
            log("Failed to create persistent download folder: \(error)")
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
            let dest = destination
            let sourceSong = song
            try await Task.detached(priority: .utility) {
                try AudioTagWriter.copyKeptSong(sourceSong, to: dest)
            }.value
            try? FileManager.default.removeItem(at: song.localURL)
            var updatedSong = song
            updatedSong.localURL = destination
            return updatedSong
        } catch {
            log("Failed to persist downloaded song \(song.title): \(error)")
            return song
        }
    }

    private func appendReadySong(_ song: SongMetadata) {
        var persisted = load([PersistedSong].self, forKey: Self.readySongsKey) ?? []

        let duplicateSignature = Self.duplicateSignature(title: song.title, artist: song.artist, album: song.album)
        guard !persisted.contains(where: { Self.duplicateSignature(title: $0.title, artist: $0.artist, album: $0.album) == duplicateSignature }) else {
            log("Skipping duplicate ready-song append for \(song.title) — an un-drained entry already matches.")
            return
        }

        persisted.append(PersistedSong(song: song))
        save(persisted, forKey: Self.readySongsKey)
    }

    private static func duplicateSignature(title: String, artist: String, album: String) -> String {
        func normalize(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return "\(normalize(title))|\(normalize(artist))|\(normalize(album))"
    }

    private func removePendingImport(_ item: PersistedPendingDownloadedImport) {
        let remaining = QueuePersistenceStore.loadPendingDownloadedImports().filter { pending in
            pending.localURLPath != item.localURLPath
        }
        QueuePersistenceStore.savePendingDownloadedImports(remaining)
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        let taskState = BackgroundTaskState()
        taskState.id = UIApplication.shared.beginBackgroundTask(withName: "BackgroundMetadataFetch") { [weak self] in
            guard taskState.id != .invalid else { return }
            let expiredID = taskState.id
            UIApplication.shared.endBackgroundTask(expiredID)
            taskState.id = .invalid
            Task { @MainActor in
                self?.log("Background task expired while metadata fetch was active; cancelling drain")
                self?.drainTask?.cancel()
                self?.drainTask = nil
                self?.isProcessing = false
                self?.clearBackgroundTaskID(expiredID)
            }
        }
        backgroundTaskID = taskState.id
    }

    private func clearBackgroundTaskID(_ id: UIBackgroundTaskIdentifier) {
        if backgroundTaskID == id {
            backgroundTaskID = .invalid
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            log("Failed to save \(key): \(error)")
        }
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log("Failed to load \(key): \(error)")
            return nil
        }
    }

    private func log(_ message: String) {
        Logger.shared.log("[BGMetadata] \(message)")
    }
}
