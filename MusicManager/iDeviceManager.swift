import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3


typealias IdevicePairingFile = OpaquePointer
typealias IdeviceProviderHandle = OpaquePointer
typealias HeartbeatClientHandle = OpaquePointer
typealias AfcClientHandle = OpaquePointer
typealias AfcFileHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

typealias IdeviceErrorCode = UnsafeMutablePointer<IdeviceFfiError>?

let IdeviceSuccess: IdeviceErrorCode = nil


private let BUILD_VERSION = "v1.0.8-DEBUG"

class DeviceManager: ObservableObject {
    @Published var heartbeatReady: Bool = false
    @Published var connectionStatus: String = "Disconnected"
    var provider: IdeviceProviderHandle?
    var heartbeatThread: Thread?
    
    static var shared = DeviceManager()
    
    
    static let appGroupID = "group.com.edualexxis.MusicManager"
    
    var pairingFile: URL {
        let base: URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            base = containerURL
        } else {
            base = URL.documentsDirectory
        }
        return base.appendingPathComponent("pairing file").appendingPathComponent("pairingFile.plist")
    }
    
    
    static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
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
        
        let folderPath = self.pairingFile.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: folderPath.path) {
                try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)
                Logger.shared.log("[DeviceManager] Created pairing file directory at: \(folderPath.path)")
            }
        } catch {
            Logger.shared.log("[DeviceManager] Error creating pairing directory: \(error)")
        }
    }
    
    
    
    func startHeartbeat(completion: ((Bool) -> Void)? = nil) {
        
        
        heartbeatThread = Thread {
            DispatchQueue.main.async {
                self.connectionStatus = "Connecting..."
            }
            
            self.establishHeartbeat { success in
                DispatchQueue.main.async {
                    if success {
                        
                        self.connectionStatus = "Connection Lost"
                        self.heartbeatReady = false
                    } else {
                        
                        self.connectionStatus = "Connection Failed"
                        self.heartbeatReady = false
                    }
                }
            }
        }
        heartbeatThread?.name = "HeartbeatThread"
        heartbeatThread?.start()
        
        if let completion = completion {
            DispatchQueue.global().async {
                
                for _ in 0..<20 {
                    if self.heartbeatReady {
                        DispatchQueue.main.async { completion(true) }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
                DispatchQueue.main.async { completion(false) }
            }
        }
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
            Logger.shared.log("[DeviceManager] ERROR: Provider is nil. Err: \(String(describing: providerErr))")
            completion(false)
            return
        }
        
        var hbClient: HeartbeatClientHandle?
        let err = heartbeat_connect(provider, &hbClient)
        
        if err == IdeviceSuccess && hbClient != nil {
            Logger.shared.log("[DeviceManager] Heartbeat connected successfully!")
            
            DispatchQueue.main.async {
                self.connectionStatus = "Connected"
                self.heartbeatReady = true
            }
            
            
            while true {
                var newInterval: UInt64 = 0
                
                heartbeat_get_marco(hbClient, 10, &newInterval)
                
                heartbeat_send_polo(hbClient)
                
                DispatchQueue.main.async {
                    if !self.heartbeatReady {
                         self.heartbeatReady = true
                         self.connectionStatus = "Connected"
                    }
                }
                
                
                Thread.sleep(forTimeInterval: 5)
            }
            
            
            heartbeat_client_free(hbClient)
            completion(true) 
        } else {
            Logger.shared.log("[DeviceManager] ERROR: Heartbeat connection failed")
            completion(false)
        }
    }

    

    
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
                
                completion(true)
            } else {
                print("[DeviceManager] Failed to get ATC port")
                completion(false)
            }
        }
    }
    
    
    

    func addSongToDevice(localURL: URL, filename: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] addSongToDevice called for: \(filename)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
            Logger.shared.log("[DeviceManager] Security scoped access needed: \(needsSecurityScope)")
            defer {
                if needsSecurityScope {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            
            Logger.shared.log("[DeviceManager] File exists: \(FileManager.default.fileExists(atPath: localURL.path))")

            Logger.shared.log("[DeviceManager] Connecting AFC client...")
            afc_client_connect(self.provider, &afc)
            Logger.shared.log("[DeviceManager] AFC client connected: \(afc != nil)")
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil")
                completion(false)
                return
            }
            
            
            let musicDir = "/iTunes_Control/Music/F00"
            Logger.shared.log("[DeviceManager] Creating directory: \(musicDir)")
            afc_make_directory(afc, musicDir)
            
            let remotePath = "\(musicDir)/\(filename)"
            Logger.shared.log("[DeviceManager] Opening remote file: \(remotePath)")
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            if let data = try? Data(contentsOf: localURL) {
                
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Could not read file data from \(localURL.path)")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
            
            afc_file_close(file)
            afc_client_free(afc)
            
            self.sendSyncFinishedNotification()
            Logger.shared.log("[DeviceManager] addSongToDevice complete")
            completion(true)
        }
    }
    
    
    
    func removeFileFromDevice(remotePath: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] removeFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for deletion")
                completion(false)
                return
            }
            
            
            let err = afc_remove_path(afc, remotePath)
            
            
            afc_client_free(afc)
            completion(err == nil)
        }
    }
    
    
    
    func deleteMediaLibrary(completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] DELETING MEDIA LIBRARY (NUKE)...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            let connectErr = afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for library reset (Error: \(String(describing: connectErr)))")
                completion(false)
                return
            }
            
            
            
            let iTunesPath = "/iTunes_Control/iTunes"
            Logger.shared.log("[DeviceManager] Removing \(iTunesPath) and all contents...")
            
            

            _ = afc_remove_path_and_contents(afc, iTunesPath)
            
            
            Logger.shared.log("[DeviceManager] Recreating \(iTunesPath)...")
            _ = afc_make_directory(afc, iTunesPath)
            
            
             _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
             _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            
            afc_client_free(afc)

            
            self.sendSyncFinishedNotification()
            Logger.shared.log("[DeviceManager] Library nuke complete.")
            completion(true)
        }
    }
    
    private func cleanUpOrphanedFiles(validFilenames: Set<String>, completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] GC: Failed to connect AFC")
                completion(0)
                return
            }
            
            let musicDir = "/iTunes_Control/Music/F00"
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, musicDir, &entries, &count)
            
            var deletedCount = 0
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let filename = String(cString: ptr)
                        if filename != "." && filename != ".." {
                            // If file on disk is NOT in the database (validFilenames), delete it.
                            if !validFilenames.contains(filename) {
                                let path = "\(musicDir)/\(filename)"
                                Logger.shared.log("[DeviceManager] GC: Deleting orphan -> \(filename)")
                                afc_remove_path(afc, path)
                                deletedCount += 1
                            }
                        }
                    }
                }
                free(entries)
            }
            
            afc_client_free(afc)
            completion(deletedCount)
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
                Logger.shared.log("[DeviceManager] Error writing downloaded file: \(error)")
                completion(false)
            }
        }
    }
    
    
    func downloadFileFromDevice(remotePath: String, completion: @escaping (Data?) -> Void) {
        Logger.shared.log("[DeviceManager] downloadFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            var file: AfcFileHandle?
            
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for download")
                completion(nil)
                return
            }
            
            
            afc_file_open(afc, remotePath, AfcRdOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] File does not exist or cannot be opened: \(remotePath)")
                afc_client_free(afc)
                completion(nil)
                return
            }
            
            
            var dataPtr: UnsafeMutablePointer<UInt8>?
            var length: Int = 0
            
            let err = afc_file_read(file, &dataPtr, &length)
            
            if err == nil, let dataPtr = dataPtr, length > 0 {
                let data = Data(bytes: dataPtr, count: length)
                Logger.shared.log("[DeviceManager] Downloaded \(length) bytes from \(remotePath)")
                afc_file_read_data_free(dataPtr, length)
                afc_file_close(file)
                afc_client_free(afc)
                completion(data)
            } else {
                Logger.shared.log("[DeviceManager] Failed to read file: \(remotePath)")
                afc_file_close(file)
                afc_client_free(afc)
                completion(nil)
            }
        }
    }
    
    
    
    func uploadFileToDevice(localURL: URL, remotePath: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] uploadFileToDevice called: \(localURL.lastPathComponent) -> \(remotePath)")
        
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
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for upload")
                completion(false)
                return
            }
            
            
            let parentDir = (remotePath as NSString).deletingLastPathComponent
            afc_make_directory(afc, parentDir)

            // Force delete existing file to prevent appending/stitching
            afc_remove_path(afc, remotePath)
            
            afc_file_open(afc, remotePath, AfcWrOnly, &file)
            
            guard file != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file: \(remotePath)")
                afc_client_free(afc)
                completion(false)
                return
            }
            
            
            if let data = try? Data(contentsOf: localURL) {
                
                data.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        afc_file_write(file, base, data.count)
                    }
                }
                
                
                afc_file_close(file)
                
                
                var checkFile: AfcFileHandle?
                let ret = afc_file_open(afc, remotePath, AfcRdOnly, &checkFile)
                if ret == nil { 
                    if checkFile != nil {
                        afc_file_close(checkFile)
                    }
                    afc_client_free(afc)
                    completion(true)
                } else {
                    Logger.shared.log("[DeviceManager] ERROR: Verification failed for \(remotePath)")
                    afc_client_free(afc)
                    completion(false)
                }
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Could not read file data")
                afc_file_close(file)
                afc_client_free(afc)
                completion(false)
                return
            }
        }
    }
    
    
    
    func listFiles(remotePath: String, completion: @escaping ([String]?) -> Void) {
        Logger.shared.log("[DeviceManager] listFiles called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for listFiles")
                completion(nil)
                return
            }
            
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, remotePath, &entries, &count)
            
            var files: [String] = []
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let name = String(cString: ptr)
                        if name != "." && name != ".." {
                            files.append(name)
                        }
                    }
                }
                
                free(entries) 
            } else {
                Logger.shared.log("[DeviceManager] Error reading directory or empty: \(remotePath)")
            }
            
            afc_client_free(afc)
            completion(files)
        }
    }
    
    
    
    func injectSongs(songs: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectSongs called with \(songs.count) songs")

        var validSongs: [SongMetadata] = []
        
        let isBatch = songs.count > 1
        
        for var song in songs {
            
            if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filename = song.localURL.lastPathComponent
                Logger.shared.log("[DeviceManager] Sanitize: Empty title for '\(filename)', using filename.")
                song.title = filename
            }
            
            
            if song.artist.isEmpty { song.artist = "Unknown Artist" }
            if song.album.isEmpty { song.album = "Unknown Album" }
            
            
            if isBatch {
                if song.title == "Broken Heart" {
                    Logger.shared.log("[DeviceManager] Batch Mode: Skipping 'Broken Heart'")
                    continue
                }
                if song.artist == "Unknown Artist" && song.album == "Unknown Album" {
                    Logger.shared.log("[DeviceManager] Batch Mode: Skipping Unknown song '\(song.title)'")
                    continue
                }
            }
            
            validSongs.append(song)
        }
        
        Logger.shared.log("[DeviceManager] Processing \(validSongs.count) songs (Sanitized).")
        
        if validSongs.isEmpty {
            Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs found.")
            DispatchQueue.main.async { completion(true) }
            return
        }
        

        DispatchQueue.global(qos: .userInitiated).async {
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in /iTunes_Control/Music/F00")
            var onDeviceFiles: Set<String> = []
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: "/iTunes_Control/Music/F00") { files in
                if let f = files {
                    onDeviceFiles = Set(f)
                }
                semFiles.signal()
            }
            semFiles.wait()
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
            semaphoreDownload.wait()
            
            
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            
            progress("Setting up directories...")
            Logger.shared.log("[DeviceManager] Step 2: Setting up directories")
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            
            
            afc_make_directory(afc, "/iTunes_Control")
            afc_make_directory(afc, "/iTunes_Control/Music")
            afc_make_directory(afc, "/iTunes_Control/Music/F00")
            afc_make_directory(afc, "/iTunes_Control/iTunes")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Caches")
            afc_make_directory(afc, "/iTunes_Control/Artwork")
            Logger.shared.log("[DeviceManager] Step 2: Directories created")
            
            afc_client_free(afc)
            
            
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []
            
            do {
                
                if let existingData = existingDbData, existingData.count > 10000 {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs,
                        existingOnDeviceFiles: onDeviceFiles
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo
                    
                    Logger.shared.log("[DeviceManager] Existing files on device: \(existingFiles.count), artwork entries: \(artworkInfo.count)")
                } else {
                    if existingDbData != nil {
                        Logger.shared.log("[DeviceManager] Existing database too small (\(existingDbData!.count) bytes), creating fresh")
                    }
                    
                    progress("Creating new library...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database")
                    let createResult = try MediaLibraryBuilder.createDatabase_v104(songs: validSongs)
                    dbURL = createResult.dbURL
                    artworkInfo = createResult.artworkInfo
                }
            } catch {
                
                
                Logger.shared.log("[DeviceManager] ⚠️ MERGE FAILED: \(error)")
                Logger.shared.log("[DeviceManager] Aborting to preserve existing library. User should restart their iPhone and try again.")
                progress("Error: Could not merge. Restart iPhone and retry.")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading songs...")
            Logger.shared.log("[DeviceManager] Step 4: Uploading MP3 files")
            
            var uploadedCount = 0
            var skippedCount = 0
            
            
            for (index, song) in validSongs.enumerated() {
                
                if existingFiles.contains(song.remoteFilename) {
                    Logger.shared.log("[DeviceManager] Skipping (already exists): \(song.title)")
                    skippedCount += 1
                    continue
                }
                
                progress("Uploading \(index + 1)/\(validSongs.count): \(song.title)")
                
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                
                semaphore.wait()
                
                if !uploadSuccess {
                    Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                uploadedCount += 1
                
                
                
                if let artworkData = song.artworkData, index < artworkInfo.count {
                    let info = artworkInfo[index]
                    let artworkRelativePath = info.artworkHash  
                    
                    let pathComponents = artworkRelativePath.components(separatedBy: "/")
                    let folderName = pathComponents.count >= 1 ? pathComponents[0] : "00"
                    let fileName = pathComponents.count >= 2 ? pathComponents[1] : "unknown"
                    
                    let artworkDir = "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)"
                    let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                    
                    Logger.shared.log("[DeviceManager] Uploading artwork for: \(song.title) -> \(artworkPath)")
                    
                    
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
                    self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { _ in
                        artworkSem.signal()
                    }
                    artworkSem.wait()
                    
                    try? FileManager.default.removeItem(at: tempArtwork)
                    print("[DeviceManager] Artwork uploaded to: \(artworkPath)")
                }
            }
            
            print("[DeviceManager] Uploaded: \(uploadedCount), Skipped: \(skippedCount)")
            
            
            
            Logger.shared.log("[DeviceManager] Step 4.5: ArtworkDB generation SKIPPED - iOS handles artwork internally")

            
            
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
            semUploadDB.wait()
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var afcSwap: AfcClientHandle?
            afc_client_connect(self.provider, &afcSwap)
            
            guard afcSwap != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to connect AFC for atomic swap")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            afc_remove_path(afcSwap, shmPath)
            afc_remove_path(afcSwap, walPath)
            
            
            afc_remove_path(afcSwap, finalDBPath)
            
            
            let renameErr = afc_rename_path(afcSwap, tempDBPath, finalDBPath)
            
            if renameErr != nil {
                Logger.shared.log("[DeviceManager] ERROR: Failed to rename database (Error: \(renameErr!))")
                 
                 afc_remove_path(afcSwap, tempDBPath)
                 afc_client_free(afcSwap)
                 DispatchQueue.main.async { completion(false) }
                 return
            }
            
            Logger.shared.log("[DeviceManager] Database swapped successfully.")
            afc_client_free(afcSwap)
            
            
            
            progress("Finalizing...")
            Logger.shared.log("[DeviceManager] Step 6: Garbage Collection")
            
            // CRITICAL FIX: Ensure BOTH existing files AND newly added files are protected from GC
            let newFilenames = validSongs.map { $0.remoteFilename }
            let allValidFiles = existingFiles.union(newFilenames)
            
            Logger.shared.log("[DeviceManager] GC Whitelist: \(allValidFiles.count) files (Old: \(existingFiles.count), New: \(newFilenames.count))")

            self.cleanUpOrphanedFiles(validFilenames: allValidFiles) { deletedCount in
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
        
            var validSongs: [SongMetadata] = []
        for var song in songs {
            if song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let filename = song.localURL.lastPathComponent
                song.title = filename
            }
            if song.artist.isEmpty { song.artist = "Unknown Artist" }
            if song.album.isEmpty { song.album = "Unknown Album" }
            validSongs.append(song)
        }
        
        if validSongs.isEmpty {
            Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs for playlist.")
            DispatchQueue.main.async { completion(true) }
            return
        }
        

        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in /iTunes_Control/Music/F00")
            var onDeviceFiles: Set<String> = []
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: "/iTunes_Control/Music/F00") { files in
                if let f = files {
                    onDeviceFiles = Set(f)
                }
                semFiles.signal()
            }
            semFiles.wait()
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
            semaphoreDownload.wait()
            
            
            let semWal = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.wait()
            
            let semShm = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.wait()
            
            
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            if afc != nil {
                
                
                
                afc_make_directory(afc, "/iTunes_Control/Music/F00")
                afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
                afc_client_free(afc)
            }
            
            
            var dbURL: URL
            var existingFiles = Set<String>()
            var artworkInfo: [MediaLibraryBuilder.ArtworkInfo] = []

            
            do {
                if let existingData = existingDbData, existingData.count > 10000 {
                    progress("Merging with existing library...")
                    Logger.shared.log("[DeviceManager] Step 3: Merging with existing database (\(existingData.count) bytes)")
                    
                    let result = try MediaLibraryBuilder.addSongsToExistingDatabase(
                        existingDbData: existingData,
                        walData: walData,
                        shmData: shmData,
                        newSongs: validSongs, 
                        playlistName: playlistName,
                        targetPlaylistPid: targetPlaylistPid,
                        existingOnDeviceFiles: onDeviceFiles
                    )
                    dbURL = result.dbURL
                    existingFiles = result.existingFiles
                    artworkInfo = result.artworkInfo

                } else {
                    progress("Creating new library with playlist...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database with playlist")
                    let createResult = try MediaLibraryBuilder.createDatabase_v104(songs: validSongs, playlistName: playlistName)
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
            
            for (index, song) in validSongs.enumerated() {
                
                if existingFiles.contains(song.remoteFilename) {
                    continue
                }
                
                progress("Uploading \(index + 1)/\(validSongs.count): \(song.title)")
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                let remotePath = "/iTunes_Control/Music/F00/\(song.remoteFilename)"
                
                self.uploadFileToDevice(localURL: song.localURL, remotePath: remotePath) { success in
                    uploadSuccess = success
                    semaphore.signal()
                }
                semaphore.wait()
                
                if !uploadSuccess {
                    Logger.shared.log("[DeviceManager] ERROR: Failed to upload \(song.title)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                uploadedCount += 1
                
                

            }
            
            

            
            
            
            var artworkIndex = 0
            
            for song in validSongs {
                 if existingFiles.contains(song.remoteFilename) { continue }
                 
                 
                 if song.artworkData != nil {
                     if artworkIndex < artworkInfo.count {
                         let info = artworkInfo[artworkIndex]
                         let artworkData = song.artworkData!
                         
                         let artworkRelativePath = info.artworkHash
                         let pathComponents = artworkRelativePath.components(separatedBy: "/")
                         let fileName = pathComponents.last ?? "unknown"
                         let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(artworkRelativePath)"
                         
                         let tempArtwork = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                         try? artworkData.write(to: tempArtwork)
                         
                         let semArt = DispatchSemaphore(value: 0)
                         self.uploadFileToDevice(localURL: tempArtwork, remotePath: artworkPath) { _ in semArt.signal() }
                         semArt.wait()
                         try? FileManager.default.removeItem(at: tempArtwork)
                         
                         artworkIndex += 1
                     }
                 }
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
            semUploadDB.wait()
            
            if !dbUploadSuccess {
                Logger.shared.log("[DeviceManager] ERROR: Failed to upload temp database")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var afcSwap: AfcClientHandle?
            afc_client_connect(self.provider, &afcSwap)
            
            guard afcSwap != nil else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to connect AFC for atomic swap")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            afc_remove_path(afcSwap, shmPath)
            afc_remove_path(afcSwap, walPath)
            
            
            afc_remove_path(afcSwap, finalDBPath)
            
            
            let renameErr = afc_rename_path(afcSwap, tempDBPath, finalDBPath)
            
            if renameErr != nil {
                Logger.shared.log("[DeviceManager] ERROR: Failed to rename database (Error: \(renameErr!))")
                 
                 afc_remove_path(afcSwap, tempDBPath)
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
        let dbPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.heartbeatReady else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            var success = false
            var dbData: Data?
            let sem = DispatchSemaphore(value: 0)
            
            self.downloadFileFromDevice(remotePath: dbPath) { data in
                if let data = data {
                    dbData = data
                    success = true
                }
                sem.signal()
            }
            sem.wait()
            
            if !success {
                Logger.shared.log("[DeviceManager] Failed to download DB for playlist fetch")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            
            let tempDB = FileManager.default.temporaryDirectory.appendingPathComponent("PlaylistFetch.sqlitedb")
            do {
                try dbData?.write(to: tempDB)
            } catch {
                 DispatchQueue.main.async { completion([]) }
                 return
            }
            
            let playlists = MediaLibraryBuilder.extractPlaylists(fromDbPath: tempDB.path)
            try? FileManager.default.removeItem(at: tempDB)
            
            DispatchQueue.main.async { completion(playlists) }
        }
    }
    
    
    
    func injectRingtones(ringtones: [SongMetadata], progress: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] injectRingtones called with \(ringtones.count) ringtones")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            
            progress("Preparing ringtones...")
            Logger.shared.log("[DeviceManager] Step 1: Downloading Ringtones.plist")
            
            var rootDict: [String: Any] = [:]
            var ringtonesDict: [String: Any] = [:]
            
            let plistSem = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/Ringtones/Ringtones.plist") { data in
                if let data = data {
                    do {
                        if let dict = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                            rootDict = dict
                            if let r = dict["Ringtones"] as? [String: Any] {
                                ringtonesDict = r
                            }
                        }
                    } catch {
                        Logger.shared.log("[DeviceManager] Failed to parse existing Ringtones.plist: \(error)")
                    }
                }
                plistSem.signal()
            }
            plistSem.wait()
            
            
            progress("Preparing database...")
            let dbSem = DispatchSemaphore(value: 0)
            var existingDbData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                existingDbData = data
                dbSem.signal()
            }
            dbSem.wait()
            
            var dbData: Data
            if let existing = existingDbData {
                dbData = existing
            } else {
                Logger.shared.log("[DeviceManager] No existing DB found. Creating fresh database for Ringtones...")

                Logger.shared.log("[DeviceManager] WARNING: No DB found. Ringtone injection might fail if no library exists.")
                dbData = Data()
            }
            
            
            let tempDir = FileManager.default.temporaryDirectory
            let dbPath = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")
            try? FileManager.default.removeItem(at: dbPath)
            do {
                try dbData.write(to: dbPath)
            } catch {
                Logger.shared.log("[DeviceManager] Failed to write temp DB: \(error)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var db: OpaquePointer?
            if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
                Logger.shared.log("[DeviceManager] Failed to open temp DB")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            var insertedPids: [Int64] = []
            do {
                 insertedPids = try MediaLibraryBuilder.insertRingtones(db: db, ringtones: ringtones)
            } catch {
                Logger.shared.log("[DeviceManager] DB update error: \(error)")
                sqlite3_close(db)
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            sqlite3_close(db)
            
            
            let uploadDbSem = DispatchSemaphore(value: 0)
            var dbSuccess = false
            self.uploadFileToDevice(localURL: dbPath, remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { success in
                dbSuccess = success
                uploadDbSem.signal()
            }
            uploadDbSem.wait()
            
            if !dbSuccess {
                Logger.shared.log("[DeviceManager] Failed to upload modified DB")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            
            progress("Uploading ringtones...")
            
            for (index, ringtone) in ringtones.enumerated() {
                let pid = insertedPids[index]
                let remotePath = "/iTunes_Control/Ringtones/\(ringtone.remoteFilename)"
                
                
                let uploadSem = DispatchSemaphore(value: 0)
                var success = false
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: remotePath) { s in
                    success = s
                    uploadSem.signal()
                }
                uploadSem.wait()
                
                if !success {
                    Logger.shared.log("[DeviceManager] Failed to upload ringtone: \(ringtone.title)")
                }
                
                
                let entry: [String: Any] = [
                    "Name": ringtone.title,
                    "Total Time": ringtone.durationMs, 
                    "PID": pid,
                    "Protected Content": false,
                    "GUID": SongMetadata.generatePersistentId() 
                ]
                ringtonesDict[ringtone.remoteFilename] = entry
                Logger.shared.log("[DeviceManager] Ringtone plist entry: \(ringtone.remoteFilename) -> PID \(pid)")
            }
            
            rootDict["Ringtones"] = ringtonesDict
            
            
            do {
                let plistData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .xml, options: 0)
                let tempPlist = tempDir.appendingPathComponent("Ringtones.plist")
                try plistData.write(to: tempPlist)
                
                let plistUploadSem = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "/iTunes_Control/Ringtones/Ringtones.plist") { _ in
                    plistUploadSem.signal()
                }
                plistUploadSem.wait()
                
            } catch {
                Logger.shared.log("[DeviceManager] Failed to generate/upload Ringtones.plist: \(error)")
            }
            
            
            progress("Done!")
            self.sendSyncFinishedNotification()
            
            DispatchQueue.main.async { completion(true) }
        }
    }
}


extension URL {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
