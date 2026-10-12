import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)


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
typealias RpPairingFileHandle = OpaquePointer

typealias IdeviceErrorCode = UnsafeMutablePointer<IdeviceFfiError>?
typealias SnapshotProgressHandler = (String, Double?) -> Void

let IdeviceSuccess: IdeviceErrorCode = nil

enum PairingFileImportError: LocalizedError {
    case invalidFileType(expected: String)
    case wrongFormatForOSVersion(expected: String, detectedOther: String)

    var errorDescription: String? {
        switch self {
        case .invalidFileType(let expected):
            return "That file is not a valid \(expected). Make sure you exported it correctly and try again."
        case .wrongFormatForOSVersion(let expected, let detectedOther):
            return "This looks like a \(detectedOther), but your iPhone's current iOS version needs a \(expected) instead. Export the correct file type and try again."
        }
    }
}


let BUILD_VERSION = "v2.6"
let DEVICE_HOST = "10.7.0.1"
let RP_PAIRING_PORT: UInt16 = 49152

extension FileManager {
    nonisolated func createDirectoryLogged(at url: URL) {
        do {
            try createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Logger.shared.log("[Backup] Failed to create directory \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

extension DispatchSemaphore {
    nonisolated func waitForTransfer(seconds: TimeInterval = 900) {
        if wait(timeout: .now() + seconds) == .timedOut {
            Logger.shared.log("[DeviceManager] Transfer wait timed out after \(Int(seconds))s")
        }
    }
}

class DeviceManager: ObservableObject {

    // MARK: - Nested Types
    struct DatabaseSnapshotInfo: Identifiable {
        var id: String { folderName }
        let folderName: String
        let createdAt: Date
        let songCount: Int
        let sizeBytes: Int
        let displayName: String?
    }

    struct ExportableSongInfo: Identifiable, Hashable {
        var id: String { remoteFilename }
        let itemPid: Int64
        let remoteFilename: String
        let title: String
        let artist: String
        let album: String
        let albumPid: Int64
        let albumArtist: String
        let genre: String
        let year: Int
        let durationMs: Int
        let fileSize: Int
        let trackNumber: Int?
        let lyrics: String?
        let explicitRating: Int
        let fileExtension: String
        let artworkRelativePath: String?

        var suggestedFilename: String {
            let ext = fileExtension.isEmpty ? "mp3" : fileExtension
            return "\(DeviceManager.sanitizedExportFilenameBase("\(artist) - \(title)")).\(ext)"
        }
    }

    struct ArtworkRepairCandidate {
        let itemPid: Int64
        let albumPid: Int64
        let storeItemId: Int64
        let title: String
        let artist: String
        let album: String
        let artworkToken: String
        let relativePath: String
    }

    struct ExperimentalAppleMetadataRepair {
        let itemPid: Int64
        let albumPid: Int64
        let artworkToken: String
        let relativePath: String
        let title: String
        let artist: String
        let album: String
        let year: Int
        let trackNumber: Int
        let trackCount: Int
        let discNumber: Int
        let discCount: Int
        let durationMs: Int
        let explicitRating: Int
        let copyright: String
        let storeItemId: Int64
        let artistId: Int64
        let composerId: Int64
        let genreStoreId: Int64
        let albumStoreId: Int64
        let storefrontId: Int64
        let storeXid: String
        let storeFlavor: String
        let releaseDate: Int
        let subscriptionStoreItemId: Int64
        let masteredForItunes: Int
        let hlsAssetTraits: Int
        let colorAnalysis: String
        let artworkData: Data?
    }

    // MARK: - Connection State
    @Published var heartbeatReady: Bool = false
    @Published var pinnedPlaylistPids: Set<Int64> = []
    @Published var connectionStatus: String = "Disconnected"
    @Published var hasValidExpectedPairingFile: Bool = false
    var provider: IdeviceProviderHandle?
    var rpAdapter: AdapterHandle?
    var rpHandshake: RsdHandshakeHandle?
    var heartbeatThread: Thread?
    var heartbeatSessionID: UInt64 = 0
    var isReconnecting = false
    var pendingReconnectCompletions: [(Bool) -> Void] = []
    let reconnectCoordinationLock = NSLock()
    nonisolated(unsafe) private var currentRepairOperationToken: UUID?
    nonisolated private let repairTokenLock = NSLock()

    nonisolated func beginRepairOperation() -> UUID {
        let token = UUID()
        repairTokenLock.lock()
        currentRepairOperationToken = token
        repairTokenLock.unlock()
        return token
    }

    nonisolated func isRepairOperationCancelled(_ token: UUID) -> Bool {
        repairTokenLock.lock()
        defer { repairTokenLock.unlock() }
        return currentRepairOperationToken != token
    }

    nonisolated func cancelCurrentRepairOperation() {
        repairTokenLock.lock()
        currentRepairOperationToken = nil
        repairTokenLock.unlock()
    }
    var autoReconnectTimer: DispatchSourceTimer?
    var lastHeartbeatAttemptStartedAt: Date = .distantPast
    let autoReconnectCheckInterval: TimeInterval = 2
    let staleHeartbeatAttemptInterval: TimeInterval = 6
    let heartbeatEstablishTimeout: TimeInterval = 20
    
    var lastLoggedStatus: [String: String] = [:]
    
    func logOnce(_ message: String, key: String) {
        objc_sync_enter(self)
        let changed = lastLoggedStatus[key] != message
        if changed {
            lastLoggedStatus[key] = message
        }
        objc_sync_exit(self)
        
        if changed {
            Logger.shared.log(message)
        }
    }
    
    static var shared = DeviceManager()
    
    
    static let appGroupID = "group.com.edualexxis.MusicManager"

    static func sanitizedExportFilenameBase(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.isEmpty ? "Exported Song" : collapsed
    }
    
    // MARK: - Pairing Files
    var pairingFile: URL {
        regularPairingFile
    }

    var regularPairingFile: URL {
        let base: URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            base = containerURL
        } else {
            base = URL.documentsDirectory
        }
        return base.appendingPathComponent("pairing file").appendingPathComponent("pairingFile.plist")
    }

    var rpPairingFile: URL {
        regularPairingFile.deletingLastPathComponent().appendingPathComponent("rpPairingFile.plist")
    }

    var expectedPairingFile: URL {
        requiresRPPairingTunnel ? rpPairingFile : regularPairingFile
    }
    
    
    static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    var requiresRPPairingTunnel: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion > 26 { return true }
        return version.majorVersion == 26 && version.minorVersion >= 4
    }

    var expectedPairingFileDescription: String {
        requiresRPPairingTunnel ? "RP pairing file" : "pairing file"
    }

    var expectedPairingFileTitle: String {
        requiresRPPairingTunnel ? "RP Pairing File" : "Pairing File"
    }

    var shouldPromptForRPPairingUpgrade: Bool {
        requiresRPPairingTunnel && !hasValidExpectedPairingFile && validateLockdownPairingFile(at: regularPairingFile)
    }

    var supportsIOS26ArtworkRepair: Bool {
        requiresRPPairingTunnel
    }

    var hasActiveTransport: Bool {
        if requiresRPPairingTunnel {
            return rpAdapter != nil && rpHandshake != nil
        }
        return provider != nil
    }
    
    // MARK: - Snapshot Storage
    var snapshotsDirectoryURL: URL {
        if let custom = customSnapshotsDirectory() {
            return custom
        }
        let base = Self.sharedContainerURL ?? URL.documentsDirectory
        let hidden = base.appendingPathComponent(".db_snapshots", isDirectory: true)
        let legacy = base.appendingPathComponent("db_snapshots", isDirectory: true)
        migrateLegacySnapshotsDirectory(from: legacy, to: hidden)
        return hidden
    }

    func customSnapshotsDirectory() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "backupsFolderBookmark") else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale,
               let refreshedBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshedBookmark, forKey: "backupsFolderBookmark")
            }

            return url
        } catch {
            Logger.shared.log("[DeviceManager] Failed to resolve custom backups folder bookmark: \(error)")
            return nil
        }
    }

    @discardableResult
    func withSnapshotsDirectoryAccess<T>(_ body: () -> T) -> T {
        let url = snapshotsDirectoryURL
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return body()
    }

    static let backupDisplayNamesKey = "backupDisplayNames"

    func displayName(for folderName: String) -> String? {
        let names = UserDefaults.standard.dictionary(forKey: Self.backupDisplayNamesKey) as? [String: String]
        return names?[folderName]
    }

    func setDisplayName(_ name: String?, for folderName: String) {
        var names = (UserDefaults.standard.dictionary(forKey: Self.backupDisplayNamesKey) as? [String: String]) ?? [:]
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            names[folderName] = trimmed
        } else {
            names.removeValue(forKey: folderName)
        }
        UserDefaults.standard.set(names, forKey: Self.backupDisplayNamesKey)
    }

    let snapshotMusicManifestName = "music_files.txt"
    let snapshotArtworkManifestName = "artwork_paths.txt"
    let snapshotArtworkDirectory = "Artwork/Originals"
    let snapshotFullBackupDirectory = ".iTunesFullBackup"
    
    // MARK: - Setup
    private init() {
        Logger.shared.log("===========================================")
        Logger.shared.log("[DeviceManager] BUILD VERSION: \(BUILD_VERSION)")
        Logger.shared.log("===========================================")
        Logger.shared.log("[DeviceManager] Initializing...")
        let logPath = FileManager.default.temporaryDirectory.appendingPathComponent("idevice-logs.txt").path
        let cString = strdup(logPath)
        defer { free(cString) }
        idevice_init_logger(Info, Disabled, cString)
        
        let folderPath = self.regularPairingFile.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: folderPath.path) {
                try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true)
                Logger.shared.log("[DeviceManager] Created pairing file directory at: \(folderPath.path)")
            }
        } catch {
            Logger.shared.log("[DeviceManager] Error creating pairing directory: \(error)")
        }
        refreshExpectedPairingFileState()
        installAutoReconnectWatcher()
    }

    func installAutoReconnectWatcher() {
        guard autoReconnectTimer == nil else { return }

        Logger.shared.log("[DeviceManager] Installing auto-reconnect watcher")

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + autoReconnectCheckInterval, repeating: autoReconnectCheckInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard UIApplication.shared.applicationState == .active else { return }

            self.refreshExpectedPairingFileState()
            guard self.hasValidExpectedPairingFile else {
                self.logOnce("[DeviceManager] Auto-reconnect skipped: pairing file is not valid", key: "auto_reconnect")
                return
            }

            let timeSinceLastAttempt = Date().timeIntervalSince(self.lastHeartbeatAttemptStartedAt)
            let connectingIsStale =
                self.connectionStatus == "Connecting..."
                && timeSinceLastAttempt >= self.staleHeartbeatAttemptInterval

            guard self.connectionStatus != "Connecting..." || connectingIsStale else {
                self.logOnce("[DeviceManager] Auto-reconnect skipped: already connecting", key: "auto_reconnect")
                return
            }

            if self.connectionStatus != "Connecting..." {
                guard timeSinceLastAttempt >= 10.0 else { return }
            }

            if connectingIsStale {
                self.logOnce("[DeviceManager] Auto-reconnect detected stale connecting state; forcing refresh", key: "auto_reconnect")
            }

            let needsReconnect = !self.heartbeatReady || !self.hasActiveTransport
            guard needsReconnect else { return }

            self.logOnce("[DeviceManager] Auto-reconnect triggering forced heartbeat refresh", key: "auto_reconnect")
            Logger.shared.log("[DeviceManager] Auto-reconnect reason: ready=\(self.heartbeatReady), transport=\(self.hasActiveTransport), status=\(self.connectionStatus)")
            self.startHeartbeat(forceReconnect: true)
        }
        timer.resume()
        autoReconnectTimer = timer
    }

    func migrateLegacySnapshotsDirectory(from legacy: URL, to hidden: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }

        do {
            if !fm.fileExists(atPath: hidden.path) {
                try fm.moveItem(at: legacy, to: hidden)
                Logger.shared.log("[Backup] Migrated snapshots folder to hidden storage")
                return
            }

            let entries = try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for entry in entries {
                let destination = hidden.appendingPathComponent(entry.lastPathComponent, isDirectory: entry.hasDirectoryPath)
                if fm.fileExists(atPath: destination.path) {
                    try? fm.removeItem(at: destination)
                }
                try fm.moveItem(at: entry, to: destination)
            }
            try fm.removeItem(at: legacy)
            Logger.shared.log("[Backup] Merged legacy snapshots into hidden storage")
        } catch {
            Logger.shared.log("[Backup] Failed to migrate legacy snapshots folder: \(error)")
        }
    }

    
}

extension URL {
    static var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
