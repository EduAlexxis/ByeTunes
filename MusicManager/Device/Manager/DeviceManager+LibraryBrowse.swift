import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func fetchDatabaseSnapshots(completion: @escaping ([DatabaseSnapshotInfo]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let root = self.snapshotsDirectoryURL
            let needsSecurityScope = root.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    root.stopAccessingSecurityScopedResource()
                }
            }

            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                completion([])
                return
            }
            
            var snapshots: [DatabaseSnapshotInfo] = []
            for dir in entries where dir.hasDirectoryPath && dir.lastPathComponent.hasPrefix("snapshot_") {
                let dbURL = dir.appendingPathComponent("MediaLibrary.sqlitedb")
                guard fm.fileExists(atPath: dbURL.path) else { continue }
                
                let values = try? dir.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
                let songCount = self.countSongsInSnapshotDB(dbURL)
                let sizeBytes = self.directorySize(dir)

                snapshots.append(
                    DatabaseSnapshotInfo(
                        folderName: dir.lastPathComponent,
                        createdAt: createdAt,
                        songCount: songCount,
                        sizeBytes: sizeBytes,
                        displayName: self.displayName(for: dir.lastPathComponent)
                    )
                )
            }
            
            snapshots.sort { $0.createdAt > $1.createdAt }
            completion(snapshots)
        }
    }

    func fetchExportableSongs(completion: @escaping ([ExportableSongInfo]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "loading the device library") else {
                completion([])
                return
            }

            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("song_export_probe_\(UUID().uuidString)", isDirectory: true)

            defer { try? fileManager.removeItem(at: tempDir) }

            do {
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[Export] Failed to create staging directory: \(error)")
                completion([])
                return
            }

            let semDb = DispatchSemaphore(value: 0)
            var dbData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                dbData = data
                semDb.signal()
            }
            semDb.waitForTransfer()

            let semWal = DispatchSemaphore(value: 0)
            var walData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.waitForTransfer()

            let semShm = DispatchSemaphore(value: 0)
            var shmData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.waitForTransfer()

            guard self.hasUsableExistingLibrary(dbData: dbData, walData: walData, shmData: shmData) else {
                Logger.shared.log(
                    "[Export] Failed to load usable MediaLibrary.sqlitedb for song export list " +
                    "(db=\(dbData?.count ?? 0), wal=\(walData?.count ?? 0), shm=\(shmData?.count ?? 0))"
                )
                completion([])
                return
            }

            guard let dbData else {
                Logger.shared.log("[Export] Missing primary MediaLibrary.sqlitedb data during export staging")
                completion([])
                return
            }

            let stagedDbURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
            do {
                try dbData.write(to: stagedDbURL)
                if let walData {
                    try walData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
                }
                if let shmData {
                    try shmData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
                }
            } catch {
                Logger.shared.log("[Export] Failed to stage export database files: \(error)")
                completion([])
                return
            }

            var onDeviceFiles = Set<String>()
            let musicRoot = "/iTunes_Control/Music"
            var musicSubfolders: [String] = []
            let semTop = DispatchSemaphore(value: 0)
            self.listFiles(remotePath: musicRoot) { entries in
                musicSubfolders = (entries ?? []).filter { $0.hasPrefix("F") }
                semTop.signal()
            }
            semTop.waitForTransfer()

            if musicSubfolders.isEmpty {
                musicSubfolders = [(self.resolvePrimaryMusicDirectory() as NSString).lastPathComponent]
            }

            for name in musicSubfolders {
                let semFiles = DispatchSemaphore(value: 0)
                self.listFiles(remotePath: "\(musicRoot)/\(name)") { files in
                    if let files {
                        onDeviceFiles.formUnion(files)
                    }
                    semFiles.signal()
                }
                semFiles.waitForTransfer()
            }

            let metadataMap = self.carrySongMetadataMapFromDatabase(stagedDbURL)
            let dbFilenames = self.musicFilenamesFromDatabase(stagedDbURL)
            Logger.shared.log("[Export] DB lists \(dbFilenames.count) song filename(s); on-device listing across \(musicSubfolders.count) folder(s) returned \(onDeviceFiles.count) file(s)")
            let songs = dbFilenames
                .filter { onDeviceFiles.contains($0) }
                .map { filename -> ExportableSongInfo in
                    let meta = metadataMap[filename]
                    let fallbackTitle = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                    return ExportableSongInfo(
                        itemPid: meta?.itemPid ?? 0,
                        remoteFilename: filename,
                        title: meta?.title ?? fallbackTitle,
                        artist: meta?.artist ?? "Unknown Artist",
                        album: meta?.album ?? "Unknown Album",
                        albumPid: meta?.albumPid ?? 0,
                        albumArtist: meta?.albumArtist ?? (meta?.artist ?? "Unknown Artist"),
                        genre: meta?.genre ?? "Music",
                        year: meta?.year ?? 0,
                        durationMs: meta?.durationMs ?? 0,
                        fileSize: meta?.fileSize ?? 0,
                        trackNumber: meta?.trackNumber,
                        lyrics: meta?.lyrics,
                        explicitRating: meta?.explicitRating ?? 0,
                        fileExtension: URL(fileURLWithPath: filename).pathExtension,
                        artworkRelativePath: meta?.artworkRelativePath
                    )
                }
                .sorted {
                    if $0.artist == $1.artist {
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                }

            Logger.shared.log("[Export] Found \(songs.count) exportable songs")
            completion(songs)
        }
    }

    func downloadSongFileForAnalysis(_ song: ExportableSongInfo, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "analyzing this song's audio quality") else {
                completion(nil)
                return
            }
            let musicDir = self.resolvePrimaryMusicDirectory()
            let remotePath = "\(musicDir)/\(song.remoteFilename)"
            self.downloadFileFromDevice(remotePath: remotePath) { data in
                completion(data)
            }
        }
    }

    func downloadPlaylistCoverArtwork(relativePath: String, completion: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "loading playlist cover artwork") else {
                completion(nil)
                return
            }
            let remotePath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
            self.downloadFileFromDevice(remotePath: remotePath) { data in
                completion(data)
            }
        }
    }

    func fetchExportablePlaylists(completion: @escaping ([(name: String, pid: Int64, songPids: [Int64], coverRelativePath: String?)]) -> Void) {
        let semDb = DispatchSemaphore(value: 0)
        var dbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            semDb.signal()
        }
        semDb.waitForTransfer()

        let semWal = DispatchSemaphore(value: 0)
        var walData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            walData = data
            semWal.signal()
        }
        semWal.waitForTransfer()

        let semShm = DispatchSemaphore(value: 0)
        var shmData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            shmData = data
            semShm.signal()
        }
        semShm.waitForTransfer()

        let playlists = withStagedMediaLibrary(dbData: dbData, walData: walData, shmData: shmData, label: "playlist_fetch") { stagedDbURL -> [(name: String, pid: Int64, songPids: [Int64], coverRelativePath: String?)]? in
            var db: OpaquePointer?
            guard sqlite3_open(stagedDbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return nil
            }
            defer { sqlite3_close(db) }

            var playlists: [(name: String, pid: Int64, songPids: [Int64], coverRelativePath: String?)] = []
            let getPlaylistsQuery = "SELECT name, container_pid FROM container WHERE contained_media_type = 8 AND distinguished_kind = 0 ORDER BY name"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, getPlaylistsQuery, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
                    let name = String(cString: namePtr)
                    let pid = sqlite3_column_int64(stmt, 1)

                    var pids: [Int64] = []
                    let getPidsQuery = "SELECT item_pid FROM container_item WHERE container_pid = ? ORDER BY position ASC"
                    var pidStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, getPidsQuery, -1, &pidStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int64(pidStmt, 1, pid)
                        while sqlite3_step(pidStmt) == SQLITE_ROW {
                            pids.append(sqlite3_column_int64(pidStmt, 0))
                        }
                    }
                    sqlite3_finalize(pidStmt)

                    var coverRelativePath: String?
                    let coverQuery = """
                    SELECT ar.relative_path FROM artwork_token at
                    JOIN artwork ar ON ar.artwork_token = at.artwork_token
                        AND ar.artwork_source_type = at.artwork_source_type
                        AND ar.artwork_variant_type = at.artwork_variant_type
                    WHERE at.entity_pid = ? AND at.entity_type = 1 AND at.artwork_type = 5
                    LIMIT 1
                    """
                    var coverStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, coverQuery, -1, &coverStmt, nil) == SQLITE_OK {
                        sqlite3_bind_int64(coverStmt, 1, pid)
                        if sqlite3_step(coverStmt) == SQLITE_ROW, let pathPtr = sqlite3_column_text(coverStmt, 0) {
                            coverRelativePath = String(cString: pathPtr)
                        }
                    }
                    sqlite3_finalize(coverStmt)

                    playlists.append((name, pid, pids, coverRelativePath))
                }
            }
            sqlite3_finalize(stmt)
            return playlists
        } ?? []

        completion(playlists)
    }

    static func isWritableExportFolder(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let probe = folder.appendingPathComponent(".byetunes-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    static func fallbackExportDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
    }

    func exportSongs(_ songs: [ExportableSongInfo], destinationFolder: URL?, completion: @escaping (Bool, String, [URL]) -> Void) {
        guard !songs.isEmpty else {
            completion(false, "No songs selected.", [])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let needsSecurityScope = destinationFolder?.startAccessingSecurityScopedResource() ?? false
            let finish: (Bool, String, [URL]) -> Void = { success, message, urls in
                if needsSecurityScope {
                    destinationFolder?.stopAccessingSecurityScopedResource()
                }
                completion(success, message, urls)
            }

            guard self.ensureActiveTransport(reason: "exporting songs from the device library") else {
                finish(false, "Could not reconnect to the device.", [])
                return
            }

            let fileManager = FileManager.default
            var exportDirectory = destinationFolder ?? Self.fallbackExportDirectory()
            var usedFallbackFolder = false

            if destinationFolder.map({ !Self.isWritableExportFolder($0) }) ?? true {
                Logger.shared.log("[Export] Selected export folder is unavailable, using app folder fallback: \(destinationFolder?.path ?? "none")")
                let fallback = Self.fallbackExportDirectory()
                do {
                    try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
                } catch {
                    Logger.shared.log("[Export] Failed to create fallback export folder: \(error)")
                    finish(false, "Could not access the selected folder or the app folder.", [])
                    return
                }
                exportDirectory = fallback
                usedFallbackFolder = true
            }

            let musicDir = self.resolvePrimaryMusicDirectory()
            var exportedURLs: [URL] = []
            var usedNames = Set<String>()
            var failedCount = 0

            func destinationURL(for song: ExportableSongInfo) -> URL {
                let ext = song.fileExtension.isEmpty ? "mp3" : song.fileExtension
                let baseName = Self.sanitizedExportFilenameBase("\(song.artist) - \(song.title)")
                var candidate = "\(baseName).\(ext)"
                var suffix = 1
                while usedNames.contains(candidate) {
                    candidate = "\(baseName)-\(suffix).\(ext)"
                    suffix += 1
                }
                usedNames.insert(candidate)
                return exportDirectory.appendingPathComponent(candidate)
            }

            func exportNext(_ index: Int) {
                guard index < songs.count else {
                    let success = !exportedURLs.isEmpty
                    let message: String
                    if success {
                        let summary = failedCount == 0
                            ? "Exported \(exportedURLs.count) song(s)."
                            : "Exported \(exportedURLs.count) song(s), \(failedCount) failed."
                        message = usedFallbackFolder
                            ? "\(summary) Your export folder wasn't available, so they were saved to the Exports folder in the Files app under On My iPhone > ByeTunes."
                            : summary
                    } else {
                        message = "No songs were exported."
                    }
                    finish(success, message, exportedURLs)
                    return
                }

                let song = songs[index]
                let localURL = destinationURL(for: song)
                if fileManager.fileExists(atPath: localURL.path) {
                    try? fileManager.removeItem(at: localURL)
                }

                let remotePath = "\(musicDir)/\(song.remoteFilename)"
                self.downloadFileFromDevice(remotePath: remotePath, localURL: localURL) { success in
                    if success {
                        exportedURLs.append(localURL)
                    } else {
                        failedCount += 1
                        Logger.shared.log("[Export] Failed to export \(song.remoteFilename)")
                    }
                    exportNext(index + 1)
                }
            }

            exportNext(0)
        }
    }
}
