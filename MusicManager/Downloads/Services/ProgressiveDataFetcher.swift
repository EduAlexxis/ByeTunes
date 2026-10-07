import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

final class ProgressiveDataFetcher: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var receivedData = Data()
    private var response: URLResponse?
    private var expectedLength: Int64 = -1
    private var progressHandler: ((Double, Double) -> Void)?
    private var session: URLSession?
    private var startedAt: CFAbsoluteTime = 0
    private var lastSampleAt: CFAbsoluteTime = 0
    private var lastSampleBytes: Int = 0
    private var smoothedSpeedBps: Double = 0
    private var task: URLSessionDataTask?

    func fetch(
        request: URLRequest,
        progress: @escaping (Double, Double) -> Void
    ) async throws -> (Data, URLResponse) {
        progressHandler = progress
        receivedData = Data()
        expectedLength = -1
        response = nil
        startedAt = CFAbsoluteTimeGetCurrent()
        lastSampleAt = startedAt
        lastSampleBytes = 0
        smoothedSpeedBps = 0

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        self.expectedLength = response.expectedContentLength
        if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(0, 0)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsedSinceLastSample = max(now - lastSampleAt, 0.001)
        let bytesSinceLastSample = max(receivedData.count - lastSampleBytes, 0)
        let instantaneousSpeedBps = Double(bytesSinceLastSample) / elapsedSinceLastSample

        if smoothedSpeedBps == 0 {
            smoothedSpeedBps = instantaneousSpeedBps
        } else {
            smoothedSpeedBps = (smoothedSpeedBps * 0.65) + (instantaneousSpeedBps * 0.35)
        }

        lastSampleAt = now
        lastSampleBytes = receivedData.count

        if expectedLength > 0 {
            let fraction = Double(receivedData.count) / Double(expectedLength)
            if let progressHandler {
                let value = max(0, min(fraction, 1))
                DispatchQueue.main.async {
                    progressHandler(value, self.smoothedSpeedBps)
                }
            }
        } else if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(0, self.smoothedSpeedBps)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
        }

        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }

        guard let response else {
            continuation?.resume(throwing: DownloadError.emptyResponse)
            continuation = nil
            return
        }

        if let progressHandler {
            DispatchQueue.main.async {
                progressHandler(1, self.smoothedSpeedBps)
            }
        }
        continuation?.resume(returning: (receivedData, response))
        continuation = nil
    }
}
