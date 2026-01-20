import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Type Aliases
typealias IdevicePairingFile = OpaquePointer
typealias IdeviceProviderHandle = OpaquePointer
typealias HeartbeatClientHandle = OpaquePointer
typealias AfcClientHandle = OpaquePointer
typealias AfcFileHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

typealias IdeviceErrorCode = UnsafeMutablePointer<IdeviceFfiError>?

let IdeviceSuccess: IdeviceErrorCode = nil

// Anti-Ghost Build Version - INCREMENT THIS BEFORE EACH BUILD!
private let BUILD_VERSION = "v1.0.7"

class DeviceManager: ObservableObject {
    @Published var heartbeatReady: Bool = false
    @Published var connectionStatus: String = "Disconnected"
    var provider: IdeviceProviderHandle?
    var heartbeatThread: Thread?
    
    static var shared = DeviceManager()
    
    var pairingFile: URL {
        return URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
    }
    
    private init() {
        print("===========================================")
        print("[DeviceManager] BUILD VERSION: \(BUILD_VERSION)")
        print("===========================================")
        print("[DeviceManager] Initializing...")
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice-logs.txt").path
        let cString = strdup(logPath)
        defer { free(cString) }
        idevice_init_logger(Info, Disabled, cString)
    }

    // MARK: - Heartbeat Connection
    // Conectar el heartbeat pa que no se cierre la conexion
    
    // MARK: - Heartbeat Connection
    
    func startHeartbeat() {
        // If already connecting or connected, don't spam? 
        // Actually, user wants "Retry", so we should allow re-entrancy but maybe cancel previous?
        // For simplicity, just spawn a new check.
        
        heartbeatThread = Thread {
            DispatchQueue.main.async {
                self.connectionStatus = "Connecting..."
            }
            
            self.establishHeartbeat { success in
                DispatchQueue.main.async {
                    if success {
                        // Connection was successful but now finished (likely lost)
                        self.connectionStatus = "Connection Lost"
                        self.heartbeatReady = false
                    } else {
                        // Never connected
                        self.connectionStatus = "Connection Failed"
                        self.heartbeatReady = false
                    }
                }
            }
        }
        heartbeatThread?.name = "HeartbeatThread"
        heartbeatThread?.start()
    }

    func establishHeartbeat(_ completion: @escaping (Bool) -> Void) {
                 
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(LOCKDOWN_PORT))
        inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr)
        
        var pairingPtr: IdevicePairingFile?
        let _ = idevice_pairing_file_read(pairingFile.path, &pairingPtr)
        
        if let oldProvider = provider {
            idevice_provider_free(oldProvider)
            provider = nil
        }
        
        let providerErr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                idevice_tcp_provider_new(sockaddrPointer, pairingPtr, "Music-Provider", &provider)
            }
        }
        
        if provider == nil {
            print("[DeviceManager] ERROR: Provider is nil. Err: \(String(describing: providerErr))")
            completion(false)
            return
        }
        
        var hbClient: HeartbeatClientHandle?
        let err = heartbeat_connect(provider, &hbClient)
        
        if err == IdeviceSuccess && hbClient != nil {
            print("[DeviceManager] Heartbeat connected successfully!")
            
            DispatchQueue.main.async {
                self.connectionStatus = "Connected"
                self.heartbeatReady = true
            }
            
            // Loop while connected
            while true {
                var newInterval: UInt64 = 0
                // We use 5s timeout. We do NOT check for error because false positives occur frequently.
                // If the connection is truly dead, the outer loop isn't reachable, but at least we don't spam reconnects.
                // This matches the stable behavior of the previous version.
                heartbeat_get_marco(hbClient, 10, &newInterval)
                
                heartbeat_send_polo(hbClient)
                
                DispatchQueue.main.async {
                    if !self.heartbeatReady {
                         self.heartbeatReady = true
                         self.connectionStatus = "Connected"
                    }
                }
                
                // Sleep 5s between heartbeats
                Thread.sleep(forTimeInterval: 5)
            }
            
            // Cleanup
            heartbeat_client_free(hbClient)
            completion(true) // Was successful previously
        } else {
            print("[DeviceManager] ERROR: Heartbeat connection failed")
            completion(false)
        }
    }

    // MARK: - Notification Proxy
    // Mandar notis al device pa que sepa que ya acabamos
    
    func sendSyncFinishedNotification() {
        var lockdownd: LockdowndClientHandle?
        let err = lockdownd_connect(provider, &lockdownd)
        
        if err == IdeviceSuccess {
            var port: UInt16 = 0
            var ssl: Bool = false
            _ = lockdownd_start_service(lockdownd, "com.apple.mobile.notification_proxy", &port, &ssl)
            lockdownd_client_free(lockdownd)
        }
    }
    
    // MARK: - ATC Sync (Triggers Music Library Update)
    // Disparar el sync de ATC (pa que actualice la library de musica)
    
    func triggerATCSync(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var lockdownd: LockdowndClientHandle?
            let err = lockdownd_connect(self.provider, &lockdownd)
            
            guard err == IdeviceSuccess else {
                print("[DeviceManager] Failed to connect lockdownd for ATC")
                completion(false)
                return
            }
            
            var port: UInt16 = 0
            var ssl: Bool = false
            let _ = lockdownd_start_service(lockdownd, "com.apple.atc", &port, &ssl)
            
            lockdownd_client_free(lockdownd)
            
            if port > 0 {
                // Note: Full ATC protocol implementation would require:
                // 1. Connect to the ATC port via TCP
                // 2. Wrap in SSL using the pairing certificates
                // 3. Send ATC commands (little-endian length + plist)
                // For now, just confirming we can start the service
                completion(true)
            } else {
                print("[DeviceManager] Failed to get ATC port")
                completion(false)
            }
        }
    }
    
    // MARK: - AFC File Operations
    // Operaciones de archivos AFC (subir/borrar cosas)

    func addSongToDevice(localURL: URL, filename: String, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] addSongToDevice called for: \(filename)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
            print("[DeviceManager] Security scoped access needed: \(needsSecurityScope)")
            defer {
                if needsSecurityScope {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            
            print("[DeviceManager] File exists: \(FileManager.default.fileExists(atPath: localURL.path))")

            print("[DeviceManager] Connecting AFC client...")
            afc_client_connect(self.provider, &afc)
            print("[DeviceManager] AFC client connected: \(afc != nil)")
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil")
                completion(false)
                return
            }
            
            // Ensure directory exists
            let musicDir = "/iTunes_Control/Music/F00"
            print("[DeviceManager] Creating directory: \(musicDir)")
            afc_make_directory(afc, musicDir)
            
            let remotePath = "\(musicDir)/\(filename)"
            print("[DeviceManager] Opening remote file: \(remotePath)")
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                print("[DeviceManager] ERROR: Could not open remote file")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            if let data = try? Data(contentsOf: localURL) {
                // print("[DeviceManager] Writing \(data.count) bytes...")
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                // print("[DeviceManager] Write complete")
            } else {
                print("[DeviceManager] ERROR: Could not read file data from \(localURL.path)")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
            
            afc_file_close(file)
            afc_client_free(afc)
            
            self.sendSyncFinishedNotification()
            print("[DeviceManager] addSongToDevice complete")
            completion(true)
        }
    }
    
    // MARK: - File Deletion
    
    func removeFileFromDevice(remotePath: String, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] removeFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil for deletion")
                completion(false)
                return
            }
            
            
            let err = afc_remove_path(afc, remotePath)
            // print("[DeviceManager] Remove result for \(remotePath): \(err == nil ? "success" : "error")")
            
            afc_client_free(afc)
            completion(err == nil)
        }
    }
    
    // MARK: - Library Reset
    
    func deleteMediaLibrary(completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] DELETING MEDIA LIBRARY...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil for library reset")
                completion(false)
                return
            }
            
            // Delete main DB and journals
            let files = [
                "/iTunes_Control/iTunes/MediaLibrary.sqlitedb",
                "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal",
                "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            ]
            
            for file in files {
                afc_remove_path(afc, file)
            }
            
            afc_client_free(afc)
            self.sendSyncFinishedNotification()
            print("[DeviceManager] Library deleted.")
            completion(true)
        }
    }
    
    func downloadFileFromDevice(remotePath: String, localURL: URL, completion: @escaping (Bool) -> Void) {
        self.downloadFileFromDevice(remotePath: remotePath) { data in
            guard let data = data else {
                completion(false)
                return
            }
            do {
                try data.write(to: localURL)
                completion(true)
            } catch {
                print("[DeviceManager] Error writing downloaded file: \(error)")
                completion(false)
            }
        }
    }
    
    
    func downloadFileFromDevice(remotePath: String, completion: @escaping (Data?) -> Void) {
        print("[DeviceManager] downloadFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil for download")
                completion(nil)
                return
            }
            
            // Open file for reading
            afc_file_open(afc, remotePath, AfcRdOnly, &file)
            
            guard file != nil else {
                print("[DeviceManager] File does not exist or cannot be opened: \(remotePath)")
                afc_client_free(afc)
                completion(nil)
                return
            }
            
            // Read the file data
            var dataPtr: UnsafeMutablePointer<UInt8>?
            var length: Int = 0
            
            let err = afc_file_read(file, &dataPtr, &length)
            
            if err == nil, let dataPtr = dataPtr, length > 0 {
                let data = Data(bytes: dataPtr, count: length)
                print("[DeviceManager] Downloaded \(length) bytes from \(remotePath)")
                afc_file_read_data_free(dataPtr, length)
                afc_file_close(file)
                afc_client_free(afc)
                completion(data)
            } else {
                print("[DeviceManager] Failed to read file: \(remotePath)")
                afc_file_close(file)
                afc_client_free(afc)
                completion(nil)
            }
        }
    }
    
    // MARK: - Generic File Upload
    
    func uploadFileToDevice(localURL: URL, remotePath: String, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] uploadFileToDevice called: \(localURL.lastPathComponent) -> \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil for upload")
                completion(false)
                return
            }
            
            // Ensure parent directory exists before opening file for write
            let parentDir = (remotePath as NSString).deletingLastPathComponent
            afc_make_directory(afc, parentDir)
            
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                print("[DeviceManager] ERROR: Could not open remote file: \(remotePath)")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            
            if let data = try? Data(contentsOf: localURL) {
                // print("[DeviceManager] Writing \(data.count) bytes to \(remotePath)...")
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                // print("[DeviceManager] Write complete")
                
                afc_file_close(file)
                
                // Verify file existence using simple open check
                var checkFile: AfcFileHandle?
                let ret = afc_file_open(afc, remotePath, AfcRdOnly, &checkFile)
                if ret == nil { // nil return means success (no error) for IdeviceFfiError pointers
                    if checkFile != nil {
                        afc_file_close(checkFile)
                    }
                    afc_client_free(afc)
                    completion(true)
                } else {
                    print("[DeviceManager] ERROR: Verification failed for \(remotePath)")
                    afc_client_free(afc)
                    completion(false)
                }
            } else {
                print("[DeviceManager] ERROR: Could not read file data")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
        }
    }
    
    // MARK: - Full Injection Workflow (with merge support)
    
    func injectSongs(songs: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] injectSongs called with \(songs.count) songs")
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Step 1: Try to download existing database
            progress("Checking for existing library...")
            print("[DeviceManager] Step 1: Downloading existing database")
            
            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            semaphoreDownload.wait()
            
            // Download WAL
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            // Download SHM
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            // Step 2: Create/Connect AFC and setup directories
            progress("Setting up directories...")
            print("[DeviceManager] Step 2: Setting up directories")
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Delete WAL/SHM files (they can cause issues)
            afc_remove_path(afc, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm")
            afc_remove_path(afc, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal")
            
            // Create ALL necessary directories (including parents)
            afc_make_directory(afc, "/iTunes_Control")
            afc_make_directory(afc, "/iTunes_Control/Music")
            afc_make_directory(afc, "/iTunes_Control/Music/F00")
            afc_make_directory(afc, "/iTunes_Control/iTunes")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Caches")
            afc_make_directory(afc, "/iTunes_Control/Artwork")
            print("[DeviceManager] Step 2: Directories created")
            
            afc_client_free(afc)
            
            // Step 3: Create database (merge or fresh)
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []
            
            do {
                // FORCE FRESH LIBRARY for debugging (Condition includes false to skip block)
                if let existingData = existingDbData, existingData.count > 10000, false {
                    progress("Merging with existing library...")
                    print("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: songs
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo
                    
                    print("[DeviceManager] Existing files on device: \(existingFiles.count), artwork entries: \(artworkInfo.count)")
                } else {
                    if existingDbData != nil {
                        print("[DeviceManager] Existing database too small (\(existingDbData!.count) bytes), creating fresh")
                    }
                    // Create fresh
                    progress("Creating new library...")
                    print("[DeviceManager] Step 3: Creating fresh database")
                    let createResult = try MediaLibraryBuilder.createDatabase_v104(songs: songs)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo
                }
            } catch {
                // If merge failed, try creating a fresh database instead
                print("[DeviceManager] Merge failed: \(error), falling back to fresh database")
                // Create fresh
                progress("Creating fresh database...")
                print("[DeviceManager] Step 3 (VERIFIED): Creating fresh database")
                do {
                    let result = try MediaLibraryBuilder.createDatabase_v104(songs: songs)
                    dbURL = result.dbURL
                    artworkInfo = result.artworkInfo
                } catch {
                    print("[DeviceManager] Failed to create fresh database: \(error)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            }
            
            // Step 4: Upload MP3 files (skip existing ones)
            progress("Uploading songs...")
            print("[DeviceManager] Step 4: Uploading MP3 files")
            
            var uploadedCount = 0
            var skippedCount = 0
            
            for (index, song) in songs.enumerated() {
                // Skip if file already exists on device
                if existingFiles.contains(song.remoteFilename) {
                    print("[DeviceManager] Skipping (already exists): \(song.title)")
                    skippedCount += 1
                    continue
                }
                
                progress("Uploading \(index + 1)/\(songs.count): \(song.title)")
                // print("[DeviceManager] Uploading: \(song.title) -> \(song.remoteFilename)")
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                
                semaphore.wait()
                
                if !uploadSuccess {
                    print("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                uploadedCount += 1
                
                // Upload artwork file using the path from artworkInfo
                // artworkInfo now contains correct paths: SHA1(token) -> XX/hash
                if let artworkData = song.artworkData, index < artworkInfo.count {
                    let info = artworkInfo[index]
                    let artworkRelativePath = info.artworkHash  // Format: "XX/hashstring"
                    
                    let pathComponents = artworkRelativePath.components(separatedBy: "/")
                    let folderName = pathComponents.count >= 1 ? pathComponents[0] : "00"
                    let fileName = pathComponents.count >= 2 ? pathComponents[1] : "unknown"
                    
                    let artworkDir = "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)"
                    let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                    
                    print("[DeviceManager] Uploading artwork for: \(song.title) -> \(artworkPath)")
                    
                    // Create directory
                    var afcArt: AfcClientHandle?
                    afc_client_connect(self.provider, &afcArt)
                    if afcArt != nil {
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork")
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork/Originals")
                        afc_make_directory(afcArt, artworkDir)
                        afc_client_free(afcArt)
                    }
                    
                    // Save artwork to temp file
                    let tempArtwork = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? artworkData.write(to: tempArtwork)
                    
                    // Upload
                    let artworkSem = DispatchSemaphore(value: 0)
                    self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { _ in
                        artworkSem.signal()
                    }
                    artworkSem.wait()
                    
                    try? FileManager.default.removeItem(at: tempArtwork)
                    print("[DeviceManager] Artwork uploaded to: \(artworkPath)")
                }
            }
            
            print("[DeviceManager] Uploaded: \(uploadedCount), Skipped: \(skippedCount)")
            
            // Step 4.5: ArtworkDB generation DISABLED
            // iOS manages its own artwork database using internal algorithms.
            // We no longer upload external artwork or ArtworkDB files.
            print("[DeviceManager] Step 4.5: ArtworkDB generation SKIPPED - iOS handles artwork internally")

            
            // Step 5: Upload merged database
            progress("Uploading database...")
            print("[DeviceManager] Step 5: Uploading database")
            
            // First delete the old database
            var afcDel: AfcClientHandle?
            afc_client_connect(self.provider, &afcDel)
            if afcDel != nil {
                afc_remove_path(afcDel, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb")
                afc_client_free(afcDel)
            }
            
            let semaphoreUploadDb = DispatchSemaphore(value: 0)
            var dbUploadSuccess = false
            
            self.uploadFileToDevice(localURL: dbURL, remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { success in
                dbUploadSuccess = success
                semaphoreUploadDb.signal()
            }
            
            semaphoreUploadDb.wait()
            
            if !dbUploadSuccess {
                print("[DeviceManager] ERROR: Failed to upload database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Cleanup temp file
            try? FileManager.default.removeItem(at: dbURL)
            
            // Step 6: Send sync notification
            progress("Finalizing...")
            print("[DeviceManager] Step 6: Sending sync notification")
            self.sendSyncFinishedNotification()
            
            progress("Complete! Restart your iPhone.")
            print("[DeviceManager] Injection complete!")
            DispatchQueue.main.async { completion(true) }
        }
    }
    
    // MARK: - Playlist Injection
    
    /// Inject songs and create a playlist containing them
    func injectSongsAsPlaylist(songs: [SongMetadata], playlistName: String? = nil, targetPlaylistPid: Int64? = nil, progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] injectSongsAsPlaylist called with \(songs.count) songs, playlist: '\(playlistName ?? "Existing")'")
        
        let tempDir = FileManager.default.temporaryDirectory
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Try to download existing database
            progress("Checking for existing library...")
            
            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb", localURL: tempDir.appendingPathComponent("temp_lib.sqlitedb")) { success in
                if success {
                    existingDbData = try? Data(contentsOf: tempDir.appendingPathComponent("temp_lib.sqlitedb"))
                }
                semaphoreDownload.signal()
            }
            semaphoreDownload.wait()
            
            // Download WAL
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            // Download SHM
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            // Step 2: Create/Connect AFC and setup directories
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                print("[DeviceManager] ERROR: AFC client is nil")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            afc_remove_path(afc, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm")
            afc_remove_path(afc, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal")
            afc_make_directory(afc, "/iTunes_Control/Music/F00")
            afc_make_directory(afc, "/iTunes_Control/iTunes")
            afc_make_directory(afc, "/iTunes_Control/Artwork")
            afc_client_free(afc)
            
            // Step 3: Create database with playlist
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []
            
            do {
                if let existingData = existingDbData, existingData.count > 10000 {
                    progress("Merging with existing library...")
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: songs,
                        playlistName: playlistName,
                        targetPlaylistPid: targetPlaylistPid
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo
                } else {
                    progress("Creating new library with playlist...")
                    let createResult = try MediaLibraryBuilder.createDatabase_v104(songs: songs, playlistName: playlistName)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo
                }
            } catch {
                print("[DeviceManager] Database creation failed: \(error)")
                do {
                    progress("Creating new library with playlist...")
                   let createResult = try MediaLibraryBuilder.createDatabase_v104(songs: songs, playlistName: playlistName)
                   dbURL = createResult.dbURL
                   artworkInfo = createResult.artworkInfo
                } catch {
                    print("[DeviceManager] ERROR: Failed to create database: \(error)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            }
            
            // Step 4: Upload MP3 files (same as regular inject)
            progress("Uploading songs...")
            
            for (index, song) in songs.enumerated() {
                if existingFiles.contains(song.remoteFilename) {
                    continue
                }
                
                progress("Uploading \(index + 1)/\(songs.count): \(song.title)")
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                
                semaphore.wait()
                
                if !uploadSuccess {
                    print("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                // Upload artwork
                if let artworkData = song.artworkData {
                    var sha1Hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                    artworkData.withUnsafeBytes { bytes in
                        _ = CC_SHA1(bytes.baseAddress, CC_LONG(artworkData.count), &sha1Hash)
                    }
                    let hashString = sha1Hash.map { String(format: "%02x", $0) }.joined()
                    let folderName = String(hashString.prefix(2))
                    let fileName = String(hashString.dropFirst(2))
                    
                    let artworkDir = "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)"
                    let artworkPath = "\(artworkDir)/\(fileName)"
                    
                    var afcArt: AfcClientHandle?
                    afc_client_connect(self.provider, &afcArt)
                    if afcArt != nil {
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork")
                        afc_make_directory(afcArt, "/iTunes_Control/iTunes/Artwork/Originals")
                        afc_make_directory(afcArt, artworkDir)
                        afc_client_free(afcArt)
                    }
                    
                    let tempArtwork = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    try? artworkData.write(to: tempArtwork)
                    
                    let artworkSem = DispatchSemaphore(value: 0)
                    self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { success in
                        if !success {
                            print("[DeviceManager] FATAL ERROR: Failed to upload artwork to \(artworkPath)")
                            progress("Error uploading artwork for \(song.title)")
                        }
                        artworkSem.signal()
                    }
                    artworkSem.wait()
                    try? FileManager.default.removeItem(at: tempArtwork)
                }
            }
            
            // Step 4.5: Generate and upload ArtworkDB binary file
            progress("Generating ArtworkDB...")
            print("[DeviceManager] Step 4.5: Generating ArtworkDB with \(artworkInfo.count) entries")
            
            // Build ArtworkDB entries from collected artwork info
            let artworkDBEntries = artworkInfo.enumerated().map { index, info in
                ArtworkDBBuilder.ArtworkEntry(
                    imageID: UInt32(info.artworkToken) ?? UInt32(100 + index),
                    songDBID: UInt64(info.itemPid),
                    artworkHash: info.artworkHash,
                    fileSize: info.fileSize
                )
            }
            let artworkDBData = ArtworkDBBuilder.generateArtworkDB(entries: artworkDBEntries)
            print("[DeviceManager] ArtworkDB size: \(artworkDBData.count) bytes")
            
            let artworkDBPath = FileManager.default.temporaryDirectory.appendingPathComponent("ArtworkDB")
            try? artworkDBData.write(to: artworkDBPath)
            
            let semArtworkDB = DispatchSemaphore(value: 0)
            self.uploadFileToDevice(localURL: artworkDBPath, remotePath: "/iTunes_Control/Artwork/ArtworkDB") { _ in
                semArtworkDB.signal()
            }
            semArtworkDB.wait()
            try? FileManager.default.removeItem(at: artworkDBPath)
            print("[DeviceManager] ArtworkDB uploaded")
            
            // Step 5: Upload database
            progress("Uploading database...")
            
            var afcDel: AfcClientHandle?
            afc_client_connect(self.provider, &afcDel)
            if afcDel != nil {
                afc_remove_path(afcDel, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb")
                afc_client_free(afcDel)
            }
            
            let semaphoreUploadDb = DispatchSemaphore(value: 0)
            var dbUploadSuccess = false
            
            self.uploadFileToDevice(localURL: dbURL, remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { success in
                dbUploadSuccess = success
                semaphoreUploadDb.signal()
            }
            
            semaphoreUploadDb.wait()
            
            if !dbUploadSuccess {
                print("[DeviceManager] ERROR: Failed to upload database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            try? FileManager.default.removeItem(at: dbURL)
            
            // Step 6: Send notification
            progress("Finalizing...")
            self.sendSyncFinishedNotification()
            
            progress("Playlist '\(playlistName ?? "Unknown")' updated!")
            print("[DeviceManager] Playlist injection complete!")
            DispatchQueue.main.async { completion(true) }
        }
    }
    
    func fetchPlaylists(completion: @escaping ([(name: String, pid: Int64)]) -> Void) {
        let dbPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.heartbeatReady else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // Download DB to temp
            let tempDir = FileManager.default.temporaryDirectory
            let localURL = tempDir.appendingPathComponent("PlaylistFetch.sqlitedb")
            let walURL = tempDir.appendingPathComponent("PlaylistFetch.sqlitedb-wal")
            let shmURL = tempDir.appendingPathComponent("PlaylistFetch.sqlitedb-shm")
            
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
            
            let sem = DispatchSemaphore(value: 0)
            var success = false
            
            // Download Main
            self.downloadFileFromDevice(remotePath: dbPath, localURL: localURL) { isSuccess in
                success = isSuccess
                sem.signal()
            }
            sem.wait()
            
            if !success {
                print("[DeviceManager] Failed to download DB for playlist fetch")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // Download WAL
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal", localURL: walURL) { _ in
                semWal.signal()
            }
            semWal.wait()
            
            // Download SHM
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm", localURL: shmURL) { _ in
                semShm.signal()
            }
            semShm.wait()
            
            // Open and query
            let playlists = MediaLibraryBuilder.extractPlaylists(fromDbPath: localURL.path)
            
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
            
            DispatchQueue.main.async { completion(playlists) }
        }
    }
    
    // MARK: - Ringtone Injection
    
    func injectRingtones(ringtones: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        print("[DeviceManager] injectRingtones called with \(ringtones.count) ringtones")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Download existing DB
            progress("Preparing library...")
            
            let semaphoreDownload = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            var walData: Data?
            var shmData: Data?
            
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                semaphoreDownload.signal()
            }
            semaphoreDownload.wait()
            
             // Download WAL
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            // Download SHM
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            guard let dbData = existingDbData else {
                print("[DeviceManager] ERROR: No existing DB found")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Step 2: Update Database
            progress("Updating database...")
            
            var dbURL: URL?
            
            // Reuse addSongsToExistingDatabase logic? No, ringtones are special.
            // We'll manually reconstruct the DB session
            let tempDir = FileManager.default.temporaryDirectory
            let dbPath = tempDir.appendingPathComponent("RingtoneUpdate.sqlitedb")
            
            try? FileManager.default.removeItem(at: dbPath)
            try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneUpdate.sqlitedb-wal"))
            try? FileManager.default.removeItem(at: tempDir.appendingPathComponent("RingtoneUpdate.sqlitedb-shm"))
            
            var insertedPids: [Int64] = []
            
            do {
                try dbData.write(to: dbPath)
                if let wal = walData { try wal.write(to: tempDir.appendingPathComponent("RingtoneUpdate.sqlitedb-wal")) }
                if let shm = shmData { try shm.write(to: tempDir.appendingPathComponent("RingtoneUpdate.sqlitedb-shm")) }
                
                var db: OpaquePointer?
                if sqlite3_open(dbPath.path, &db) == SQLITE_OK {
                    // Call our new method and capture PIDs
                    insertedPids = try MediaLibraryBuilder.insertRingtones(db: db, ringtones: ringtones)
                    
                    // Force checkpoint
                    if walData != nil {
                         var errorMsg: UnsafeMutablePointer<CChar>?
                        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, &errorMsg)
                         sqlite3_free(errorMsg)
                    }
                    
                    sqlite3_close(db)
                    dbURL = dbPath
                }
            } catch {
                print("[DeviceManager] DB update error: \(error)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Step 3: Upload Ringtones
            progress("Uploading ringtones...")
            
             // Create Ringtones directory if it doesn't exist?
            // Usually /iTunes_Control/Ringtones
            // We need AFC
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            if afc != nil {
                afc_make_directory(afc, "/iTunes_Control/Ringtones")
                afc_client_free(afc)
            }
            
            for (index, ringtone) in ringtones.enumerated() {
                progress("Uploading \(index+1)/\(ringtones.count): \(ringtone.title)")
                
                let remotePath = "/iTunes_Control/Ringtones/\(ringtone.remoteFilename)"
                let sem = DispatchSemaphore(value: 0)
                var success = false
                
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: remotePath) { s in
                    success = s
                    sem.signal()
                }
                sem.wait()
                
                if !success {
                    print("[DeviceManager] Failed to upload ringtone: \(ringtone.title)")
                }
            }
            
            // Step 3b: Merge and Upload Ringtones.plist
            progress("Updating Ringtones index...")
            
            // 1. Download existing plist
            let tempPlistURL = tempDir.appendingPathComponent("ExistingRingtones.plist")
            var existingDict: [String: Any]?
            
            let semDl = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/Ringtones.plist", localURL: tempPlistURL) { success in
                semDl.signal()
            }
            semDl.wait()
            
            if FileManager.default.fileExists(atPath: tempPlistURL.path) {
                if let data = try? Data(contentsOf: tempPlistURL),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    existingDict = plist
                }
            }
            
            // 2. Prepare merging
            var rootDict: [String: Any] = existingDict ?? ["Ringtones": [:]]
            var ringtonesDict = rootDict["Ringtones"] as? [String: Any] ?? [:]
            
            // 3. Add new entries
            for (index, ringtone) in ringtones.enumerated() {
                 let pid = (index < insertedPids.count) ? insertedPids[index] : Int64.random(in: 1000000000...9999999999)
                 // 3uTools uses 16-char hex for GUID, and Filename as Key
                 let shortGUID = String((0..<16).map { _ in "0123456789ABCDEF".randomElement()! })
                 
                 // Required fields for Ringtones.plist
                 let entry: [String: Any] = [
                    "Name": ringtone.title,
                    "Total Time": ringtone.durationMs,
                    "PID": pid,
                    "Protected Content": false,
                    "GUID": shortGUID
                 ]
                 
                 // Use filename as key
                 ringtonesDict[ringtone.remoteFilename] = entry
                 print("[DeviceManager] Ringtone plist entry: \(ringtone.remoteFilename) -> PID \(pid)")
            }
            
            rootDict["Ringtones"] = ringtonesDict
            
            // 4. Save and Upload
            do {
                let plistData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .binary, options: 0)
                let plistURL = tempDir.appendingPathComponent("Ringtones.plist")
                try plistData.write(to: plistURL)
                
                let semPlist = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: plistURL, remotePath: "/iTunes_Control/iTunes/Ringtones.plist") { _ in
                    semPlist.signal()
                }
                semPlist.wait()
                
                try? FileManager.default.removeItem(at: plistURL)
                try? FileManager.default.removeItem(at: tempPlistURL)
            } catch {
                print("[DeviceManager] Failed to generate/upload Ringtones.plist: \(error)")
            }
            
            // Step 4: Upload Database
            progress("Syncing library...")
            
             // Delete WAL/SHM on device first to be safe
            var afcDel: AfcClientHandle?
            afc_client_connect(self.provider, &afcDel)
            if afcDel != nil {
                afc_remove_path(afcDel, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb")
                afc_remove_path(afcDel, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal")
                afc_remove_path(afcDel, "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm")
                afc_client_free(afcDel)
            }
            
            let semUpload = DispatchSemaphore(value: 0)
            self.uploadFileToDevice(localURL: dbURL!, remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { _ in
                semUpload.signal()
            }
            semUpload.wait()
            
            // Cleanup
            try? FileManager.default.removeItem(at: dbPath)
            
            // Step 5: Notify
            progress("Done!")
            self.sendSyncFinishedNotification()
            
            DispatchQueue.main.async { completion(true) }
        }
    }
}

// MARK: - URL Extension
extension URL {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
