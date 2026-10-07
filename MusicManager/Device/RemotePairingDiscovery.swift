import Foundation
import Network

enum RemotePairingDiscovery {
    private static let serviceType = "_remotepairing._tcp"

    static func resolvePort(attempts: Int = 3, timeoutPerAttempt: TimeInterval = 2, delayBetweenAttempts: TimeInterval = 1) -> UInt16? {
        for attempt in 0..<attempts {
            if let port = resolvePortOnce(timeout: timeoutPerAttempt) {
                return port
            }
            if attempt < attempts - 1 {
                Thread.sleep(forTimeInterval: delayBetweenAttempts)
            }
        }
        return nil
    }

    private static func resolvePortOnce(timeout: TimeInterval) -> UInt16? {
        let semaphore = DispatchSemaphore(value: 0)
        var resolvedPort: UInt16?
        let lock = NSLock()

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        var connection: NWConnection?
        var finished = false

        func finish(_ port: UInt16?) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            resolvedPort = port
            lock.unlock()
            semaphore.signal()
        }

        browser.browseResultsChangedHandler = { results, _ in
            guard connection == nil, let result = results.first else { return }
            let conn = NWConnection(to: result.endpoint, using: .tcp)
            connection = conn
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(_, port) = conn.currentPath?.remoteEndpoint {
                        finish(port.rawValue)
                    } else {
                        finish(nil)
                    }
                    conn.cancel()
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
        browser.start(queue: .global(qos: .userInitiated))

        _ = semaphore.wait(timeout: .now() + timeout)
        browser.cancel()
        connection?.cancel()

        lock.lock()
        let result = resolvedPort
        lock.unlock()
        return result
    }
}
