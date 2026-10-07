import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Music App
extension DeviceManager {
    var killMusicBeforeInjectEnabled: Bool {
        return UserDefaults.standard.object(forKey: "killMusicBeforeInject") as? Bool ?? true
    }

    func makeTemporaryProvider(label: String = "Music-Provider-Temp") -> IdeviceProviderHandle? {
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(UInt16(LOCKDOWN_PORT))
        inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr)

        var pairingPtr: IdevicePairingFile?
        _ = idevice_pairing_file_read(regularPairingFile.path, &pairingPtr)
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

    func withTemporaryProvider<T>(
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
    func terminateMusicApp(adapter: AdapterHandle, handshake: RsdHandshakeHandle) -> Bool {
        var appService: AppServiceHandle?
        let appErr = app_service_connect_rsd(adapter, handshake, &appService)
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

    @discardableResult
    func terminateMusicAppIfRunning() -> Bool {
        if requiresRPPairingTunnel {
            guard let rpAdapter, let rpHandshake else {
                Logger.shared.log("[MusicKill] RPPairing tunnel unavailable")
                return false
            }
            return terminateMusicApp(adapter: rpAdapter, handshake: rpHandshake)
        }

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

            return terminateMusicApp(adapter: adapterHandle, handshake: handshakeHandle)
        }
    }
    
    
    
    
}
