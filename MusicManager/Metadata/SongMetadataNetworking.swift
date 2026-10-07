import Foundation

enum SongMetadataNetworking {
    private static let retryDelays: [UInt64] = [600_000_000, 1_500_000_000]
    private static let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    private static let retryableURLErrors: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost
    ]

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = request.httpMethod?.uppercased() ?? "GET"
        let canRetry = method == "GET" || method == "HEAD"
        return try await withRetry(canRetry: canRetry) {
            try await URLSession.shared.data(for: request)
        }
    }

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        try await withRetry(canRetry: true) {
            try await URLSession.shared.data(from: url)
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
