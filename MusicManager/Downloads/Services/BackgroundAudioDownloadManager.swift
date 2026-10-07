import Foundation

struct BackgroundDownloadRequestContext: Codable {
    let trackID: String
    let backendLabel: String
    let suggestedName: String
    let fallbackExtension: String
}

struct BackgroundDownloadResult {
    let fileURL: URL
    let response: URLResponse
    let context: BackgroundDownloadRequestContext
}

enum BackgroundDownloadManagerError: LocalizedError {
    case missingResponse
    case missingContext
    case missingDownloadedFile

    var errorDescription: String? {
        switch self {
        case .missingResponse:
            return "The background download finished without a response."
        case .missingContext:
            return "The background download lost its task context."
        case .missingDownloadedFile:
            return "The background download finished without a file."
        }
    }
}

final class BackgroundAudioDownloadManager: NSObject {
    static let shared = BackgroundAudioDownloadManager()
    static let sessionIdentifier = "com.musicmanager.downloads.background"

    private struct PersistedPendingResult: Codable {
        let trackID: String
        let filePath: String
        let backendLabel: String
        let suggestedName: String
        let fallbackExtension: String
        let statusCode: Int
        let url: String?
        let headerFields: [String: String]
        let createdAt: Date
    }

    private static let pendingResultsDefaultsKey = "BackgroundAudioDownloadManager.pendingResults.v1"
    private static let pendingResultMaxAge: TimeInterval = 24 * 60 * 60

    private struct TransferState {
        var progressHandler: ((Double, Double) -> Void)?
        var completionHandler: ((Result<BackgroundDownloadResult, Error>) -> Void)?
        var startedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        var lastSampleAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        var lastSampleBytes: Int64 = 0
        var smoothedSpeedBps: Double = 0
        var downloadedFileURL: URL?
        var lastProgress: Double = 0
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

    private let stateQueue = DispatchQueue(label: "BackgroundAudioDownloadManager.state")
    private var states: [Int: TransferState] = [:]
    private var pendingResultsByTrackID: [String: Result<BackgroundDownloadResult, Error>] = [:]
    private var finishedTaskIDs: Set<Int> = []
    private var backgroundEventsCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
        stateQueue.async {
            _ = self.loadPersistedPendingResults()
        }
    }

    func setBackgroundEventsCompletionHandler(_ handler: (() -> Void)?) {
        stateQueue.async {
            self.log("Set background events completion handler: \(handler == nil ? "nil" : "non-nil")")
            self.backgroundEventsCompletionHandler = handler
        }
    }

    func download(
        request: URLRequest,
        context: BackgroundDownloadRequestContext,
        progress: ((Double, Double) -> Void)? = nil
    ) async throws -> BackgroundDownloadResult {
        try await withCheckedThrowingContinuation { continuation in
            startDownload(request: request, context: context, progress: progress) { result in
                continuation.resume(with: result)
            }
        }
    }

    func bindToActiveDownload(
        forTrackID trackID: String,
        progress: ((Double, Double) -> Void)? = nil,
        completion: @escaping (Result<BackgroundDownloadResult, Error>) -> Void
    ) async -> Bool {
        if let pendingResult = await consumePendingResult(forTrackID: trackID) {
            log("Delivering pending result immediately for track \(trackID)")
            DispatchQueue.main.async {
                completion(pendingResult)
            }
            return true
        }

        let tasks = await allTasks()
        log("Attempting bind for track \(trackID). sessionTasks=\(tasks.count)")
        guard let task = tasks.first(where: { task in
            guard let context = self.context(for: task) else { return false }
            return context.trackID == trackID
        }) else {
            log("No active background task found to bind for track \(trackID)")
            return false
        }

        stateQueue.async {
            var state = self.states[task.taskIdentifier] ?? TransferState()
            state.progressHandler = progress
            state.completionHandler = completion
            self.states[task.taskIdentifier] = state
            self.log("Bound to background task id=\(task.taskIdentifier) state=\(self.describe(task.state)) track=\(trackID)")
        }
        return true
    }

    func cancelDownloads(forTrackID trackID: String) async {
        let tasks = await allTasks()
        let matchingTasks = tasks.filter { task in
            guard let context = self.context(for: task) else { return false }
            return context.trackID == trackID
        }

        guard !matchingTasks.isEmpty else {
            log("No active background tasks to cancel for track \(trackID)")
            return
        }

        for task in matchingTasks {
            log("Cancelling background task id=\(task.taskIdentifier) track=\(trackID)")
            task.cancel()
        }
    }

    private func startDownload(
        request: URLRequest,
        context: BackgroundDownloadRequestContext,
        progress: ((Double, Double) -> Void)?,
        completion: @escaping (Result<BackgroundDownloadResult, Error>) -> Void
    ) {
        var request = request
        request.allowsExpensiveNetworkAccess = true
        request.allowsConstrainedNetworkAccess = true
        request.timeoutInterval = max(request.timeoutInterval, 300)

        let task = session.downloadTask(with: request)
        task.taskDescription = encode(context: context)
        log("Starting background task id=\(task.taskIdentifier) track=\(context.trackID) backend=\(context.backendLabel) url=\(redactedURLString(request.url))")

        stateQueue.async {
            self.states[task.taskIdentifier] = TransferState(
                progressHandler: progress,
                completionHandler: completion
            )
        }

        task.resume()
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                self.log("Fetched all background session tasks: \(tasks.map { "\($0.taskIdentifier)=\(self.describe($0.state))" }.joined(separator: ", "))")
                continuation.resume(returning: tasks)
            }
        }
    }

    private func encode(context: BackgroundDownloadRequestContext) -> String? {
        guard let data = try? JSONEncoder().encode(context) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func context(for task: URLSessionTask) -> BackgroundDownloadRequestContext? {
        guard let raw = task.taskDescription?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BackgroundDownloadRequestContext.self, from: raw)
    }

    private func finishTask(
        _ task: URLSessionTask,
        result: Result<BackgroundDownloadResult, Error>
    ) {
        stateQueue.async {
            guard !self.finishedTaskIDs.contains(task.taskIdentifier) else {
                self.log("Ignoring duplicate completion for background task id=\(task.taskIdentifier)")
                return
            }
            self.finishedTaskIDs.insert(task.taskIdentifier)
            let completion = self.states.removeValue(forKey: task.taskIdentifier)?.completionHandler
            if completion == nil, let trackID = self.context(for: task)?.trackID {
                self.pendingResultsByTrackID[trackID] = result
                self.log("Stored pending result for task id=\(task.taskIdentifier) track=\(trackID) because no completion handler was attached")
                if case .success(let value) = result {
                    self.persistPendingResult(value)
                }
            }
            self.log("Finishing background task id=\(task.taskIdentifier) result=\(self.describe(result))")
            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    private func consumePendingResult(forTrackID trackID: String) async -> Result<BackgroundDownloadResult, Error>? {
        await withCheckedContinuation { continuation in
            stateQueue.async {
                if let result = self.pendingResultsByTrackID.removeValue(forKey: trackID) {
                    if case .success = result {
                        self.removePersistedPendingResult(forTrackID: trackID)
                    }
                    continuation.resume(returning: result)
                    return
                }

                if let persisted = self.loadPersistedPendingResults()[trackID] {
                    self.removePersistedPendingResult(forTrackID: trackID)
                    if let reconstructed = self.reconstructResult(from: persisted) {
                        self.log("Recovered persisted pending result from disk for track \(trackID)")
                        continuation.resume(returning: .success(reconstructed))
                        return
                    }
                    self.log("Persisted pending result for track \(trackID) referenced a missing file; discarding")
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func persistPendingResult(_ result: BackgroundDownloadResult) {
        let httpResponse = result.response as? HTTPURLResponse
        var headerFields: [String: String] = [:]
        if let httpResponse {
            for (key, value) in httpResponse.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headerFields[key] = value
                }
            }
        }

        let persisted = PersistedPendingResult(
            trackID: result.context.trackID,
            filePath: result.fileURL.path,
            backendLabel: result.context.backendLabel,
            suggestedName: result.context.suggestedName,
            fallbackExtension: result.context.fallbackExtension,
            statusCode: httpResponse?.statusCode ?? 200,
            url: result.response.url?.absoluteString,
            headerFields: headerFields,
            createdAt: Date()
        )

        var all = loadPersistedPendingResults(pruneStale: false)
        all[persisted.trackID] = persisted
        savePersistedPendingResults(all)
        log("Persisted pending result to disk for track \(persisted.trackID)")
    }

    private func removePersistedPendingResult(forTrackID trackID: String) {
        var all = loadPersistedPendingResults(pruneStale: false)
        guard all.removeValue(forKey: trackID) != nil else { return }
        savePersistedPendingResults(all)
    }

    private func loadPersistedPendingResults(pruneStale: Bool = true) -> [String: PersistedPendingResult] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingResultsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: PersistedPendingResult].self, from: data) else {
            return [:]
        }

        guard pruneStale else { return decoded }

        let cutoff = Date().addingTimeInterval(-Self.pendingResultMaxAge)
        let fresh = decoded.filter { $0.value.createdAt > cutoff && FileManager.default.fileExists(atPath: $0.value.filePath) }
        if fresh.count != decoded.count {
            savePersistedPendingResults(fresh)
        }
        return fresh
    }

    private func savePersistedPendingResults(_ results: [String: PersistedPendingResult]) {
        if results.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingResultsDefaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingResultsDefaultsKey)
    }

    private func reconstructResult(from persisted: PersistedPendingResult) -> BackgroundDownloadResult? {
        let fileURL = URL(fileURLWithPath: persisted.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let responseURL = persisted.url.flatMap(URL.init(string:)) ?? fileURL
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: persisted.statusCode,
            httpVersion: nil,
            headerFields: persisted.headerFields
        ) ?? URLResponse(url: responseURL, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)

        let context = BackgroundDownloadRequestContext(
            trackID: persisted.trackID,
            backendLabel: persisted.backendLabel,
            suggestedName: persisted.suggestedName,
            fallbackExtension: persisted.fallbackExtension
        )
        return BackgroundDownloadResult(fileURL: fileURL, response: response, context: context)
    }

    private func saveDownloadedFile(
        from sourceURL: URL,
        response: URLResponse,
        context: BackgroundDownloadRequestContext
    ) throws -> URL {
        let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        let fileExtension = DownloadSupport.fileExtension(for: mimeType, fallback: context.fallbackExtension)
        let base = DownloadSupport.tidyFilename(context.suggestedName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadCache", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var destination = directory.appendingPathComponent("\(base).\(fileExtension)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(suffix).\(fileExtension)")
            suffix += 1
        }

        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    private func log(_ message: String) {
        Logger.shared.log("[BGDownload] \(message)")
    }

    private func redactedURLString(_ url: URL?) -> String {
        guard let url else { return "<unknown>" }
        if url.host?.caseInsensitiveCompare(Config.byeTunesApiHost) == .orderedSame {
            return Config.downloadBackendLabel
        }
        return url.absoluteString
    }

    private func describe(_ state: URLSessionTask.State) -> String {
        switch state {
        case .running: return "running"
        case .suspended: return "suspended"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown"
        }
    }

    private func describe(_ result: Result<BackgroundDownloadResult, Error>) -> String {
        switch result {
        case .success(let value):
            return "success(file=\(value.fileURL.lastPathComponent), track=\(value.context.trackID), backend=\(value.context.backendLabel))"
        case .failure(let error):
            return "failure(\(error.localizedDescription))"
        }
    }
}

extension BackgroundAudioDownloadManager: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return
        }

        stateQueue.async {
            let now = CFAbsoluteTimeGetCurrent()
            var state = self.states[downloadTask.taskIdentifier] ?? {
                var recoveredState = TransferState()
                recoveredState.lastSampleAt = now
                recoveredState.lastSampleBytes = max(totalBytesWritten - bytesWritten, 0)
                return recoveredState
            }()

            let elapsed = max(now - state.lastSampleAt, 0.001)
            let bytesDelta = max(totalBytesWritten - state.lastSampleBytes, 0)
            let instantaneousSpeed = Double(bytesDelta) / elapsed

            if state.smoothedSpeedBps == 0 {
                state.smoothedSpeedBps = instantaneousSpeed
            } else {
                state.smoothedSpeedBps = (state.smoothedSpeedBps * 0.65) + (instantaneousSpeed * 0.35)
            }

            state.lastSampleAt = now
            state.lastSampleBytes = totalBytesWritten
            self.states[downloadTask.taskIdentifier] = state

            let expectedCandidates: [Int64] = [
                totalBytesExpectedToWrite,
                downloadTask.countOfBytesExpectedToReceive,
                downloadTask.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
            ]
            let expectedBytes = expectedCandidates.first(where: { $0 > 0 }) ?? 0

            let measuredFraction: Double
            if expectedBytes > 0 {
                measuredFraction = Double(totalBytesWritten) / Double(expectedBytes)
            } else if downloadTask.progress.fractionCompleted.isFinite && downloadTask.progress.fractionCompleted > 0 {
                measuredFraction = downloadTask.progress.fractionCompleted
            } else {
                measuredFraction = state.lastProgress
            }
            let fraction = max(state.lastProgress, max(0, min(measuredFraction, 1)))
            state.lastProgress = fraction
            self.states[downloadTask.taskIdentifier] = state

            let progressHandler = state.progressHandler
            let speed = state.smoothedSpeedBps
            DispatchQueue.main.async {
                progressHandler?(fraction, speed)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let context = context(for: downloadTask) else {
            log("didFinishDownloadingTo missing context for task id=\(downloadTask.taskIdentifier)")
            finishTask(downloadTask, result: .failure(BackgroundDownloadManagerError.missingContext))
            return
        }

        guard let response = downloadTask.response else {
            log("didFinishDownloadingTo missing response for task id=\(downloadTask.taskIdentifier) track=\(context.trackID)")
            finishTask(downloadTask, result: .failure(BackgroundDownloadManagerError.missingResponse))
            return
        }

        do {
            let fileURL = try saveDownloadedFile(from: location, response: response, context: context)
            stateQueue.async {
                var state = self.states[downloadTask.taskIdentifier] ?? TransferState()
                state.downloadedFileURL = fileURL
                self.states[downloadTask.taskIdentifier] = state
            }
        } catch {
            log("Failed to save downloaded file for task id=\(downloadTask.taskIdentifier) track=\(context.trackID): \(error.localizedDescription)")
            finishTask(downloadTask, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            log("Task completed with error id=\(task.taskIdentifier) state=\(describe(task.state)) error=\(error.localizedDescription)")
            finishTask(task, result: .failure(error))
            return
        }

        guard let context = context(for: task) else {
            log("Task completed without context id=\(task.taskIdentifier)")
            finishTask(task, result: .failure(BackgroundDownloadManagerError.missingContext))
            return
        }

        guard let response = task.response else {
            log("Task completed without response id=\(task.taskIdentifier) track=\(context.trackID)")
            finishTask(task, result: .failure(BackgroundDownloadManagerError.missingResponse))
            return
        }

        stateQueue.async {
            guard let fileURL = self.states[task.taskIdentifier]?.downloadedFileURL else {
                self.log("Task completed without downloaded file id=\(task.taskIdentifier) track=\(context.trackID)")
                self.finishTask(task, result: .failure(BackgroundDownloadManagerError.missingDownloadedFile))
                return
            }

            let result = BackgroundDownloadResult(fileURL: fileURL, response: response, context: context)
            self.finishTask(task, result: .success(result))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        stateQueue.async {
            self.log("Background URLSession finished delivering events")
            let handler = self.backgroundEventsCompletionHandler
            self.backgroundEventsCompletionHandler = nil
            DispatchQueue.main.async {
                handler?()
            }
        }
    }
}
