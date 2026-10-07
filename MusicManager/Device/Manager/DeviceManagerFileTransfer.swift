import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - File Transfer
extension DeviceManager {
    func downloadFileFromDevice(remotePath: String, completion: @escaping (Data?) -> Void) {
        Logger.shared.log("[DeviceManager] downloadFileFromDevice called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)

            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for download")
                completion(nil)
                return
            }
            
            defer {
                if let currentAfc = afc {
                    afc_client_free(currentAfc)
                }
            }

            for attempt in 1...2 {
                var file: AfcFileHandle?
                let err = afc_file_open(afc, remotePath, AfcRdOnly, &file)

                if err == nil, let fileHandle = file {
                    var dataPtr: UnsafeMutablePointer<UInt8>? = nil
                    var length: Int = 0
                    let readErr = afc_file_read_entire(fileHandle, &dataPtr, &length)
                    afc_file_close(fileHandle)

                    if let readErr {
                        let msg = readErr.pointee.message != nil ? String(cString: readErr.pointee.message!) : "No message"
                        Logger.shared.log("[DeviceManager] ERROR: afc_file_read_entire failed. Code: \(readErr.pointee.code), Msg: \(msg)")
                        idevice_error_free(readErr)
                        completion(nil)
                        return
                    }

                    if let ptr = dataPtr, length > 0 {
                        let data = Data(bytes: ptr, count: length)
                        Logger.shared.log("[DeviceManager] Downloaded \(length) bytes from \(remotePath)")
                        afc_file_read_data_free(ptr, length)
                        completion(data)
                        return
                    }

                    completion(nil)
                    return
                }

                if let openErr = err {
                    let msg = openErr.pointee.message != nil ? String(cString: openErr.pointee.message!) : "No message"
                    let isConnLoss = self.isConnectionLossError(openErr)
                    Logger.shared.log("[DeviceManager] afc_file_open failed. Code: \(openErr.pointee.code), Msg: \(msg), ConnectionLoss: \(isConnLoss)")
                    idevice_error_free(openErr)

                    if isConnLoss && attempt < 2 {
                        if self.reconnectAfcClient(&afc, reason: remotePath) {
                            continue
                        }
                    }
                } else {
                    Logger.shared.log("[DeviceManager] afc_file_open failed with nil error and nil file handle")
                }

                completion(nil)
                return
            }
        }
    }
    
    
    
    func uploadFileToDevice(localURL: URL, remotePath: String, completion: @escaping (Bool) -> Void) {
        Logger.shared.log("[DeviceManager] uploadFileToDevice called: \(localURL.lastPathComponent) -> \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            
            self.connectAfcClient(&afc)
            
            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for upload")
                completion(false)
                return
            }
            defer { afc_client_free(afc) }

            completion(self.uploadFileToDevice(localURL: localURL, remotePath: remotePath, afc: afc))
        }
    }

    func reconnectAfcClient(_ afc: inout AfcClientHandle?, reason: String) -> Bool {
        if let currentAfc = afc {
            afc_client_free(currentAfc)
            afc = nil
        }

        Logger.shared.log("[DeviceManager] AFC transport lost, reconnecting (\(reason))...")

        let semaphore = DispatchSemaphore(value: 0)
        var reconnected = false

        startHeartbeat(forceReconnect: true) { success in
            reconnected = success
            semaphore.signal()
        }
        guard awaitAFCOperation(semaphore, timeoutSeconds: 45, step: "Heartbeat rebuild during AFC reconnect") else {
            return false
        }

        guard reconnected else {
            Logger.shared.log("[DeviceManager] ERROR: Failed to rebuild transport during AFC reconnect")
            return false
        }

        let connectErr = connectAfcClient(&afc)
        guard connectErr == IdeviceSuccess, afc != nil else {
            Logger.shared.log("[DeviceManager] ERROR: Failed to reconnect AFC client")
            return false
        }

        Logger.shared.log("[DeviceManager] AFC client reconnected successfully")
        return true
    }

    func isConnectionLossError(_ err: IdeviceErrorCode) -> Bool {
        guard let error = err else { return false }
        let code = error.pointee.code
        let msg = error.pointee.message != nil ? String(cString: error.pointee.message!) : ""
        
        if code == 8 || code == 9 {
            return false
        }

        if code == 7 || code == 10 || code == 11 {
            return false
        }
        
        let lower = msg.lowercased()
        if lower.contains("not found") || lower.contains("no such") || lower.contains("objectnotfound") {
            return false
        }
        
        return true
    }

    func ensureActiveTransport(reason: String) -> Bool {
        if heartbeatReady && hasActiveTransport && canStillReachDevice() {
            return true
        }

        Logger.shared.log("[DeviceManager] Transport unavailable, reconnecting before \(reason)...")

        let semaphore = DispatchSemaphore(value: 0)
        var connected = false

        startHeartbeat(forceReconnect: true) { success in
            connected = success
            semaphore.signal()
        }
        semaphore.waitForTransfer()

        if !connected {
            Logger.shared.log("[DeviceManager] ERROR: Failed to reconnect transport before \(reason)")
        }

        return connected
    }

    func uploadFileToDeviceWithReconnect(localURL: URL, remotePath: String, afc: inout AfcClientHandle?, verify: Bool = true, maxAttempts: Int = 3) -> Bool {
        for attempt in 1...maxAttempts {
            if uploadFileToDevice(localURL: localURL, remotePath: remotePath, afc: afc, verify: verify) {
                return true
            }

            guard attempt < maxAttempts else { break }

            Logger.shared.log("[DeviceManager] Retrying file upload after AFC reconnect (\(attempt)/\(maxAttempts - 1)): \(remotePath)")
            Thread.sleep(forTimeInterval: 0.5)
            guard reconnectAfcClient(&afc, reason: remotePath) else { break }
        }

        return false
    }

    func uploadDataToDeviceWithReconnect(_ data: Data, remotePath: String, afc: inout AfcClientHandle?, verify: Bool = true, maxAttempts: Int = 3) -> Bool {
        for attempt in 1...maxAttempts {
            if uploadDataToDevice(data, remotePath: remotePath, afc: afc, verify: verify) {
                return true
            }

            guard attempt < maxAttempts else { break }

            Logger.shared.log("[DeviceManager] Retrying data upload after AFC reconnect (\(attempt)/\(maxAttempts - 1)): \(remotePath)")
            Thread.sleep(forTimeInterval: 0.5)
            guard reconnectAfcClient(&afc, reason: remotePath) else { break }
        }

        return false
    }

    func preferredParallelUploadCount(for totalFiles: Int) -> Int {
        guard totalFiles > 1 else { return 1 }
        let processorBudget = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 6))
        return min(totalFiles, processorBudget)
    }

    func uploadFilesToDeviceInChunks(
        _ uploads: [(localURL: URL, remotePath: String, label: String)],
        progressLabel: String,
        progress: @escaping (String) -> Void
    ) -> (success: Bool, uploadedCount: Int) {
        guard !uploads.isEmpty else { return (true, 0) }

        let concurrency = preferredParallelUploadCount(for: uploads.count)
        let chunkSize = max(concurrency, min(uploads.count, concurrency * 3))
        let lock = NSLock()
        var uploadedCount = 0
        var failedLabels: [String] = []

        Logger.shared.log(
            "[DeviceManager] Parallel AFC upload enabled: \(uploads.count) files, " +
            "\(concurrency) concurrent connections, chunk size \(chunkSize)"
        )

        for chunkStart in stride(from: 0, to: uploads.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, uploads.count)
            let chunk = Array(uploads[chunkStart..<chunkEnd])
            let throttle = DispatchSemaphore(value: concurrency)
            let group = DispatchGroup()

            Logger.shared.log(
                "[DeviceManager] Upload chunk \(chunkStart / chunkSize + 1): files \(chunkStart + 1)-\(chunkEnd) of \(uploads.count)"
            )

            for upload in chunk {
                group.enter()
                throttle.wait()

                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        throttle.signal()
                        group.leave()
                    }

                    var localAfc: AfcClientHandle?
                    let connectErr = self.connectAfcClient(&localAfc)
                    guard connectErr == IdeviceSuccess, localAfc != nil else {
                        lock.lock()
                        failedLabels.append(upload.label)
                        lock.unlock()
                        Logger.shared.log("[DeviceManager] ERROR: Failed to open AFC client for \(upload.label)")
                        return
                    }
                    defer { afc_client_free(localAfc) }

                    let ok = self.uploadFileToDeviceWithReconnect(
                        localURL: upload.localURL,
                        remotePath: upload.remotePath,
                        afc: &localAfc,
                        verify: false
                    )

                    lock.lock()
                    if ok {
                        uploadedCount += 1
                        let done = uploadedCount
                        DispatchQueue.main.async {
                            progress("\(progressLabel) \(done)/\(uploads.count)...")
                        }
                    } else {
                        failedLabels.append(upload.label)
                        Logger.shared.log("[DeviceManager] ERROR: Parallel upload failed for \(upload.label)")
                    }
                    lock.unlock()
                }
            }

            group.wait()

            if !failedLabels.isEmpty {
                let failedPreview = failedLabels.prefix(3).joined(separator: ", ")
                Logger.shared.log(
                    "[DeviceManager] Parallel upload chunk failed after \(uploadedCount)/\(uploads.count) files. " +
                    "Examples: \(failedPreview)"
                )
                return (false, uploadedCount)
            }
        }

        return (true, uploadedCount)
    }

    func uploadDataToDeviceInChunks(
        _ uploads: [(data: Data, remotePath: String, label: String)],
        progressLabel: String,
        progress: @escaping (String) -> Void
    ) -> (success: Bool, uploadedCount: Int) {
        guard !uploads.isEmpty else { return (true, 0) }

        let concurrency = preferredParallelUploadCount(for: uploads.count)
        let chunkSize = max(concurrency, min(uploads.count, concurrency * 3))
        let lock = NSLock()
        var uploadedCount = 0
        var failedLabels: [String] = []

        Logger.shared.log(
            "[DeviceManager] Parallel AFC data upload enabled: \(uploads.count) files, " +
            "\(concurrency) concurrent connections, chunk size \(chunkSize)"
        )

        for chunkStart in stride(from: 0, to: uploads.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, uploads.count)
            let chunk = Array(uploads[chunkStart..<chunkEnd])
            let throttle = DispatchSemaphore(value: concurrency)
            let group = DispatchGroup()

            Logger.shared.log(
                "[DeviceManager] Data upload chunk \(chunkStart / chunkSize + 1): files \(chunkStart + 1)-\(chunkEnd) of \(uploads.count)"
            )

            for upload in chunk {
                group.enter()
                throttle.wait()

                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        throttle.signal()
                        group.leave()
                    }

                    var localAfc: AfcClientHandle?
                    let connectErr = self.connectAfcClient(&localAfc)
                    guard connectErr == IdeviceSuccess, localAfc != nil else {
                        lock.lock()
                        failedLabels.append(upload.label)
                        lock.unlock()
                        Logger.shared.log("[DeviceManager] ERROR: Failed to open AFC client for \(upload.label)")
                        return
                    }
                    defer { afc_client_free(localAfc) }

                    let ok = self.uploadDataToDeviceWithReconnect(
                        upload.data,
                        remotePath: upload.remotePath,
                        afc: &localAfc,
                        verify: false
                    )

                    lock.lock()
                    if ok {
                        uploadedCount += 1
                        let done = uploadedCount
                        Logger.shared.log("[DeviceManager] Artwork uploaded: \(upload.remotePath)")
                        DispatchQueue.main.async {
                            progress("\(progressLabel) \(done)/\(uploads.count)...")
                        }
                    } else {
                        failedLabels.append(upload.label)
                        Logger.shared.log("[DeviceManager] ERROR: Parallel data upload failed for \(upload.label)")
                    }
                    lock.unlock()
                }
            }

            group.wait()

            if !failedLabels.isEmpty {
                let failedPreview = failedLabels.prefix(3).joined(separator: ", ")
                Logger.shared.log(
                    "[DeviceManager] Parallel data upload chunk failed after \(uploadedCount)/\(uploads.count) files. " +
                    "Examples: \(failedPreview)"
                )
                return (false, uploadedCount)
            }
        }

        return (true, uploadedCount)
    }

    func uploadFileToDevice(localURL: URL, remotePath: String, afc: AfcClientHandle?, verify: Bool = true) -> Bool {
        let needsSecurityScope = localURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: localURL) else {
            Logger.shared.log("[DeviceManager] ERROR: Could not read file data")
            return false
        }

        return uploadDataToDevice(data, remotePath: remotePath, afc: afc, verify: verify)
    }

    func ensureRemoteDirectoryExists(_ remoteDirectory: String, afc: AfcClientHandle?) {
        guard afc != nil else { return }

        let trimmed = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return }

        let hasLeadingSlash = trimmed.hasPrefix("/")
        let components = trimmed.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }

        var currentPath = hasLeadingSlash ? "" : "."
        for component in components {
            if currentPath.isEmpty || currentPath == "." {
                currentPath = hasLeadingSlash ? "/\(component)" : component
            } else {
                currentPath += "/\(component)"
            }
            let makeErr = afc_make_directory(afc, currentPath)
            if let makeErr {
                idevice_error_free(makeErr)
            }
        }
    }

    func uploadDataToDevice(_ data: Data, remotePath: String, afc: AfcClientHandle?, verify: Bool = true) -> Bool {
        var file: AfcFileHandle?

        guard afc != nil else {
            Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for upload")
            return false
        }

        let parentDir = (remotePath as NSString).deletingLastPathComponent
        ensureRemoteDirectoryExists(parentDir, afc: afc)
        
        let removeErr = afc_remove_path(afc, remotePath)
        if let removeErr {
            idevice_error_free(removeErr)
        }
        
        let openErr = afc_file_open(afc, remotePath, AfcWrOnly, &file)

        guard openErr == nil, let fileHandle = file else {
            if let openErr {
                let msg = openErr.pointee.message != nil ? String(cString: openErr.pointee.message!) : "No message"
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file for upload: \(remotePath). Code: \(openErr.pointee.code), Msg: \(msg)")
                idevice_error_free(openErr)
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Could not open remote file for upload: \(remotePath) (nil error and nil file handle)")
            }
            return false
        }

        guard !data.isEmpty else {
            afc_file_close(fileHandle)
            Logger.shared.log("[DeviceManager] ERROR: Refusing to upload empty file: \(remotePath)")
            return false
        }

        let writeErr: IdeviceErrorCode = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            return afc_file_write(fileHandle, base, data.count)
        }

        afc_file_close(fileHandle)

        guard writeErr == nil else {
            if let writeErr {
                let msg = writeErr.pointee.message != nil ? String(cString: writeErr.pointee.message!) : "No message"
                Logger.shared.log("[DeviceManager] ERROR: Failed to write remote file: \(remotePath). Code: \(writeErr.pointee.code), Msg: \(msg)")
                idevice_error_free(writeErr)
            } else {
                Logger.shared.log("[DeviceManager] ERROR: Failed to write remote file: \(remotePath)")
            }
            return false
        }

        guard verify else { return true }

        var checkFile: AfcFileHandle?
        let ret = afc_file_open(afc, remotePath, AfcRdOnly, &checkFile)
        if ret == nil {
            if let checkFileHandle = checkFile {
                afc_file_close(checkFileHandle)
            }
            return true
        } else {
            if let ret {
                let msg = ret.pointee.message != nil ? String(cString: ret.pointee.message!) : "No message"
                Logger.shared.log("[DeviceManager] ERROR: Verification open failed for \(remotePath). Code: \(ret.pointee.code), Msg: \(msg)")
                idevice_error_free(ret)
            }
            return false
        }
    }

    func replaceRemoteFileAtomically(_ data: Data, remotePath: String, afc: AfcClientHandle?) -> Bool {
        let tempPath = remotePath + ".tmp"
        _ = afc_remove_path(afc, tempPath)

        guard uploadDataToDevice(data, remotePath: tempPath, afc: afc, verify: true) else {
            _ = afc_remove_path(afc, tempPath)
            return false
        }

        let renameErr = afc_rename_path(afc, tempPath, remotePath)
        guard renameErr == nil else {
            Logger.shared.log("[DeviceManager] ERROR: Failed to activate replacement file at \(remotePath)")
            _ = afc_remove_path(afc, tempPath)
            return false
        }

        return true
    }

    enum DirectoryListResult {
        case files([String])
        case confirmedMissing
        case unknown
    }

    func listFilesOrConfirmMissing(remotePath: String, completion: @escaping (DirectoryListResult) -> Void) {
        Logger.shared.log("[DeviceManager] listFilesOrConfirmMissing called for: \(remotePath)")

        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)

            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for listFilesOrConfirmMissing")
                completion(.unknown)
                return
            }

            defer {
                if let currentAfc = afc {
                    afc_client_free(currentAfc)
                }
            }

            for attempt in 1...2 {
                var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
                var count: Int = 0

                let err = afc_list_directory(afc, remotePath, &entries, &count)

                if err == nil {
                    var files: [String] = []
                    if let list = entries {
                        for i in 0..<count {
                            if let ptr = list[i] {
                                let name = String(cString: ptr)
                                if name != "." && name != ".." {
                                    files.append(name)
                                }
                            }
                        }
                        free(entries)
                    }
                    completion(.files(files))
                    return
                }

                if let listErr = err {
                    let msg = listErr.pointee.message != nil ? String(cString: listErr.pointee.message!) : "No message"
                    let isConnLoss = self.isConnectionLossError(listErr)
                    let isObjectNotFound = msg.contains("ObjectNotFound")
                    Logger.shared.log("[DeviceManager] afc_list_directory failed. Code: \(listErr.pointee.code), Msg: \(msg), ConnectionLoss: \(isConnLoss)")
                    idevice_error_free(listErr)

                    if isConnLoss && attempt < 2 {
                        if self.reconnectAfcClient(&afc, reason: remotePath) {
                            continue
                        }
                    }

                    completion(isObjectNotFound ? .confirmedMissing : .unknown)
                    return
                }

                completion(.unknown)
                return
            }
        }
    }

    func listFiles(remotePath: String, completion: @escaping ([String]?) -> Void) {
        Logger.shared.log("[DeviceManager] listFiles called for: \(remotePath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)

            guard afc != nil else {
                Logger.shared.log("[DeviceManager] ERROR: AFC client is nil for listFiles")
                completion(nil)
                return
            }
            
            defer {
                if let currentAfc = afc {
                    afc_client_free(currentAfc)
                }
            }

            for attempt in 1...2 {
                var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
                var count: Int = 0
                
                let err = afc_list_directory(afc, remotePath, &entries, &count)
                
                if err == nil {
                    var files: [String] = []
                    if let list = entries {
                        for i in 0..<count {
                            if let ptr = list[i] {
                                let name = String(cString: ptr)
                                if name != "." && name != ".." {
                                    files.append(name)
                                }
                            }
                        }
                        free(entries)
                    }
                    completion(files)
                    return
                }

                if let listErr = err {
                    let msg = listErr.pointee.message != nil ? String(cString: listErr.pointee.message!) : "No message"
                    let isConnLoss = self.isConnectionLossError(listErr)
                    Logger.shared.log("[DeviceManager] afc_list_directory failed. Code: \(listErr.pointee.code), Msg: \(msg), ConnectionLoss: \(isConnLoss)")
                    idevice_error_free(listErr)

                    if isConnLoss && attempt < 2 {
                        if self.reconnectAfcClient(&afc, reason: remotePath) {
                            continue
                        }
                    }
                }

                completion(nil)
                return
            }
        }
    }
    
    
    
    func awaitAFCOperation(_ semaphore: DispatchSemaphore, timeoutSeconds: TimeInterval, step: String) -> Bool {
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            Logger.shared.log("[DeviceManager] TIMEOUT: \(step) did not respond within \(Int(timeoutSeconds))s; aborting to avoid freeze")
            return false
        }
        return true
    }
}
