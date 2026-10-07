import Foundation

final class MetadataBackgroundURLSession: NSObject {
    static let shared = MetadataBackgroundURLSession()
    static let sessionIdentifier = "com.musicmanager.metadatafetch.background"

    private struct TransferState {
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        var downloadedData: Data?
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let stateQueue = DispatchQueue(label: "MetadataBackgroundURLSession.state")
    private var states: [Int: TransferState] = [:]
    private var backgroundEventsCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    func setBackgroundEventsCompletionHandler(_ handler: (() -> Void)?) {
        stateQueue.async {
            self.log("Set background events completion handler: \(handler == nil ? "nil" : "non-nil")")
            self.backgroundEventsCompletionHandler = handler
        }
    }

    private static let requestTimeoutSeconds: TimeInterval = 90

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.allowsExpensiveNetworkAccess = true
        request.allowsConstrainedNetworkAccess = true

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            stateQueue.async {
                self.states[task.taskIdentifier] = TransferState(continuation: continuation)
            }
            task.resume()
            self.scheduleTimeout(for: task)
        }
    }

    func cancelAllTasks() {
        session.getAllTasks { tasks in
            guard !tasks.isEmpty else { return }
            self.log("Manual cancel: aborting \(tasks.count) in-flight task(s)")
            for task in tasks {
                task.cancel()
            }
        }
    }

    private func scheduleTimeout(for task: URLSessionDownloadTask) {
        stateQueue.asyncAfter(deadline: .now() + Self.requestTimeoutSeconds) { [weak self] in
            guard let self, self.states[task.taskIdentifier] != nil else { return }
            self.log("Request timed out after \(Int(Self.requestTimeoutSeconds))s for task id=\(task.taskIdentifier); cancelling")
            task.cancel()
        }
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    private func log(_ message: String) {
        Logger.shared.log("[BGMetadataSession] \(message)")
    }
}

extension MetadataBackgroundURLSession: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let data = (try? Data(contentsOf: location)) ?? Data()
        stateQueue.async {
            guard var state = self.states[downloadTask.taskIdentifier] else {
                self.log("didFinishDownloadingTo for untracked task id=\(downloadTask.taskIdentifier); discarding")
                return
            }
            state.downloadedData = data
            self.states[downloadTask.taskIdentifier] = state
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard let state = self.states.removeValue(forKey: task.taskIdentifier) else {
                self.log("Task completed for untracked task id=\(task.taskIdentifier); discarding")
                return
            }

            if let error {
                self.log("Task completed with error id=\(task.taskIdentifier): \(error.localizedDescription)")
                state.continuation?.resume(throwing: error)
                return
            }

            guard let response = task.response else {
                state.continuation?.resume(throwing: URLError(.badServerResponse))
                return
            }

            state.continuation?.resume(returning: (state.downloadedData ?? Data(), response))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        stateQueue.async {
            self.log("Background metadata URLSession finished delivering events")
            let handler = self.backgroundEventsCompletionHandler
            self.backgroundEventsCompletionHandler = nil
            DispatchQueue.main.async {
                handler?()
            }
        }
    }
}

enum SongMetadataNetworking {
    @TaskLocal static var useBackgroundSession: Bool = false

    private static let retryDelays: [UInt64] = [600_000_000, 1_500_000_000]
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    private static let retryableURLErrors: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost
    ]

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod?.uppercased() ?? "GET"
        let canRetry = method == "GET" || method == "HEAD"
        return try await withRetry(canRetry: canRetry) {
            if useBackgroundSession {
                return try await MetadataBackgroundURLSession.shared.data(for: request)
            }
            return try await URLSession.shared.data(for: request)
        }
    }

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        try await withRetry(canRetry: true) {
            if useBackgroundSession {
                return try await MetadataBackgroundURLSession.shared.data(from: url)
            }
            return try await URLSession.shared.data(from: url)
        }
    }

    private static func withRetry(
        canRetry: Bool,
        _ operation: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let result = try await operation()
                if canRetry,
                   attempt < retryDelays.count,
                   let http = result.1 as? HTTPURLResponse,
                   retryableStatusCodes.contains(http.statusCode) {
                    try await Task.sleep(nanoseconds: retryDelays[attempt])
                    attempt += 1
                    continue
                }
                return result
            } catch let error as URLError where canRetry && attempt < retryDelays.count && retryableURLErrors.contains(error.code) {
                try await Task.sleep(nanoseconds: retryDelays[attempt])
                attempt += 1
            }
        }
    }
}
