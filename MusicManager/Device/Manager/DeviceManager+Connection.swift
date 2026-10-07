import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Connection
extension DeviceManager {
    func resetConnectionHandles() {
        if let oldProvider = provider {
            idevice_provider_free(oldProvider)
            provider = nil
        }
        if let oldHandshake = rpHandshake {
            rsd_handshake_free(oldHandshake)
            rpHandshake = nil
        }
        if let oldAdapter = rpAdapter {
            adapter_close(oldAdapter)
            adapter_free(oldAdapter)
            rpAdapter = nil
        }
    }

    func canStillReachDevice() -> Bool {
        guard hasActiveTransport else { return false }
        var probeClient: HeartbeatClientHandle?
        let err = connectHeartbeatClient(&probeClient)
        guard err == IdeviceSuccess, let probeClient else {
            return false
        }
        heartbeat_client_free(probeClient)
        return true
    }

    func makeSocketAddress(port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(port)
        inet_pton(AF_INET, DEVICE_HOST, &addr.sin_addr)
        return addr
    }

    @discardableResult
    func connectHeartbeatClient(_ client: inout HeartbeatClientHandle?) -> IdeviceErrorCode {
        if requiresRPPairingTunnel, let rpAdapter, let rpHandshake {
            return heartbeat_connect_rsd(rpAdapter, rpHandshake, &client)
        }
        return heartbeat_connect(provider, &client)
    }

    @discardableResult
    func connectLockdownClient(_ client: inout LockdowndClientHandle?) -> IdeviceErrorCode {
        if requiresRPPairingTunnel, let rpAdapter, let rpHandshake {
            return lockdownd_connect_rsd(rpAdapter, rpHandshake, &client)
        }
        return lockdownd_connect(provider, &client)
    }

    @discardableResult
    func connectNotificationProxyClient(_ client: inout NotificationProxyClientHandle?) -> IdeviceErrorCode {
        if requiresRPPairingTunnel, let rpAdapter, let rpHandshake {
            return notification_proxy_connect_rsd(rpAdapter, rpHandshake, &client)
        }
        return notification_proxy_connect(provider, &client)
    }

    @discardableResult
    func connectAfcClient(_ client: inout AfcClientHandle?) -> IdeviceErrorCode {
        if requiresRPPairingTunnel, let rpAdapter, let rpHandshake {
            var lastError: IdeviceErrorCode = IdeviceSuccess
            for attempt in 0..<10 {
                lastError = afc_client_connect_rsd(rpAdapter, rpHandshake, &client)
                if lastError == IdeviceSuccess && client != nil {
                    return lastError
                }
                if attempt < 9 {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
            return lastError
        }
        return afc_client_connect(provider, &client)
    }

    func establishRPPairingTunnel() -> Bool {
        var rpPairingPtr: RpPairingFileHandle?
        let readErr = rp_pairing_file_read(rpPairingFile.path, &rpPairingPtr)
        guard readErr == IdeviceSuccess, let rpPairingHandle = rpPairingPtr else {
            self.logOnce("[DeviceManager] ERROR: Failed to read RPPairing file. Err: \(String(describing: readErr))", key: "connection_status")
            return false
        }
        defer { rp_pairing_file_free(rpPairingHandle) }

        let resolvedPort = RemotePairingDiscovery.resolvePort() ?? RP_PAIRING_PORT
        if resolvedPort != RP_PAIRING_PORT {
            self.logOnce("[DeviceManager] RPPairing service resolved to port \(resolvedPort) via Bonjour (default \(RP_PAIRING_PORT))", key: "connection_status")
        }

        var addr = makeSocketAddress(port: resolvedPort)
        let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let tunnelErr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                tunnel_create_rppairing(
                    sockaddrPointer,
                    addrLen,
                    "Music-Provider",
                    rpPairingHandle,
                    nil,
                    nil,
                    &rpAdapter,
                    &rpHandshake
                )
            }
        }

        guard tunnelErr == nil, rpAdapter != nil, rpHandshake != nil else {
            if let err = tunnelErr {
                let msg = err.pointee.message != nil ? String(cString: err.pointee.message!) : "No message"
                self.logOnce("[DeviceManager] ERROR: RPPairing tunnel failed. Code: \(err.pointee.code), SubCode: \(err.pointee.sub_code), Msg: \(msg)", key: "connection_status")
                idevice_error_free(err)
            } else {
                self.logOnce("[DeviceManager] ERROR: RPPairing tunnel failed (nil error pointer but adapter/handshake nil)", key: "connection_status")
            }
            resetConnectionHandles()
            return false
        }

        self.logOnce("[DeviceManager] RPPairing tunnel established via \(DEVICE_HOST):\(resolvedPort)", key: "connection_status")
        return true
    }

    func startHeartbeat(forceReconnect: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if !forceReconnect {
            if connectionStatus == "Connecting..." {
                completion?(false)
                return
            }
            let timeSinceLastAttempt = Date().timeIntervalSince(lastHeartbeatAttemptStartedAt)
            if connectionStatus != "Connecting..." && !heartbeatReady {
                guard timeSinceLastAttempt >= 10.0 else {
                    completion?(false)
                    return
                }
            }
        }

        reconnectCoordinationLock.lock()
        if isReconnecting {
            if let completion {
                pendingReconnectCompletions.append(completion)
            }
            reconnectCoordinationLock.unlock()
            return
        }
        isReconnecting = true
        reconnectCoordinationLock.unlock()

        func finish(_ success: Bool) {
            reconnectCoordinationLock.lock()
            isReconnecting = false
            let waiters = pendingReconnectCompletions
            pendingReconnectCompletions = []
            reconnectCoordinationLock.unlock()
            completion?(success)
            for waiter in waiters {
                waiter(success)
            }
        }

        heartbeatSessionID &+= 1
        refreshExpectedPairingFileState()
        guard hasValidExpectedPairingFile else {
            let message = "Invalid \(expectedPairingFileTitle)"
            Logger.shared.log("[DeviceManager] \(message). Import the correct file before connecting.")
            DispatchQueue.main.async {
                self.connectionStatus = message
                self.heartbeatReady = false
                finish(false)
            }
            return
        }

        if !forceReconnect && heartbeatReady && hasActiveTransport && canStillReachDevice() {
            DispatchQueue.main.async {
                finish(true)
            }
            return
        }

        lastHeartbeatAttemptStartedAt = Date()
        if Thread.isMainThread {
            self.connectionStatus = "Connecting..."
            self.heartbeatReady = false
        } else {
            DispatchQueue.main.async {
                self.connectionStatus = "Connecting..."
                self.heartbeatReady = false
            }
        }

        resetConnectionHandles()


        heartbeatThread = Thread {
            let sessionID = self.heartbeatSessionID
            let outcomeLock = NSLock()
            var outcomeReported = false
            let outcomeSemaphore = DispatchSemaphore(value: 0)

            func reportOutcome(success: Bool) {
                outcomeLock.lock()
                let alreadyReported = outcomeReported
                outcomeReported = true
                outcomeLock.unlock()
                guard !alreadyReported else { return }

                DispatchQueue.main.async {
                    guard sessionID == self.heartbeatSessionID else { return }
                    self.connectionStatus = success ? "Connection Lost" : "Connection Failed"
                    self.heartbeatReady = false
                }
            }

            self.establishHeartbeat { success in
                reportOutcome(success: success)
                outcomeSemaphore.signal()
            }

            if outcomeSemaphore.wait(timeout: .now() + self.heartbeatEstablishTimeout) == .timedOut {
                Logger.shared.log("[DeviceManager] Heartbeat establishment timed out after \(Int(self.heartbeatEstablishTimeout))s; treating as failed.")
                reportOutcome(success: false)
            }
        }
        heartbeatThread?.name = "HeartbeatThread"
        heartbeatThread?.start()

        let sessionIDForPoll = heartbeatSessionID
        DispatchQueue.global().async {
            let pollInterval: TimeInterval = 0.5
            let maxIterations = Int((self.heartbeatEstablishTimeout + 2) / pollInterval)
            for _ in 0..<maxIterations {
                if self.heartbeatReady && self.hasActiveTransport {
                    DispatchQueue.main.async { finish(true) }
                    return
                }
                guard sessionIDForPoll == self.heartbeatSessionID else {
                    DispatchQueue.main.async { finish(false) }
                    return
                }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            DispatchQueue.main.async { finish(false) }
        }
    }

    func stopHeartbeat() {
        heartbeatSessionID &+= 1
        resetConnectionHandles()
        DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
            self.heartbeatReady = false
        }
    }

    func establishHeartbeat(_ completion: @escaping (Bool) -> Void) {
        let sessionID = heartbeatSessionID

        if requiresRPPairingTunnel {
            guard establishRPPairingTunnel() else {
                completion(false)
                return
            }
        } else {
            var addr = makeSocketAddress(port: UInt16(LOCKDOWN_PORT))

            var pairingPtr: IdevicePairingFile?
            let pairingErr = idevice_pairing_file_read(regularPairingFile.path, &pairingPtr)
            guard pairingErr == IdeviceSuccess, pairingPtr != nil else {
                self.logOnce("[DeviceManager] ERROR: Failed to read pairing file. Err: \(String(describing: pairingErr))", key: "connection_status")
                completion(false)
                return
            }

            let providerErr = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    idevice_tcp_provider_new(sockaddrPointer, pairingPtr, "Music-Provider", &provider)
                }
            }

            if provider == nil {
                self.logOnce("[DeviceManager] ERROR: Provider is nil. Err: \(String(describing: providerErr))", key: "connection_status")
                completion(false)
                return
            }
        }

        var hbClient: HeartbeatClientHandle?
        let err = connectHeartbeatClient(&hbClient)

        guard err == IdeviceSuccess && hbClient != nil else {
            self.logOnce("[DeviceManager] ERROR: Heartbeat connection failed", key: "connection_status")
            resetConnectionHandles()
            completion(false)
            return
        }

        self.logOnce("[DeviceManager] Heartbeat connected successfully!", key: "connection_status")

        DispatchQueue.main.async {
            self.connectionStatus = "Connected"
            self.heartbeatReady = true
        }

        runHeartbeatMonitorLoop(sessionID: sessionID, initialClient: hbClient)

        if sessionID == heartbeatSessionID {
            resetConnectionHandles()
            completion(true)
        }
    }

    func runHeartbeatMonitorLoop(sessionID: UInt64, initialClient: HeartbeatClientHandle?) {
        var client = initialClient
        var consecutivePoloFailures = 0
        var marcoInterval: UInt64 = 10

        while !Thread.current.isCancelled && sessionID == heartbeatSessionID {
            var newInterval: UInt64 = 0
            let marcoErr = heartbeat_get_marco(client, marcoInterval, &newInterval)

            guard marcoErr == IdeviceSuccess else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }

            if newInterval > 0 {
                marcoInterval = newInterval
            }

            let poloErr = heartbeat_send_polo(client)
            if poloErr == IdeviceSuccess {
                consecutivePoloFailures = 0
                DispatchQueue.main.async {
                    guard sessionID == self.heartbeatSessionID else { return }
                    if !self.heartbeatReady {
                        self.heartbeatReady = true
                        self.connectionStatus = "Connected"
                    }
                }
            } else {
                consecutivePoloFailures += 1
                Logger.shared.log("[DeviceManager] Heartbeat polo failed (\(consecutivePoloFailures)).")

                if consecutivePoloFailures >= 3 {
                    Logger.shared.log("[DeviceManager] Heartbeat unresponsive; reconnecting the heartbeat client without touching the rest of the transport.")
                    heartbeat_client_free(client)

                    var freshClient: HeartbeatClientHandle?
                    let reconnectErr = connectHeartbeatClient(&freshClient)
                    guard reconnectErr == IdeviceSuccess, freshClient != nil else {
                        Logger.shared.log("[DeviceManager] Could not re-establish heartbeat on the existing transport; treating the transport as lost.")
                        return
                    }

                    Logger.shared.log("[DeviceManager] Heartbeat client re-established; transport left untouched.")
                    client = freshClient
                    consecutivePoloFailures = 0
                    marcoInterval = 10
                }
            }
        }

        heartbeat_client_free(client)
    }

    

    
    func sendSyncFinishedNotification() {
        var lockdownd: LockdowndClientHandle?
        let err = connectLockdownClient(&lockdownd)
        
        if err == IdeviceSuccess {
            var port: UInt16 = 0
            var ssl: Bool = false
            _ = lockdownd_start_service(lockdownd, "com.apple.mobile.notification_proxy", &port, &ssl)
            lockdownd_client_free(lockdownd)
        }
    }

    func postRingtoneRefreshNotifications() {
        var npClient: NotificationProxyClientHandle?
        let npErr = connectNotificationProxyClient(&npClient)
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
}
