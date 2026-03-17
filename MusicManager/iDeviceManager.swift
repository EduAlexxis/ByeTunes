import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


typealias IdevicePairingFile = OpaquePointer
typealias IdeviceProviderHandle = OpaquePointer
typealias HeartbeatClientHandle = OpaquePointer
typealias AfcClientHandle = OpaquePointer
typealias AfcFileHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer
typealias NotificationProxyClientHandle = OpaquePointer
typealias CoreDeviceProxyHandle = OpaquePointer
typealias AdapterHandle = OpaquePointer
typealias ReadWriteOpaqueHandle = OpaquePointer
typealias RsdHandshakeHandle = OpaquePointer
typealias AppServiceHandle = OpaquePointer

typealias IdeviceErrorCode = UnsafeMutablePointer<IdeviceFfiError>?

let IdeviceSuccess: IdeviceErrorCode = nil


private let BUILD_VERSION = "v2.0"

class DeviceManager: ObservableObject {
    struct DatabaseSnapshotInfo: Identifiable {
        var id: String { folderName }
        let folderName: String
        let createdAt: Date
        let songCount: Int
    }
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
    
    private var snapshotsDirectoryURL: URL {
        let base = Self.sharedContainerURL ?? URL.documentsDirectory
        return base.appendingPathComponent("db_snapshots", isDirectory: true)
    }
    
    private let snapshotMusicManifestName = "music_files.txt"
    private let snapshotArtworkManifestName = "artwork_paths.txt"
    private let snapshotArtworkDirectory = "Artwork/Originals"
    
    private init() {
        Logger.shared.log("===========================================")
        Logger.shared.log("[DeviceManager] BUILD VERSION: \(BUILD_VERSION)")
        Logger.shared.log("===========================================")
        Logger.shared.log("[DeviceManager] Initializing...")
        let logPath = FileManager.default.temporaryDirectory.appendingPathComponent("idevice-logs.txt").path
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

    private func postRingtoneRefreshNotifications() {
        var npClient: NotificationProxyClientHandle?
        let npErr = notification_proxy_connect(provider, &npClient)
        guard npErr == IdeviceSuccess, let npClient else {
            Logger.shared.log("[RingtoneNotify] Failed to connect notification_proxy")
            return
        }
        defer { notification_proxy_client_free(npClient) }

        let notifications = [
            "com.apple.itunes-mobdev.syncWillStart",
            "com.apple.itunes-mobdev.syncLockRequest",
            "com.apple.itunes-mobdev.syncDidStart",
            "com.apple.itunes-mobdev.syncDidFinish"
        ]

        for name in notifications {
            let result = name.withCString { cName in
                notification_proxy_post(npClient, cName)
            }
            if result == IdeviceSuccess {
                Logger.shared.log("[RingtoneNotify] Posted \(name)")
            } else {
                Logger.shared.log("[RingtoneNotify] Failed posting \(name)")
            }
        }
    }

    var killMusicBeforeInjectEnabled: Bool {
        return UserDefaults.standard.object(forKey: "killMusicBeforeInject") as? Bool ?? true
    }

    private func makeTemporaryProvider(label: String = "Music-Provider-Temp") -> IdeviceProviderHandle? {
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(LOCKDOWN_PORT))
        inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr)

        var pairingPtr: IdevicePairingFile?
        _ = idevice_pairing_file_read(pairingFile.path, &pairingPtr)
        guard pairingPtr != nil else { return nil }

        var temporaryProvider: IdeviceProviderHandle?
        let providerErr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                idevice_tcp_provider_new(sockaddrPointer, pairingPtr, label, &temporaryProvider)
            }
        }
        guard providerErr == IdeviceSuccess, temporaryProvider != nil else {
            return nil
        }
        return temporaryProvider
    }

    private func withTemporaryProvider<T>(
        label: String = "Music-Provider-Temp",
        _ body: (IdeviceProviderHandle?) -> T
    ) -> T {
        guard let tempProvider = makeTemporaryProvider(label: label) else {
            return body(nil)
        }
        defer { idevice_provider_free(tempProvider) }
        return body(tempProvider)
    }

    @discardableResult
    private func terminateMusicAppIfRunning() -> Bool {
        return withTemporaryProvider(label: "Music-Kill") { refreshProvider in
            guard let refreshProvider else { return false }

            var proxy: CoreDeviceProxyHandle?
            let proxyErr = core_device_proxy_connect(refreshProvider, &proxy)
            guard proxyErr == IdeviceSuccess, let proxyHandle = proxy else {
                Logger.shared.log("[MusicKill] CoreDevice proxy unavailable")
                return false
            }

            var rsdPort: UInt16 = 0
            let rsdErr = core_device_proxy_get_server_rsd_port(proxyHandle, &rsdPort)
            guard rsdErr == IdeviceSuccess, rsdPort > 0 else {
                Logger.shared.log("[MusicKill] Failed to resolve RSD port")
                return false
            }

            var adapter: AdapterHandle?
            let adapterErr = core_device_proxy_create_tcp_adapter(proxyHandle, &adapter)
            guard adapterErr == IdeviceSuccess, let adapterHandle = adapter else {
                Logger.shared.log("[MusicKill] Failed to create adapter")
                return false
            }
            defer { adapter_free(adapterHandle) }

            var stream: ReadWriteOpaqueHandle?
            let streamErr = adapter_connect(adapterHandle, rsdPort, &stream)
            guard streamErr == IdeviceSuccess, let streamHandle = stream else {
                Logger.shared.log("[MusicKill] Failed to connect adapter stream")
                return false
            }

            var handshake: RsdHandshakeHandle?
            let hsErr = rsd_handshake_new(streamHandle, &handshake)
            guard hsErr == IdeviceSuccess, let handshakeHandle = handshake else {
                Logger.shared.log("[MusicKill] Failed to create RSD handshake")
                return false
            }
            defer { rsd_handshake_free(handshakeHandle) }

            var appService: AppServiceHandle?
            let appErr = app_service_connect_rsd(adapterHandle, handshakeHandle, &appService)
            guard appErr == IdeviceSuccess, let appServiceHandle = appService else {
                Logger.shared.log("[MusicKill] Failed to connect AppService")
                return false
            }
            defer { app_service_free(appServiceHandle) }

            var processes: UnsafeMutablePointer<ProcessTokenC>?
            var processCount: UInt = 0
            let listErr = app_service_list_processes(appServiceHandle, &processes, &processCount)
            guard listErr == IdeviceSuccess, let processList = processes, processCount > 0 else {
                Logger.shared.log("[MusicKill] No process list available")
                return false
            }
            defer { app_service_free_process_list(processList, processCount) }

            var terminatedAny = false
            for i in 0..<Int(processCount) {
                let token = processList[i]
                guard token.pid != 0 else { continue }
                let exe = token.executable_url.map { String(cString: $0) } ?? ""

                if exe.localizedCaseInsensitiveContains("MusicManager") {
                    continue
                }

                let isAppleMusicProcess =
                    exe.localizedCaseInsensitiveContains("MobileMusicPlayer")
                    || exe.localizedCaseInsensitiveContains("/Music.app/Music")
                    || exe.localizedCaseInsensitiveContains("/Applications/Music.app/")

                guard isAppleMusicProcess else { continue }

                Logger.shared.log("[MusicKill] Targeting Apple Music pid=\(token.pid) exe=\(exe)")

                var signalResp: UnsafeMutablePointer<SignalResponseC>?
                let termErr = app_service_send_signal(appServiceHandle, token.pid, 15, &signalResp)
                if signalResp != nil {
                    app_service_free_signal_response(signalResp)
                }
                if termErr == IdeviceSuccess {
                    terminatedAny = true
                    Logger.shared.log("[MusicKill] Sent SIGTERM to pid=\(token.pid)")
                }

                Thread.sleep(forTimeInterval: 0.25)

                var killResp: UnsafeMutablePointer<SignalResponseC>?
                let killErr = app_service_send_signal(appServiceHandle, token.pid, 9, &killResp)
                if killResp != nil {
                    app_service_free_signal_response(killResp)
                }
                if killErr == IdeviceSuccess {
                    terminatedAny = true
                    Logger.shared.log("[MusicKill] Sent SIGKILL to pid=\(token.pid)")
                }
            }

            return terminatedAny
        }
    }
    
    
    
    
    func getDeviceProductVersion() -> String? {
        var lockdownd: LockdowndClientHandle?
        let err = lockdownd_connect(provider, &lockdownd)
        
        guard err == IdeviceSuccess, let client = lockdownd else {
            return nil
        }
        defer { lockdownd_client_free(client) }
        
        var plist: plist_t?
        let valErr = lockdownd_get_value(client, "ProductVersion", nil, &plist)
        
        guard valErr == IdeviceSuccess, let versionPlist = plist else {
            return nil
        }
        defer { plist_free(versionPlist) }
        
        var cString: UnsafeMutablePointer<CChar>?
        plist_get_string_val(versionPlist, &cString)
        
        if let cString = cString {
            let version = String(cString: cString)
            plist_mem_free(cString)
            return version
        }
        
        return nil
    }
    
    func getDatabaseVersion() -> DatabaseVersion {
        guard let versionString = getDeviceProductVersion() else {
            Logger.shared.log("[DeviceManager] Could not detect version, defaulting to iOS 16/26 schema")
            return .ios(16)
        }
        
        Logger.shared.log("[DeviceManager] Detected device version: \(versionString)")
        let components = versionString.split(separator: ".").compactMap { Int($0) }
        guard let major = components.first else { return .ios(16) }
        
        return .ios(major)
    }

    func triggerATCSync(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var lockdownd: LockdowndClientHandle?
            let err = lockdownd_connect(self.provider, &lockdownd)
            
            guard err == IdeviceSuccess else {
                Logger.shared.log("[DeviceManager] Failed to connect lockdownd for ATC")
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
                Logger.shared.log("[DeviceManager] Failed to get ATC port")
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
            if self.killMusicBeforeInjectEnabled {
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[DeviceManager] Pre-delete Music kill \(killed ? "completed" : "skipped/failed")")
            }

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
    
    func createDatabaseSnapshot(completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Creating database snapshot...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            if self.killMusicBeforeInjectEnabled {
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[Backup] Pre-snapshot Music kill \(killed ? "completed" : "skipped/failed")")
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let stamp = formatter.string(from: Date())
            
            let root = self.snapshotsDirectoryURL
            let folder = root.appendingPathComponent("snapshot_\(stamp)", isDirectory: true)
            
            if let existing = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for entry in existing where entry.hasDirectoryPath && entry.lastPathComponent.hasPrefix("snapshot_") {
                    try? FileManager.default.removeItem(at: entry)
                }
            }
            
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[Backup] Failed creating snapshot folder: \(error)")
                completion(false, "Failed creating snapshot folder")
                return
            }
            
            let files: [(remote: String, local: String, required: Bool)] = [
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb", "MediaLibrary.sqlitedb", true),
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal", "MediaLibrary.sqlitedb-wal", false),
                ("/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm", "MediaLibrary.sqlitedb-shm", false),
                ("/iTunes_Control/Ringtones/Ringtones.plist", "Ringtones.plist", false)
            ]
            
            var saved: [String] = []
            for item in files {
                let localURL = folder.appendingPathComponent(item.local)
                let sem = DispatchSemaphore(value: 0)
                var success = false
                self.downloadFileFromDevice(remotePath: item.remote, localURL: localURL) { ok in
                    success = ok
                    sem.signal()
                }
                sem.wait()
                
                if success {
                    saved.append(item.local)
                    Logger.shared.log("[Backup] Saved \(item.local)")
                } else if item.required {
                    Logger.shared.log("[Backup] Required file missing: \(item.remote)")
                    try? FileManager.default.removeItem(at: folder)
                    completion(false, "Failed: MediaLibrary.sqlitedb unavailable")
                    return
                }
            }
            
            if !saved.contains("MediaLibrary.sqlitedb") {
                Logger.shared.log("[Backup] Snapshot invalid (no DB file)")
                try? FileManager.default.removeItem(at: folder)
                completion(false, "Failed: DB file missing")
                return
            }
            
            let dbLocal = folder.appendingPathComponent("MediaLibrary.sqlitedb")
            let musicFiles = Array(self.musicFilenamesFromDatabase(dbLocal)).sorted()
            self.writeSnapshotManifest(musicFiles, to: folder.appendingPathComponent(self.snapshotMusicManifestName))
            Logger.shared.log("[Backup] Indexed \(musicFiles.count) music filenames for rollback safety")
            
            let artworkPaths = self.artworkPathsFromDatabase(dbLocal)
            self.writeSnapshotManifest(artworkPaths, to: folder.appendingPathComponent(self.snapshotArtworkManifestName))
            Logger.shared.log("[Backup] Indexed \(artworkPaths.count) artwork paths")
            
            let artworkRoot = folder.appendingPathComponent(self.snapshotArtworkDirectory, isDirectory: true)
            var artworkSaved = 0
            if !artworkPaths.isEmpty {
                try? FileManager.default.createDirectory(at: artworkRoot, withIntermediateDirectories: true)
                for relativePath in artworkPaths {
                    let localURL = artworkRoot.appendingPathComponent(relativePath)
                    let localDir = localURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                    
                    let remotePath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
                    let sem = DispatchSemaphore(value: 0)
                    var downloaded = false
                    self.downloadFileFromDevice(remotePath: remotePath, localURL: localURL) { ok in
                        downloaded = ok
                        sem.signal()
                    }
                    sem.wait()
                    
                    if downloaded {
                        artworkSaved += 1
                    } else {
                        try? FileManager.default.removeItem(at: localURL)
                    }
                }
            }
            Logger.shared.log("[Backup] Artwork saved: \(artworkSaved)/\(artworkPaths.count)")
            
            Logger.shared.log("[Backup] Snapshot complete: \(folder.lastPathComponent) (\(saved.count) files)")
            completion(true, "Snapshot created: \(folder.lastPathComponent)")
        }
    }
    
    func restoreLatestDatabaseSnapshot(completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Restoring latest database snapshot...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let root = self.snapshotsDirectoryURL
            let fm = FileManager.default
            
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                completion(false, "No snapshots found")
                return
            }
            
            let snapshotDirs = entries.filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("snapshot_") }
            guard !snapshotDirs.isEmpty else {
                completion(false, "No snapshots found")
                return
            }
            
            let sorted = snapshotDirs.sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lDate > rDate
            }
            
            guard let latest = sorted.first else {
                completion(false, "No snapshots found")
                return
            }
            self.restoreSnapshotDirectory(latest, completion: completion)
        }
    }
    
    func restoreDatabaseSnapshot(named folderName: String, completion: @escaping (Bool, String) -> Void) {
        Logger.shared.log("[Backup] Restoring snapshot: \(folderName)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshotDir = self.snapshotsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: snapshotDir.path) else {
                completion(false, "Snapshot not found")
                return
            }
            self.restoreSnapshotDirectory(snapshotDir, completion: completion)
        }
    }
    
    func deleteDatabaseSnapshot(named folderName: String, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let path = self.snapshotsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
            do {
                try FileManager.default.removeItem(at: path)
                Logger.shared.log("[Backup] Deleted snapshot: \(folderName)")
                completion(true, "Deleted: \(folderName)")
            } catch {
                Logger.shared.log("[Backup] Failed deleting snapshot \(folderName): \(error)")
                completion(false, "Delete failed")
            }
        }
    }
    
    private func restoreSnapshotDirectory(_ snapshotDir: URL, completion: @escaping (Bool, String) -> Void) {
        let fm = FileManager.default
        let dbLocal = snapshotDir.appendingPathComponent("MediaLibrary.sqlitedb")
        guard fm.fileExists(atPath: dbLocal.path) else {
            completion(false, "Snapshot missing MediaLibrary.sqlitedb")
            return
        }
        
        if self.killMusicBeforeInjectEnabled {
            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[Backup] Pre-restore Music kill \(killed ? "completed" : "skipped/failed")")
        }
        
        var afc: AfcClientHandle?
        afc_client_connect(self.provider, &afc)
        guard let afc else {
            completion(false, "AFC connection failed")
            return
        }
        defer { afc_client_free(afc) }
        
        let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
        let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
        let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
        let ringtonePath = "/iTunes_Control/Ringtones/Ringtones.plist"
        
        _ = afc_make_directory(afc, "/iTunes_Control/iTunes")
        _ = afc_make_directory(afc, "/iTunes_Control/Ringtones")
        
        let semUploadDB = DispatchSemaphore(value: 0)
        var dbUploadOK = false
        self.uploadFileToDevice(localURL: dbLocal, remotePath: tempDBPath) { ok in
            dbUploadOK = ok
            semUploadDB.signal()
        }
        semUploadDB.wait()
        
        guard dbUploadOK else {
            completion(false, "Failed uploading snapshot DB")
            return
        }
        
        _ = afc_remove_path(afc, shmPath)
        _ = afc_remove_path(afc, walPath)
        _ = afc_remove_path(afc, finalDBPath)
        
        let renameErr = afc_rename_path(afc, tempDBPath, finalDBPath)
        guard renameErr == nil else {
            Logger.shared.log("[Backup] Rename failed while restoring DB")
            _ = afc_remove_path(afc, tempDBPath)
            completion(false, "Failed swapping restored DB")
            return
        }
        
        let ringtoneLocal = snapshotDir.appendingPathComponent("Ringtones.plist")
        if fm.fileExists(atPath: ringtoneLocal.path) {
            let semRingtone = DispatchSemaphore(value: 0)
            self.uploadFileToDevice(localURL: ringtoneLocal, remotePath: ringtonePath) { _ in
                semRingtone.signal()
            }
            semRingtone.wait()
        }
        
        let artworkRoot = snapshotDir.appendingPathComponent(snapshotArtworkDirectory, isDirectory: true)
        var restoredArtwork = 0
        if fm.fileExists(atPath: artworkRoot.path) {
            _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork")
            _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            
            if let enumerator = fm.enumerator(at: artworkRoot, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    
                    let relative = fileURL.path.replacingOccurrences(of: artworkRoot.path + "/", with: "")
                    guard !relative.isEmpty else { continue }
                    
                    let remote = "/iTunes_Control/iTunes/Artwork/Originals/\(relative)"
                    let semArt = DispatchSemaphore(value: 0)
                    self.uploadFileToDevice(localURL: fileURL, remotePath: remote) { ok in
                        if ok {
                            restoredArtwork += 1
                        }
                        semArt.signal()
                    }
                    semArt.wait()
                }
            }
        }
        Logger.shared.log("[Backup] Restored artwork files: \(restoredArtwork)")
        
        self.sendSyncFinishedNotification()
        Logger.shared.log("[Backup] Restore complete from \(snapshotDir.lastPathComponent)")
        completion(true, "Restored: \(snapshotDir.lastPathComponent)")
    }
    
    private func countSongsInSnapshotDB(_ dbURL: URL) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item WHERE media_type = 8", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
            if count > 0 { return count }
        } else if stmt != nil {
            sqlite3_finalize(stmt)
        }
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        return count
    }
    
    private func musicFilenamesFromDatabase(_ dbURL: URL) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var names = Set<String>()
        
        let sql = """
        SELECT item_extra.location
        FROM item
        INNER JOIN item_extra ON item.item_pid = item_extra.item_pid
        WHERE item.base_location_id = 3840
          AND item.media_type = 8
          AND item_extra.location != ''
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let location = String(cString: ptr)
                    let filename = (location as NSString).lastPathComponent
                    if !filename.isEmpty {
                        names.insert(filename)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        if !names.isEmpty {
            return names
        }
        
        if sqlite3_prepare_v2(db, "SELECT location FROM item_extra WHERE location != ''", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let location = String(cString: ptr)
                    let filename = (location as NSString).lastPathComponent
                    if !filename.isEmpty {
                        names.insert(filename)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        return names
    }
    
    private func artworkPathsFromDatabase(_ dbURL: URL) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        var paths = Set<String>()
        if sqlite3_prepare_v2(db, "SELECT relative_path FROM artwork WHERE relative_path != ''", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    let rel = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rel.isEmpty {
                        paths.insert(rel)
                    }
                }
            }
        }
        if stmt != nil { sqlite3_finalize(stmt) }
        
        return paths.sorted()
    }
    
    private func writeSnapshotManifest(_ lines: [String], to manifestURL: URL) {
        let content = lines.joined(separator: "\n")
        try? content.write(to: manifestURL, atomically: true, encoding: .utf8)
    }
    
    private func loadSnapshotMusicFilenames(snapshotDir: URL) -> Set<String> {
        let manifestURL = snapshotDir.appendingPathComponent(snapshotMusicManifestName)
        if
            let content = try? String(contentsOf: manifestURL, encoding: .utf8),
            !content.isEmpty
        {
            let set = Set(
                content
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            if !set.isEmpty {
                return set
            }
        }
        
        let dbURL = snapshotDir.appendingPathComponent("MediaLibrary.sqlitedb")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [] }
        return musicFilenamesFromDatabase(dbURL)
    }
    
    private func protectedFilenamesFromAllSnapshots() -> Set<String> {
        let fm = FileManager.default
        let root = snapshotsDirectoryURL
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        
        var protectedSet = Set<String>()
        for dir in entries where dir.hasDirectoryPath && dir.lastPathComponent.hasPrefix("snapshot_") {
            let names = loadSnapshotMusicFilenames(snapshotDir: dir)
            if !names.isEmpty {
                protectedSet.formUnion(names)
            }
        }
        return protectedSet
    }
    
    private struct CarrySongDBMetadata {
        let itemPid: Int64
        let title: String
        let artist: String
        let album: String
        let genre: String
        let year: Int
        let durationMs: Int
        let fileSize: Int
        let lyrics: String?
        let artworkRelativePath: String?
    }
    
    private func firstStringQuery(db: OpaquePointer?, sql: String, itemPid: Int64) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, itemPid)
        if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) {
            let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }
    
    private func artworkPathForItemPid(db: OpaquePointer?, itemPid: Int64) -> String? {
        let candidates = [
            """
            SELECT aw.relative_path
            FROM best_artwork_token bat
            JOIN artwork aw ON aw.artwork_token = bat.available_artwork_token
            WHERE bat.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """,
            """
            SELECT aw.relative_path
            FROM best_artwork_token bat
            JOIN artwork aw ON aw.artwork_token = bat.fetchable_artwork_token
            WHERE bat.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """,
            """
            SELECT aw.relative_path
            FROM artwork_token atok
            JOIN artwork aw ON aw.artwork_token = atok.artwork_token
            WHERE atok.entity_pid = ? AND aw.relative_path != ''
            LIMIT 1
            """
        ]
        
        for sql in candidates {
            if let rel = firstStringQuery(db: db, sql: sql, itemPid: itemPid) {
                return rel
            }
        }
        return nil
    }
    
    private func carrySongMetadataMapFromDatabase(_ dbURL: URL) -> [String: CarrySongDBMetadata] {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }
        
        let sql = """
        SELECT
            i.item_pid,
            ie.location,
            ie.title,
            IFNULL(ia.item_artist, ''),
            IFNULL(al.album, ''),
            IFNULL(ge.genre, ''),
            ie.year,
            CAST(ie.total_time_ms AS INTEGER),
            ie.file_size
        FROM item i
        JOIN item_extra ie ON ie.item_pid = i.item_pid
        LEFT JOIN item_artist ia ON ia.item_artist_pid = i.item_artist_pid
        LEFT JOIN album al ON al.album_pid = i.album_pid
        LEFT JOIN genre ge ON ge.genre_id = i.genre_id
        WHERE ie.location != ''
        """
        
        var stmt: OpaquePointer?
        var map: [String: CarrySongDBMetadata] = [:]
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            return [:]
        }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemPid = sqlite3_column_int64(stmt, 0)
            guard let locPtr = sqlite3_column_text(stmt, 1) else { continue }
            let location = String(cString: locPtr)
            let filename = (location as NSString).lastPathComponent
            if filename.isEmpty { continue }
            
            let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let artist = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "Unknown Artist"
            let album = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "Unknown Album"
            let genre = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "Music"
            let year = Int(sqlite3_column_int(stmt, 6))
            let durationMs = Int(sqlite3_column_int(stmt, 7))
            let fileSize = Int(sqlite3_column_int(stmt, 8))
            let lyrics = firstStringQuery(
                db: db,
                sql: "SELECT lyrics FROM lyrics WHERE item_pid = ? LIMIT 1",
                itemPid: itemPid
            )
            let artworkRelativePath = artworkPathForItemPid(db: db, itemPid: itemPid)
            
            map[filename] = CarrySongDBMetadata(
                itemPid: itemPid,
                title: title.isEmpty ? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent : title,
                artist: artist.isEmpty ? "Unknown Artist" : artist,
                album: album.isEmpty ? "Unknown Album" : album,
                genre: genre.isEmpty ? "Music" : genre,
                year: year > 0 ? year : Calendar.current.component(.year, from: Date()),
                durationMs: max(0, durationMs),
                fileSize: max(0, fileSize),
                lyrics: lyrics,
                artworkRelativePath: (artworkRelativePath?.isEmpty == false) ? artworkRelativePath : nil
            )
        }
        
        Logger.shared.log("[Backup] Carry-over metadata map loaded for \(map.count) songs")
        return map
    }
    
    private func buildCarryOverSongsForSnapshotRestore(excluding snapshotFilenames: Set<String>) -> (songs: [SongMetadata], filenames: [String], artworkRelativePaths: [String: String], stagingDir: URL?) {
        let fm = FileManager.default
        
        let semDb = DispatchSemaphore(value: 0)
        var currentDbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            currentDbData = data
            semDb.signal()
        }
        semDb.wait()
        
        guard let currentDbData, currentDbData.count > 10000 else {
            return ([], [], [:], nil)
        }
        
        let semWal = DispatchSemaphore(value: 0)
        var walData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            walData = data
            semWal.signal()
        }
        semWal.wait()
        
        let semShm = DispatchSemaphore(value: 0)
        var shmData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            shmData = data
            semShm.signal()
        }
        semShm.wait()
        
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("restore_carry_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        } catch {
            Logger.shared.log("[Backup] Failed to create carry-over staging dir: \(error)")
            return ([], [], [:], nil)
        }
        
        let dbPath = stagingDir.appendingPathComponent("CurrentMediaLibrary.sqlitedb")
        do {
            try currentDbData.write(to: dbPath)
            if let walData {
                try walData.write(to: stagingDir.appendingPathComponent("CurrentMediaLibrary.sqlitedb-wal"))
            }
            if let shmData {
                try shmData.write(to: stagingDir.appendingPathComponent("CurrentMediaLibrary.sqlitedb-shm"))
            }
        } catch {
            Logger.shared.log("[Backup] Failed to stage current DB for merge capture: \(error)")
            try? fm.removeItem(at: stagingDir)
            return ([], [], [:], nil)
        }
        
        let currentFilenames = musicFilenamesFromDatabase(dbPath)
        let carryFilenames = currentFilenames.subtracting(snapshotFilenames).sorted()
        guard !carryFilenames.isEmpty else {
            return ([], [], [:], stagingDir)
        }
        let metadataMap = carrySongMetadataMapFromDatabase(dbPath)
        
        let carrySongsDir = stagingDir.appendingPathComponent("carry_songs", isDirectory: true)
        try? fm.createDirectory(at: carrySongsDir, withIntermediateDirectories: true)
        let carryArtworkRoot = stagingDir.appendingPathComponent("carry_artwork", isDirectory: true)
        try? fm.createDirectory(at: carryArtworkRoot, withIntermediateDirectories: true)
        
        var songs: [SongMetadata] = []
        var carryArtworkRelativePaths: [String: String] = [:]
        songs.reserveCapacity(carryFilenames.count)
        
        for filename in carryFilenames {
            let localURL = carrySongsDir.appendingPathComponent(filename)
            let remotePath = "/iTunes_Control/Music/F00/\(filename)"
            
            let semDownload = DispatchSemaphore(value: 0)
            var downloaded = false
            self.downloadFileFromDevice(remotePath: remotePath, localURL: localURL) { ok in
                downloaded = ok
                semDownload.signal()
            }
            semDownload.wait()
            
            guard downloaded else {
                Logger.shared.log("[Backup] Carry-over skip: device file missing \(filename)")
                continue
            }
            
            var parsed: SongMetadata?
            let semMeta = DispatchSemaphore(value: 0)
            Task {
                parsed = try? await SongMetadata.fromURL(localURL)
                semMeta.signal()
            }
            semMeta.wait()
            
            if var song = parsed {
                if let dbMeta = metadataMap[filename] {
                    song.title = dbMeta.title
                    song.artist = dbMeta.artist
                    song.album = dbMeta.album
                    song.genre = dbMeta.genre
                    song.year = dbMeta.year
                    song.durationMs = dbMeta.durationMs > 0 ? dbMeta.durationMs : song.durationMs
                    song.fileSize = dbMeta.fileSize > 0 ? dbMeta.fileSize : song.fileSize
                    song.lyrics = dbMeta.lyrics ?? song.lyrics
                    if song.artworkData == nil, let rel = dbMeta.artworkRelativePath {
                        carryArtworkRelativePaths[filename] = rel
                        let semArt = DispatchSemaphore(value: 0)
                        var artData: Data?
                        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/Artwork/Originals/\(rel)") { data in
                            artData = data
                            semArt.signal()
                        }
                        semArt.wait()
                        if let artData {
                            song.artworkData = artData
                            let artLocalURL = carryArtworkRoot.appendingPathComponent(rel)
                            let artDir = artLocalURL.deletingLastPathComponent()
                            try? fm.createDirectory(at: artDir, withIntermediateDirectories: true)
                            try? artData.write(to: artLocalURL)
                        }
                    }
                } else {
                    Logger.shared.log("[Backup] Carry-over metadata fallback to file tags for \(filename)")
                }
                song.remoteFilename = filename
                songs.append(song)
            } else {
                let dbMeta = metadataMap[filename]
                var artData: Data?
                if let rel = dbMeta?.artworkRelativePath {
                    carryArtworkRelativePaths[filename] = rel
                    let semArt = DispatchSemaphore(value: 0)
                    self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/Artwork/Originals/\(rel)") { data in
                        artData = data
                        semArt.signal()
                    }
                    semArt.wait()
                    if let artData {
                        let artLocalURL = carryArtworkRoot.appendingPathComponent(rel)
                        let artDir = artLocalURL.deletingLastPathComponent()
                        try? fm.createDirectory(at: artDir, withIntermediateDirectories: true)
                        try? artData.write(to: artLocalURL)
                    }
                }
                let fallbackTitle = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                let fileSize = (try? fm.attributesOfItem(atPath: localURL.path)[.size] as? Int) ?? 0
                songs.append(
                    SongMetadata(
                        localURL: localURL,
                        title: dbMeta?.title ?? fallbackTitle,
                        artist: dbMeta?.artist ?? "Unknown Artist",
                        album: dbMeta?.album ?? "Unknown Album",
                        albumArtist: nil,
                        genre: dbMeta?.genre ?? "Music",
                        year: dbMeta?.year ?? Calendar.current.component(.year, from: Date()),
                        durationMs: dbMeta?.durationMs ?? 0,
                        fileSize: dbMeta?.fileSize ?? fileSize,
                        remoteFilename: filename,
                        artworkData: artData,
                        lyrics: dbMeta?.lyrics
                    )
                )
            }
        }
        
        return (songs, carryFilenames, carryArtworkRelativePaths, stagingDir)
    }
    
    private func mergeSongsIntoDeviceDatabase(_ songs: [SongMetadata]) -> Bool {
        guard !songs.isEmpty else { return true }
        
        var onDeviceFiles = Set<String>()
        let semFiles = DispatchSemaphore(value: 0)
        self.listFiles(remotePath: "/iTunes_Control/Music/F00") { files in
            if let files {
                onDeviceFiles = Set(files)
            }
            semFiles.signal()
        }
        semFiles.wait()
        
        let semDb = DispatchSemaphore(value: 0)
        var dbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            semDb.signal()
        }
        semDb.wait()
        guard let dbData, dbData.count > 10000 else {
            Logger.shared.log("[Backup] Merge failed: current DB unavailable")
            return false
        }
        
        let semWal = DispatchSemaphore(value: 0)
        var walData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            walData = data
            semWal.signal()
        }
        semWal.wait()
        
        let semShm = DispatchSemaphore(value: 0)
        var shmData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            shmData = data
            semShm.signal()
        }
        semShm.wait()
        
        let mergedResult: (dbURL: URL, existingFiles: Set<String>, artworkInfo: [MediaLibraryBuilder.ArtworkInfo], pids: [Int64])
        do {
            mergedResult = try MediaLibraryBuilder.addSongsToExistingDatabase(
                existingDbData: dbData,
                walData: walData,
                shmData: shmData,
                newSongs: songs,
                existingOnDeviceFiles: onDeviceFiles,
                version: getDatabaseVersion()
            )
        } catch {
            Logger.shared.log("[Backup] Merge failed while building DB: \(error)")
            return false
        }
        
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
        let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
        let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
        
        let semUpload = DispatchSemaphore(value: 0)
        var uploaded = false
        self.uploadFileToDevice(localURL: mergedResult.dbURL, remotePath: tempDBPath) { ok in
            uploaded = ok
            semUpload.signal()
        }
        semUpload.wait()
        
        guard uploaded else {
            Logger.shared.log("[Backup] Merge failed: could not upload merged DB")
            return false
        }
        
        var afc: AfcClientHandle?
        afc_client_connect(self.provider, &afc)
        guard let afc else {
            Logger.shared.log("[Backup] Merge failed: AFC unavailable for swap")
            return false
        }
        defer { afc_client_free(afc) }
        
        _ = afc_remove_path(afc, shmPath)
        _ = afc_remove_path(afc, walPath)
        _ = afc_remove_path(afc, finalDBPath)
        
        let renameErr = afc_rename_path(afc, tempDBPath, finalDBPath)
        if renameErr != nil {
            Logger.shared.log("[Backup] Merge failed: atomic swap rename failed")
            _ = afc_remove_path(afc, tempDBPath)
            return false
        }
        
        return true
    }
    
    private func sqliteExec(_ db: OpaquePointer?, _ sql: String) -> Bool {
        var errorMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if rc != SQLITE_OK {
            if let msg = errorMsg {
                Logger.shared.log("[Backup] SQLite exec warning: \(String(cString: msg))")
                sqlite3_free(errorMsg)
            }
            return false
        }
        return true
    }
    
    private func mergeCarryOverRowsFromSourceDB(sourceDbURL: URL, carryFilenames: [String]) -> Bool {
        guard !carryFilenames.isEmpty else { return true }
        
        let semDb = DispatchSemaphore(value: 0)
        var dstDbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dstDbData = data
            semDb.signal()
        }
        semDb.wait()
        guard let dstDbData, dstDbData.count > 10000 else {
            Logger.shared.log("[Backup] Row-merge failed: destination DB unavailable")
            return false
        }
        
        let semWal = DispatchSemaphore(value: 0)
        var dstWal: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
            dstWal = data
            semWal.signal()
        }
        semWal.wait()
        
        let semShm = DispatchSemaphore(value: 0)
        var dstShm: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
            dstShm = data
            semShm.signal()
        }
        semShm.wait()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("restore_rowmerge_\(UUID().uuidString)", isDirectory: true)
        let dstDbURL = tempDir.appendingPathComponent("MergedMediaLibrary.sqlitedb")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try dstDbData.write(to: dstDbURL)
            if let dstWal {
                try dstWal.write(to: tempDir.appendingPathComponent("MergedMediaLibrary.sqlitedb-wal"))
            }
            if let dstShm {
                try dstShm.write(to: tempDir.appendingPathComponent("MergedMediaLibrary.sqlitedb-shm"))
            }
        } catch {
            Logger.shared.log("[Backup] Row-merge staging failed: \(error)")
            return false
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        var db: OpaquePointer?
        guard sqlite3_open(dstDbURL.path, &db) == SQLITE_OK else {
            Logger.shared.log("[Backup] Row-merge failed: cannot open destination DB")
            return false
        }
        defer { sqlite3_close(db) }
        
        _ = sqliteExec(db, "PRAGMA foreign_keys=OFF")
        _ = sqliteExec(db, "ATTACH DATABASE '\(sourceDbURL.path.replacingOccurrences(of: "'", with: "''"))' AS src")
        _ = sqliteExec(db, "CREATE TEMP TABLE carry_filenames (filename TEXT PRIMARY KEY)")
        
        var insertLocStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO carry_filenames(filename) VALUES (?)", -1, &insertLocStmt, nil) == SQLITE_OK {
            for filename in carryFilenames {
                sqlite3_bind_text(insertLocStmt, 1, filename, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(insertLocStmt)
                sqlite3_reset(insertLocStmt)
                sqlite3_clear_bindings(insertLocStmt)
            }
        }
        if insertLocStmt != nil { sqlite3_finalize(insertLocStmt) }
        
        _ = sqliteExec(db, """
        CREATE TEMP TABLE src_pids AS
        SELECT DISTINCT ie.item_pid
        FROM src.item_extra ie
        JOIN carry_filenames cf
          ON ie.location = cf.filename
          OR ie.location LIKE '%/' || cf.filename
        """)
        _ = sqliteExec(db, """
        CREATE TEMP TABLE dst_pids AS
        SELECT DISTINCT ie.item_pid
        FROM item_extra ie
        JOIN carry_filenames cf
          ON ie.location = cf.filename
          OR ie.location LIKE '%/' || cf.filename
        """)
        
        for table in ["item","item_extra","item_playback","item_stats","item_store","item_video","item_search","lyrics","chapter"] {
            _ = sqliteExec(db, "DELETE FROM \(table) WHERE item_pid IN (SELECT item_pid FROM dst_pids)")
        }
        
        _ = sqliteExec(db, "INSERT OR REPLACE INTO sort_map SELECT * FROM src.sort_map")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO item_artist SELECT * FROM src.item_artist WHERE item_artist_pid IN (SELECT DISTINCT item_artist_pid FROM src.item WHERE item_pid IN (SELECT item_pid FROM src_pids))")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO album_artist SELECT * FROM src.album_artist WHERE album_artist_pid IN (SELECT DISTINCT album_artist_pid FROM src.item WHERE item_pid IN (SELECT item_pid FROM src_pids))")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO album SELECT * FROM src.album WHERE album_pid IN (SELECT DISTINCT album_pid FROM src.item WHERE item_pid IN (SELECT item_pid FROM src_pids))")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO genre SELECT * FROM src.genre WHERE genre_id IN (SELECT DISTINCT genre_id FROM src.item WHERE item_pid IN (SELECT item_pid FROM src_pids))")
        
        for table in ["item","item_extra","item_playback","item_stats","item_store","item_video","item_search","lyrics","chapter"] {
            _ = sqliteExec(db, "INSERT OR REPLACE INTO \(table) SELECT * FROM src.\(table) WHERE item_pid IN (SELECT item_pid FROM src_pids)")
        }
        
        _ = sqliteExec(db, "DELETE FROM artwork_token WHERE entity_pid IN (SELECT item_pid FROM dst_pids)")
        _ = sqliteExec(db, "DELETE FROM best_artwork_token WHERE entity_pid IN (SELECT item_pid FROM dst_pids)")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO artwork_token SELECT * FROM src.artwork_token WHERE entity_pid IN (SELECT item_pid FROM src_pids)")
        _ = sqliteExec(db, "INSERT OR REPLACE INTO best_artwork_token SELECT * FROM src.best_artwork_token WHERE entity_pid IN (SELECT item_pid FROM src_pids)")
        
        _ = sqliteExec(db, """
        INSERT OR REPLACE INTO artwork
        SELECT * FROM src.artwork
        WHERE artwork_token IN (
            SELECT artwork_token FROM src.artwork_token WHERE entity_pid IN (SELECT item_pid FROM src_pids)
            UNION
            SELECT available_artwork_token FROM src.best_artwork_token WHERE entity_pid IN (SELECT item_pid FROM src_pids)
            UNION
            SELECT fetchable_artwork_token FROM src.best_artwork_token WHERE entity_pid IN (SELECT item_pid FROM src_pids)
        )
        """)
        
        _ = sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
        _ = sqliteExec(db, "PRAGMA journal_mode=DELETE")
        _ = sqliteExec(db, "DETACH DATABASE src")
        
        let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
        let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
        let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
        let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
        
        let semUpload = DispatchSemaphore(value: 0)
        var uploaded = false
        self.uploadFileToDevice(localURL: dstDbURL, remotePath: tempDBPath) { ok in
            uploaded = ok
            semUpload.signal()
        }
        semUpload.wait()
        guard uploaded else {
            Logger.shared.log("[Backup] Row-merge failed: upload merged DB failed")
            return false
        }
        
        var afc: AfcClientHandle?
        afc_client_connect(self.provider, &afc)
        guard let afc else { return false }
        defer { afc_client_free(afc) }
        
        _ = afc_remove_path(afc, shmPath)
        _ = afc_remove_path(afc, walPath)
        _ = afc_remove_path(afc, finalDBPath)
        let renameErr = afc_rename_path(afc, tempDBPath, finalDBPath)
        if renameErr != nil {
            _ = afc_remove_path(afc, tempDBPath)
            Logger.shared.log("[Backup] Row-merge failed: atomic swap failed")
            return false
        }
        
        return true
    }
    
    func fetchDatabaseSnapshots(completion: @escaping ([DatabaseSnapshotInfo]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let root = self.snapshotsDirectoryURL
            
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
                
                snapshots.append(
                    DatabaseSnapshotInfo(
                        folderName: dir.lastPathComponent,
                        createdAt: createdAt,
                        songCount: songCount
                    )
                )
            }
            
            snapshots.sort { $0.createdAt > $1.createdAt }
            completion(snapshots)
        }
    }
    
    private func resolvePrimaryMusicDirectory() -> String {
        let fallback = "/iTunes_Control/Music/F00"
        let sem = DispatchSemaphore(value: 0)
        var dbData: Data?
        self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
            dbData = data
            sem.signal()
        }
        sem.wait()
        
        guard let dbData, dbData.count > 1000 else {
            Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (no DB)")
            return fallback
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("music_dir_probe_\(UUID().uuidString).sqlitedb")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        do {
            try dbData.write(to: tempURL)
        } catch {
            Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (write temp failed: \(error))")
            return fallback
        }
        
        var db: OpaquePointer?
        guard sqlite3_open(tempURL.path, &db) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (open DB failed)")
            return fallback
        }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        let sql = "SELECT path FROM base_location WHERE base_location_id = 3840 LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if stmt != nil { sqlite3_finalize(stmt) }
            Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (query prepare failed)")
            return fallback
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW, let pathPtr = sqlite3_column_text(stmt, 0) {
            let rawPath = String(cString: pathPtr)
            let normalized = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
            if normalized.hasPrefix("/iTunes_Control/Music/") {
                Logger.shared.log("[DeviceManager] Music dir resolved from base_location(3840): \(normalized)")
                return normalized
            }
        }
        
        Logger.shared.log("[DeviceManager] Music dir resolve: fallback to \(fallback) (base_location missing/invalid)")
        return fallback
    }
    
    private func cleanUpOrphanedFiles(validFilenames: Set<String>, musicDir: String, completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            afc_client_connect(self.provider, &afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] GC: Failed to connect AFC")
                completion(0)
                return
            }
            
            var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int = 0
            
            let err = afc_list_directory(afc, musicDir, &entries, &count)
            
            var deletedCount = 0
            
            if err == nil, let list = entries {
                for i in 0..<count {
                    if let ptr = list[i] {
                        let filename = String(cString: ptr)
                        if filename != "." && filename != ".." {
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
            
            
            var dataPtr: UnsafeMutablePointer<UInt8>? = nil
            var length: Int = 0

            let err = afc_file_read_entire(file, &dataPtr, &length)

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

        DispatchQueue.global(qos: .userInitiated).async {
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
                    semaphore.wait()
                    song.artworkData = extractedArtwork
                }

                validSongs.append(song)
            }

            Logger.shared.log("[DeviceManager] Processing \(validSongs.count) songs (Sanitized).")

            if validSongs.isEmpty {
                Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs found.")
                DispatchQueue.main.async { completion(true) }
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
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: musicDir) { files in
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
            afc_make_directory(afc, musicDir)
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
                    
                    Logger.shared.log("[DeviceManager] Existing files on device: \(existingFiles.count), artwork entries: \(artworkInfo.count)")
                } else {
                    if existingDbData != nil {
                        Logger.shared.log("[DeviceManager] Existing database too small (\(existingDbData!.count) bytes), creating fresh")
                    }
                    
                    progress("Creating new library...")
                    Logger.shared.log("[DeviceManager] Step 3: Creating fresh database")
                    let version = self.getDatabaseVersion()
                    let createResult = try MediaLibraryBuilder.createDatabase(songs: validSongs, version: version)
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
                
                let remotePath = "\(musicDir)/\(song.remoteFilename)"
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
                    Logger.shared.log("[DeviceManager] Artwork uploaded to: \(artworkPath)")
                }
            }
            
            Logger.shared.log("[DeviceManager] Uploaded: \(uploadedCount), Skipped: \(skippedCount)")
            
            
            
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
            for var song in songs {
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
                    semaphore.wait()
                    song.artworkData = extractedArtwork
                }
                validSongs.append(song)
            }

            if validSongs.isEmpty {
                Logger.shared.log("[DeviceManager] ⚠️ ABORTING: No songs for playlist.")
                DispatchQueue.main.async { completion(true) }
                return
            }
        
            guard let self = self else { return }
            let musicDir = self.resolvePrimaryMusicDirectory()
            
            
            Logger.shared.log("[DeviceManager] Step 0: Listing existing files in \(musicDir)")
            var onDeviceFiles: Set<String> = []
            let semFiles = DispatchSemaphore(value: 0)
            
            self.listFiles(remotePath: musicDir) { files in
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
                
                
                
                afc_make_directory(afc, musicDir)
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
            
            for (index, song) in validSongs.enumerated() {
                
                if existingFiles.contains(song.remoteFilename) {
                    continue
                }
                
                progress("Uploading \(index + 1)/\(validSongs.count): \(song.title)")
                
                let semaphore = DispatchSemaphore(value: 0)
                var uploadSuccess = false
                let remotePath = "\(musicDir)/\(song.remoteFilename)"
                
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
            let dbVersion = self.getDatabaseVersion()
            let requiresRingtoneDBEntries = dbVersion.major <= 18
            let primaryRoot = "/iTunes_Control/Ringtones"
            let legacyRoot = "/iTunes_Control/Ringtons"
            var resolvedRoot = primaryRoot
            
            
            // ── Step 1: Load existing Ringtones.plist (merge, don't overwrite) ──
            progress("Preparing ringtones...")
            Logger.shared.log("[DeviceManager] Downloading existing Ringtones.plist")

            var rootDict: [String: Any] = [:]
            var ringtonesDict: [String: Any] = [:]

            let plistSem = DispatchSemaphore(value: 0)
            self.downloadFileFromDevice(remotePath: "\(primaryRoot)/Ringtones.plist") { data in
                if let data = data {
                    if let dict = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                        rootDict = dict
                        ringtonesDict = (dict["Ringtones"] as? [String: Any]) ?? [:]
                        resolvedRoot = primaryRoot
                        Logger.shared.log("[DeviceManager] Loaded existing plist with \(ringtonesDict.count) entries")
                    }
                } else {
                    let legacySem = DispatchSemaphore(value: 0)
                    self.downloadFileFromDevice(remotePath: "\(legacyRoot)/Ringtones.plist") { legacyData in
                        if let legacyData = legacyData,
                           let dict = try? PropertyListSerialization.propertyList(from: legacyData, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] {
                            rootDict = dict
                            ringtonesDict = (dict["Ringtones"] as? [String: Any]) ?? [:]
                            resolvedRoot = legacyRoot
                            Logger.shared.log("[DeviceManager] Loaded existing legacy plist with \(ringtonesDict.count) entries")
                        }
                        legacySem.signal()
                    }
                    legacySem.wait()
                }
                plistSem.signal()
            }
            plistSem.wait()

            // ── Step 2: Ensure ringtone directories exist ──────────────
            var afcDir: AfcClientHandle?
            afc_client_connect(self.provider, &afcDir)
            if afcDir != nil {
                afc_make_directory(afcDir, primaryRoot)
                afc_make_directory(afcDir, "\(primaryRoot)/Sync")
                afc_make_directory(afcDir, legacyRoot)
                afc_make_directory(afcDir, "\(legacyRoot)/Sync")
                afc_client_free(afcDir)
            }

            // ── Step 3: Upload each .m4r and build the plist entries ─────────
            progress("Uploading ringtones...")
            var uploadedRingtones: [SongMetadata] = []

            for ringtone in ringtones {
                let remotePath = "\(resolvedRoot)/\(ringtone.remoteFilename)"
                let mirrorPath = "\(resolvedRoot == primaryRoot ? legacyRoot : primaryRoot)/\(ringtone.remoteFilename)"

                let uploadSem = DispatchSemaphore(value: 0)
                var uploadOK = false
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: remotePath) { s in
                    uploadOK = s
                    uploadSem.signal()
                }
                uploadSem.wait()
                
                let mirrorSem = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: ringtone.localURL, remotePath: mirrorPath) { _ in
                    mirrorSem.signal()
                }
                mirrorSem.wait()

                if uploadOK {
                    Logger.shared.log("[DeviceManager] Uploaded: \(ringtone.remoteFilename)")
                    uploadedRingtones.append(ringtone)
                } else {
                    Logger.shared.log("[DeviceManager] WARNING: Failed to upload \(ringtone.remoteFilename)")
                    continue
                }

                let pid  = SongMetadata.generatePersistentId()
                let guid = String(format: "%016llX", SongMetadata.generatePersistentId())

                let entry: [String: Any] = [
                    "Name":              ringtone.title,
                    "Total Time":        ringtone.durationMs,   // real duration ms
                    "PID":               pid,
                    "Protected Content": false,
                    "GUID":              guid
                ]
                ringtonesDict[ringtone.remoteFilename] = entry
                Logger.shared.log("[DeviceManager] Plist entry: \(ringtone.remoteFilename) PID=\(pid) GUID=\(guid)")
            }

            // ── Step 4: Upload merged Ringtones.plist (binary format) ────────
            rootDict["Ringtones"] = ringtonesDict

            do {
                let tempDir  = FileManager.default.temporaryDirectory
                let plistData = try PropertyListSerialization.data(fromPropertyList: rootDict, format: .binary, options: 0)
                let tempPlist = tempDir.appendingPathComponent("Ringtones.plist")
                try plistData.write(to: tempPlist)

                let plistSem2 = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "\(resolvedRoot)/Ringtones.plist") { _ in
                    plistSem2.signal()
                }
                plistSem2.wait()
                
                let plistSemMirror = DispatchSemaphore(value: 0)
                let mirrorPlistRoot = (resolvedRoot == primaryRoot) ? legacyRoot : primaryRoot
                self.uploadFileToDevice(localURL: tempPlist, remotePath: "\(mirrorPlistRoot)/Ringtones.plist") { _ in
                    plistSemMirror.signal()
                }
                plistSemMirror.wait()
                Logger.shared.log("[DeviceManager] Ringtones.plist uploaded (\(ringtonesDict.count) total entries)")
            } catch {
                Logger.shared.log("[DeviceManager] Failed to upload Ringtones.plist: \(error)")
            }
            
            // ── Step 5: Write SyncAnchor marker files (seen in iOS 17/18 exports) ──
            do {
                let anchor: [String: Any] = ["syncAnchor": "1"]
                let anchorData = try PropertyListSerialization.data(fromPropertyList: anchor, format: .binary, options: 0)
                let anchorURL = FileManager.default.temporaryDirectory.appendingPathComponent("SyncAnchor.plist")
                try anchorData.write(to: anchorURL)
                
                let anchorSem1 = DispatchSemaphore(value: 0)
                self.uploadFileToDevice(localURL: anchorURL, remotePath: "\(resolvedRoot)/SyncAnchor.plist") { _ in
                    anchorSem1.signal()
                }
                anchorSem1.wait()
                
                let anchorSem2 = DispatchSemaphore(value: 0)
                let mirrorAnchorRoot = (resolvedRoot == primaryRoot) ? legacyRoot : primaryRoot
                self.uploadFileToDevice(localURL: anchorURL, remotePath: "\(mirrorAnchorRoot)/SyncAnchor.plist") { _ in
                    anchorSem2.signal()
                }
                anchorSem2.wait()
                Logger.shared.log("[Ringtone-DB] SyncAnchor.plist uploaded")
            } catch {
                Logger.shared.log("[Ringtone-DB] Failed to upload SyncAnchor.plist: \(error)")
            }
            
            // ── Step 6: On iOS 18 and lower, also insert ringtone rows into MediaLibrary DB ──
            if requiresRingtoneDBEntries && !uploadedRingtones.isEmpty {
                progress("Updating ringtone database...")
                Logger.shared.log("[Ringtone-DB] iOS \(dbVersion.major) detected: inserting DB rows for \(uploadedRingtones.count) ringtone(s)")
                
                var dbData: Data?
                var walData: Data?
                var shmData: Data?
                
                let dbSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                    dbData = data
                    dbSem.signal()
                }
                dbSem.wait()
                
                guard let baseDbData = dbData else {
                    Logger.shared.log("[Ringtone-DB] Failed to download MediaLibrary.sqlitedb, skipping DB insertion")
                    progress("Done!")
                    self.postRingtoneRefreshNotifications()
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                
                let walSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                    walData = data
                    walSem.signal()
                }
                walSem.wait()
                
                let shmSem = DispatchSemaphore(value: 0)
                self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                    shmData = data
                    shmSem.signal()
                }
                shmSem.wait()
                
                do {
                    let updatedDbURL = try MediaLibraryBuilder.addRingtonesToExistingDatabase(
                        existingDbData: baseDbData,
                        walData: walData,
                        shmData: shmData,
                        ringtones: uploadedRingtones
                    )
                    
                    let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
                    let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
                    let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
                    let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"
                    
                    let uploadSem = DispatchSemaphore(value: 0)
                    var uploadOK = false
                    self.uploadFileToDevice(localURL: updatedDbURL, remotePath: tempDBPath) { ok in
                        uploadOK = ok
                        uploadSem.signal()
                    }
                    uploadSem.wait()
                    
                    if uploadOK {
                        var afcSwap: AfcClientHandle?
                        afc_client_connect(self.provider, &afcSwap)
                        if let afcSwap {
                            _ = afc_remove_path(afcSwap, shmPath)
                            _ = afc_remove_path(afcSwap, walPath)
                            _ = afc_remove_path(afcSwap, finalDBPath)
                            
                            let renameErr = afc_rename_path(afcSwap, tempDBPath, finalDBPath)
                            if renameErr == nil {
                                Logger.shared.log("[Ringtone-DB] Database swapped successfully with ringtone entries")
                            } else {
                                Logger.shared.log("[Ringtone-DB] Failed to swap database after ringtone insert")
                                _ = afc_remove_path(afcSwap, tempDBPath)
                            }
                            afc_client_free(afcSwap)
                        } else {
                            Logger.shared.log("[Ringtone-DB] Could not open AFC for database swap")
                        }
                    } else {
                        Logger.shared.log("[Ringtone-DB] Failed to upload updated ringtone database")
                    }
                } catch {
                    Logger.shared.log("[Ringtone-DB] Failed to build/update ringtone database: \(error)")
                }
            } else {
                Logger.shared.log("[Ringtone-DB] DB insertion not required for iOS \(dbVersion.major)")
            }

            progress("Done!")
            self.postRingtoneRefreshNotifications()
            DispatchQueue.main.async { completion(true) }
        }
    }
}


extension URL {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
