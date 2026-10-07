import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Injection
extension DeviceManager {
    func isLocalAudioReadable(_ url: URL) -> Bool {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1) else { return false }
        return !head.isEmpty
    }

    func injectSongs(songs: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectSongs called with \(songs.count) songs")

        DispatchQueue.global(qos: .userInitiated).async {
            var validSongs: [SongMetadata] = []
            var unreadableTitles: [String] = []
            let isBatch = songs.count > 1

            for var song in songs {
                guard self.isLocalAudioReadable(song.localURL) else {
                    Logger.shared.log("[DeviceManager] Skipping unreadable local file: \(song.localURL.lastPathComponent) (\(song.title))")
                    unreadableTitles.append(song.title)
                    continue
                }
                if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let filename = song.localURL.lastPathComponent
                    Logger.shared.log("[DeviceManager] Sanitize: Empty title for '\(filename)', using filename.")
                    song.title = filename
                }

                if song.artist.isEmpty { song.artist = "Unknown Artist" }
                if song.album.isEmpty { song.album = "Unknown Album" }

                if isBatch && song.artist == "Unknown Artist" && song.album == "Unknown Album" {
                    Logger.shared.log("[DeviceManager] Batch Mode: Preserving song with fallback metadata '\(song.title)'")
                }

                if song.artworkData == nil {
                    let semaphore = DispatchSemaphore(value: 0)
                    var extractedArtwork: Data?
                    Task {
                        extractedArtwork = await SongMetadata.extractEmbeddedArtwork(from: song.localURL)
                        semaphore.signal()
                    }
                    semaphore.waitForTransfer()
                    song.artworkData = extractedArtwork
                }

                validSongs.append(song)
            }

            Logger.shared.log("[DeviceManager] Processing \(validSongs.count) songs (Sanitized).")

            if !unreadableTitles.isEmpty {
                Logger.shared.log("[DeviceManager] \(unreadableTitles.count) unreadable file(s) excluded from injection: \(unreadableTitles.prefix(5).joined(separator: ", "))")
                progress("Skipping \(unreadableTitles.count) unreadable file(s)...")
            }

            if validSongs.isEmpty {
                Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs found.")
                DispatchQueue.main.async { completion(unreadableTitles.isEmpty) }
                return
            }
            if self.killMusicBeforeInjectEnabled {
                progress("Preparing device state...")
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[SyncLifecycle] Music pre-kill \(killed ? "completed" : "skipped/failed")")
            }
            
            let musicDir = self.resolvePrimaryMusicDirectory()
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in \(musicDir)")
            var onDeviceFiles: Set<String> = []
            var listResult: DirectoryListResult = .unknown
            let semFiles = DispatchSemaphore(value: 0)

            self.listFilesOrConfirmMissing(remotePath: musicDir) { result in
                listResult = result
                semFiles.signal()
            }
            guard self.awaitAFCOperation(semFiles, timeoutSeconds: 60, step: "Listing device files") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            switch listResult {
            case .files(let files):
                onDeviceFiles = Set(files)
            case .confirmedMissing:
                onDeviceFiles = []
            case .unknown:
                Logger.shared.log("[DeviceManager] Could not confirm on-device file listing for \(musicDir) — aborting sync to avoid treating unknown as empty and wiping the library.")
                progress("Error: Could not verify device library. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            Logger.shared.log("[DeviceManager] Found \(onDeviceFiles.count) actual files on device")


            progress("Checking for existing library...")
            Logger.shared.log("[DeviceManager] Step 1: Downloading existing database")

            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?

            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            guard self.awaitAFCOperation(semaphoreDownload, timeoutSeconds: 180, step: "Downloading library database") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }


            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            guard self.awaitAFCOperation(semWal, timeoutSeconds: 120, step: "Downloading library WAL") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }


            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            guard self.awaitAFCOperation(semShm, timeoutSeconds: 120, step: "Downloading library SHM") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let hasExistingLibrary = self.hasUsableExistingLibrary(dbData: existingDbData, walData: walData, shmData: shmData)
            Logger.shared.log(
                "[DeviceManager] Existing library probe: db=\(existingDbData?.count ?? 0) bytes, wal=\(walData?.count ?? 0) bytes, shm=\(shmData?.count ?? 0) bytes, usable=\(hasExistingLibrary)"
            )
            
            
            progress("Setting up directories...")
            Logger.shared.log("[DeviceManager] Step 2: Setting up directories")
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil")
                DispatchQueue.main.async { completion(false) }
                return
            }
            defer { afc_client_free(afc) }
            
            
            
            
            self.ensureRemoteDirectoryExists("/iTunes_Control", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/Music", afc: afc)
            self.ensureRemoteDirectoryExists(musicDir, afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Caches", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/Artwork", afc: afc)
            Logger.shared.log("[DeviceManager] Step 2: Directories created")

            if !hasExistingLibrary {
                Logger.shared.log("[DeviceManager] Fresh-library path: refreshing AFC session before first upload")
                if !self.reconnectAfcClient(&afc, reason: "fresh library bootstrap") {
                    Logger.shared.log("[DeviceManager] ERROR: Failed to refresh AFC session for fresh library upload")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                self.ensureRemoteDirectoryExists(musicDir, afc: afc)
                self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afc)
            }

            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []
            var songPids: [Int64] = []
            
            do {
                
                if hasExistingLibrary, let existingData = existingDbData {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let version = self.getDatabaseVersion()
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs,
                        existingOnDeviceFiles: onDeviceFiles,
                        version: version
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo
                    songPids = result.pids
                    
                    Logger.shared.log("[DeviceManager] Existing files on device: \(existingFiles.count), artwork entries: \(artworkInfo.count)")
                } else {
                    if let existingDbData {
                        Logger.shared.log("[DeviceManager] Existing database is not usable as a merge base (\(existingDbData.count) bytes main DB, wal \(walData?.count ?? 0) bytes), creating fresh")
                    }
                    
                    progress("Creating new library...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database")
                    let version = self.getDatabaseVersion()
                    let createResult = try MediaLibraryBuilder.createDatabase(songs: validSongs, version: version)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo
                    songPids = createResult.pids
                }
            } catch {
                
                
                Logger.shared.log("[DeviceManager] ⚠️ MERGE FAILED: \(error)")
                Logger.shared.log("[DeviceManager] Aborting to preserve existing library. User should restart their iPhone and try again.")
                progress("Error: Could not merge. Restart iPhone and retry.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading songs...")
            Logger.shared.log("[DeviceManager] Step 4: Uploading \(validSongs.count) audio files (RP Pairing: \(self.requiresRPPairingTunnel))")

            var uploadedCount = 0
            var skippedCount = 0

            var toUpload: [(index: Int, song: SongMetadata)] = []
            for (index, song) in validSongs.enumerated() {
                if existingFiles.contains(song.remoteFilename) {
                    Logger.shared.log("[DeviceManager] Skipping (already exists): \(song.title)")
                    skippedCount += 1
                } else {
                    toUpload.append((index, song))
                }
            }

            let shouldUseParallelUploads = toUpload.count >= 4

            if shouldUseParallelUploads {
                let uploadJobs = toUpload.map { upload in
                    (
                        localURL: upload.song.localURL,
                        remotePath: "\(musicDir)/\(upload.song.remoteFilename)",
                        label: upload.song.title
                    )
                }
                let uploadResult = self.uploadFilesToDeviceInChunks(
                    uploadJobs,
                    progressLabel: "Uploading",
                    progress: progress
                )
                uploadedCount = uploadResult.uploadedCount

                if !uploadResult.success {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            } else {
                for (_, song) in toUpload {
                    progress("Uploading \(uploadedCount + 1)/\(toUpload.count): \(song.title)")
                    let remotePath = "\(musicDir)/\(song.remoteFilename)"
                    guard self.uploadFileToDeviceWithReconnect(localURL: song.localURL, remotePath: remotePath, afc: &afc, verify: false) else {
                        Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    uploadedCount += 1
                }
            }

            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork", afc: afc)
            self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afc)

            let artworkMap = Dictionary(uniqueKeysWithValues: artworkInfo.map { ($0.itemPid, $0) })
            var artworkUploads: [(data: Data, remotePath: String, label: String)] = []

            for (originalIndex, song) in toUpload {
                guard let artworkData = song.artworkData, originalIndex < songPids.count else { continue }
                let songPid = songPids[originalIndex]
                guard let info = artworkMap[songPid] else {
                    Logger.shared.log("[DeviceManager] No artwork DB entry found for song: \(song.title)")
                    continue
                }
                let artworkRelativePath = info.artworkHash
                let folderName = artworkRelativePath.components(separatedBy: "/").first ?? "00"
                let artworkDir = "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)"
                let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"

                self.ensureRemoteDirectoryExists(artworkDir, afc: afc)
                artworkUploads.append((data: artworkData, remotePath: artworkPath, label: song.title))
            }

            if artworkUploads.count >= 4 {
                let artworkUploadResult = self.uploadDataToDeviceInChunks(
                    artworkUploads,
                    progressLabel: "Uploading artwork",
                    progress: progress
                )
                if !artworkUploadResult.success {
                    Logger.shared.log("[DeviceManager] WARNING: Some artwork uploads failed during parallel transfer")
                }
            } else {
                for artworkUpload in artworkUploads {
                    if self.uploadDataToDeviceWithReconnect(artworkUpload.data, remotePath: artworkUpload.remotePath, afc: &afc, verify: false) {
                        Logger.shared.log("[DeviceManager] Artwork uploaded: \(artworkUpload.remotePath)")
                    } else {
                        Logger.shared.log("[DeviceManager] WARNING: Artwork upload failed for: \(artworkUpload.label)")
                    }
                }
            }

            Logger.shared.log("[DeviceManager] Uploaded: \(uploadedCount), Skipped: \(skippedCount)")
            
            
            
            Logger.shared.log("[DeviceManager] Step 4.5: ArtworkDB generation SKIPPED - iOS handles artwork internally")

            
            
            progress("Repairing alphabetical order...")
            guard self.repairAlphabeticalOrderingInLocalDatabase(dbURL, logContext: "[DeviceManager]") else {
                progress("Error: Could not repair alphabetical order.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            progress("Uploading database...")
            Logger.shared.log("[DeviceManager] Step 5: Uploading database (Atomic Upgrade)")
            
            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
            let dbUploadSuccess = self.uploadFileToDeviceWithReconnect(localURL: dbURL, remotePath: tempDBPath, afc: &afc)
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let afcHandle = afc, self.replaceRemoteMediaLibrary(
                tempDBPath: tempDBPath,
                finalDBPath: finalDBPath,
                shmPath: shmPath,
                walPath: walPath,
                afc: afcHandle,
                logContext: "[DeviceManager]"
            ) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            Logger.shared.log("[DeviceManager] Database swapped successfully.")

            progress("Finalizing...")
            Logger.shared.log("[DeviceManager] Step 6: Garbage Collection")
            
            let newFilenames = validSongs.map { $0.remoteFilename }
            let snapshotProtectedFiles = self.protectedFilenamesFromAllSnapshots()
            let allValidFiles = existingFiles.union(newFilenames).union(snapshotProtectedFiles)
            
            Logger.shared.log("[DeviceManager] GC Whitelist: \(allValidFiles.count) files (Old: \(existingFiles.count), New: \(newFilenames.count), SnapshotProtected: \(snapshotProtectedFiles.count))")

            self.cleanUpOrphanedFiles(validFilenames: allValidFiles, musicDir: musicDir) { deletedCount in
                if deletedCount > 0 {
                   Logger.shared.log("[DeviceManager] Garbage Collection finished. Deleted \(deletedCount) orphaned files.")
                } else {
                   Logger.shared.log("[DeviceManager] Garbage Collection finished. No orphans found.")
                }
                
                Logger.shared.log("[DeviceManager] Step 7: Sending sync notification")
                self.sendSyncFinishedNotification()
                
                progress("Complete! Restart your iPhone.")
                Logger.shared.log("[DeviceManager] Injection complete!")
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    
    
    func injectSongsAsPlaylist(songs: [SongMetadata], playlistName: String? = nil, targetPlaylistPid: Int64? = nil, progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectSongsAsPlaylist called with \(songs.count) songs, playlist: '\(playlistName ?? "Existing")'")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var validSongs: [SongMetadata] = []
            var unreadableCount = 0
            for var song in songs {
                guard self?.isLocalAudioReadable(song.localURL) ?? true else {
                    Logger.shared.log("[DeviceManager] Skipping unreadable local file: \(song.localURL.lastPathComponent) (\(song.title))")
                    unreadableCount += 1
                    continue
                }
                if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let filename = song.localURL.lastPathComponent
                    song.title = filename
                }
                if song.artist.isEmpty { song.artist = "Unknown Artist" }
                if song.album.isEmpty { song.album = "Unknown Album" }
                if song.artworkData == nil {
                    let semaphore = DispatchSemaphore(value: 0)
                    var extractedArtwork: Data?
                    Task {
                        extractedArtwork = await SongMetadata.extractEmbeddedArtwork(from: song.localURL)
                        semaphore.signal()
                    }
                    semaphore.waitForTransfer()
                    song.artworkData = extractedArtwork
                }
                validSongs.append(song)
            }

            if unreadableCount > 0 {
                Logger.shared.log("[DeviceManager] \(unreadableCount) unreadable file(s) excluded from playlist injection")
                progress("Skipping \(unreadableCount) unreadable file(s)...")
            }

            if validSongs.isEmpty {
                Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs for playlist.")
                DispatchQueue.main.async { completion(unreadableCount == 0) }
                return
            }
        
            guard let self = self else { return }
            let musicDir = self.resolvePrimaryMusicDirectory()
            
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in \(musicDir)")
            var onDeviceFiles: Set<String> = []
            var listResult: DirectoryListResult = .unknown
            let semFiles = DispatchSemaphore(value: 0)

            self.listFilesOrConfirmMissing(remotePath: musicDir) { result in
                listResult = result
                semFiles.signal()
            }
            guard self.awaitAFCOperation(semFiles, timeoutSeconds: 60, step: "Listing device files (playlist)") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            switch listResult {
            case .files(let files):
                onDeviceFiles = Set(files)
            case .confirmedMissing:
                onDeviceFiles = []
            case .unknown:
                Logger.shared.log("[DeviceManager] Could not confirm on-device file listing for \(musicDir) — aborting sync to avoid treating unknown as empty and wiping the library.")
                progress("Error: Could not verify device library. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            Logger.shared.log("[DeviceManager] Found \(onDeviceFiles.count) actual files on device")


            progress("Checking for existing library...")
            Logger.shared.log("[DeviceManager] Step 1: Downloading existing database")

            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?

            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            guard self.awaitAFCOperation(semaphoreDownload, timeoutSeconds: 180, step: "Downloading library database (playlist)") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }


            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            guard self.awaitAFCOperation(semWal, timeoutSeconds: 120, step: "Downloading library WAL (playlist)") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            guard self.awaitAFCOperation(semShm, timeoutSeconds: 120, step: "Downloading library SHM (playlist)") else {
                progress("Error: Device connection stalled. Try again.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            let hasExistingLibrary = self.hasUsableExistingLibrary(dbData: existingDbData, walData: walData, shmData: shmData)
            Logger.shared.log(
                "[DeviceManager] Existing playlist library probe: db=\(existingDbData?.count ?? 0) bytes, wal=\(walData?.count ?? 0) bytes, shm=\(shmData?.count ?? 0) bytes, usable=\(hasExistingLibrary)"
            )
            
            
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            if afc != nil {
                
                
                
                self.ensureRemoteDirectoryExists(musicDir, afc: afc)
                self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afc)
                afc_client_free(afc)
            }
            
            
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []

            
            do {
                if hasExistingLibrary, let existingData = existingDbData {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let version = self.getDatabaseVersion()
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs, 
                        playlistName: playlistName,
                        targetPlaylistPid: targetPlaylistPid,
                        existingOnDeviceFiles: onDeviceFiles,
                        version: version
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo

                } else {
                    if let existingDbData {
                        Logger.shared.log("[DeviceManager] Existing playlist database is not usable as a merge base (\(existingDbData.count) bytes main DB, wal \(walData?.count ?? 0) bytes), creating fresh")
                    }
                    progress("Creating new library with playlist...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database with playlist")
                    let version = self.getDatabaseVersion()
                    let createResult = try MediaLibraryBuilder.createDatabase(songs: validSongs, version: version, playlistName: playlistName)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo

                }
            } catch {
                Logger.shared.log("[DeviceManager] ⚠️ PLAYLIST MERGE FAILED: \(error)")
                Logger.shared.log("[DeviceManager] Aborting to preserve existing library. User should restart their iPhone and try again.")
                progress("Error: Could not merge. Restart iPhone and retry.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading songs...")
            
            var uploadedCount = 0

            let songsToUpload = validSongs.filter { !existingFiles.contains($0.remoteFilename) }
            let shouldUseParallelUploads = songsToUpload.count >= 4

            if shouldUseParallelUploads {
                let uploadJobs = songsToUpload.map { song in
                    (
                        localURL: song.localURL,
                        remotePath: "\(musicDir)/\(song.remoteFilename)",
                        label: song.title
                    )
                }
                let uploadResult = self.uploadFilesToDeviceInChunks(
                    uploadJobs,
                    progressLabel: "Uploading",
                    progress: progress
                )
                uploadedCount = uploadResult.uploadedCount

                if !uploadResult.success {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            } else {
                for (index, song) in songsToUpload.enumerated() {
                    progress("Uploading \(index + 1)/\(songsToUpload.count): \(song.title)")

                    let semaphore = DispatchSemaphore(value: 0)
                    var uploadSuccess = false
                    let remotePath = "\(musicDir)/\(song.remoteFilename)"

                    self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                        uploadSuccess = success
                        semaphore.signal()
                    }
                    semaphore.waitForTransfer()

                    if !uploadSuccess {
                        Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    uploadedCount += 1
                }
            }
            
            

            var artworkUploads: [(data: Data, remotePath: String, label: String)] = []
            var afcArtwork: AfcClientHandle?
            self.connectAfcClient(&afcArtwork)
            if afcArtwork != nil {
                self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork", afc: afcArtwork)
                self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals", afc: afcArtwork)
            }

            var artworkIndex = 0
            for song in validSongs {
                if existingFiles.contains(song.remoteFilename) { continue }
                guard let artworkData = song.artworkData, artworkIndex < artworkInfo.count else { continue }

                let info = artworkInfo[artworkIndex]
                let artworkRelativePath = info.artworkHash
                let folderName = artworkRelativePath.components(separatedBy: "/").first ?? "00"
                let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                if afcArtwork != nil {
                    self.ensureRemoteDirectoryExists("/iTunes_Control/iTunes/Artwork/Originals/\(folderName)", afc: afcArtwork)
                }
                artworkUploads.append((data: artworkData, remotePath: artworkPath, label: song.title))
                artworkIndex += 1
            }

            if let afcArtwork {
                afc_client_free(afcArtwork)
            }

            if artworkUploads.count >= 4 {
                let artworkUploadResult = self.uploadDataToDeviceInChunks(
                    artworkUploads,
                    progressLabel: "Uploading artwork",
                    progress: progress
                )
                if !artworkUploadResult.success {
                    Logger.shared.log("[DeviceManager] WARNING: Some playlist artwork uploads failed during parallel transfer")
                }
            } else {
                var afcArtworkSequential: AfcClientHandle?
                self.connectAfcClient(&afcArtworkSequential)
                for artworkUpload in artworkUploads {
                    if self.uploadDataToDeviceWithReconnect(artworkUpload.data, remotePath: artworkUpload.remotePath, afc: &afcArtworkSequential, verify: false) {
                        Logger.shared.log("[DeviceManager] Artwork uploaded: \(artworkUpload.remotePath)")
                    } else {
                        Logger.shared.log("[DeviceManager] WARNING: Artwork upload failed for: \(artworkUpload.label)")
                    }
                }
                if let afcArtworkSequential {
                    afc_client_free(afcArtworkSequential)
                }
            }

            
            progress("Repairing alphabetical order...")
            guard self.repairAlphabeticalOrderingInLocalDatabase(dbURL, logContext: "[DeviceManager] Playlist injection") else {
                progress("Error: Could not repair alphabetical order.")
                DispatchQueue.main.async { completion(false) }
                return
            }

            progress("Uploading database...")
            Logger.shared.log("[DeviceManager] Step 5: Uploading database (Atomic Upgrade)")
            
            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
            
            
            let semUploadDB = DispatchSemaphore(value: 0)
            var dbUploadSuccess = false
            self.uploadFileToDevice(localURL: dbURL, remotePath: tempDBPath) { success in
                dbUploadSuccess = success
                semUploadDB.signal()
            }
            semUploadDB.waitForTransfer()
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var afcSwap: AfcClientHandle?
            self.connectAfcClient(&afcSwap)
            
            guard afcSwap != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to connect AFC for atomic swap")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            guard let afcSwapHandle = afcSwap, self.replaceRemoteMediaLibrary(
                tempDBPath: tempDBPath,
                finalDBPath: finalDBPath,
                shmPath: shmPath,
                walPath: walPath,
                afc: afcSwapHandle,
                logContext: "[DeviceManager]"
            ) else {
                afc_client_free(afcSwap)
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            Logger.shared.log("[DeviceManager] Database swapped successfully.")
            afc_client_free(afcSwap)
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Finalizing...")
            self.sendSyncFinishedNotification()
            
            progress("Playlist '\(playlistName ?? "Unknown")' updated!")
            Logger.shared.log("[DeviceManager] Playlist injection complete!")
            DispatchQueue.main.async { completion(true) }
        }
    }
    
    func fetchPlaylists(completion: @escaping ([(name: String, pid: Int64)]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.heartbeatReady else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            var dbData: Data?
            let sem = DispatchSemaphore(value: 0)
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                dbData = data
                sem.signal()
            }
            sem.waitForTransfer()

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

            guard let playlists = self.withStagedMediaLibrary(dbData: dbData, walData: walData, shmData: shmData, label: "playlist_fetch_basic", { dbURL in
                MediaLibraryBuilder.extractPlaylists(fromDbPath: dbURL.path)
            }) else {
                Logger.shared.log("[DeviceManager] Failed to download DB for playlist fetch")
                DispatchQueue.main.async { completion([]) }
                return
            }

            DispatchQueue.main.async { completion(playlists) }
        }
    }
    
    
    
}
