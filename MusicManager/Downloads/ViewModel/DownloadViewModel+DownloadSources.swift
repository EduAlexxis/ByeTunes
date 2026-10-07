import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func downloadWithFallbacks(track: DownloadTrack) async throws -> BackendDownloadOutcome {
        let resolvedSource = await resolvedPrimaryDownloadSource(for: track)
        log("Using source URL (\(resolvedSource.platform.displayName)): \(resolvedSource.url)")

        let candidates = try await primaryCandidates(for: resolvedSource, track: track)
        if !candidates.isEmpty {
            do {
                if let outcome = try await executeCandidatesUntilSuccess(
                    candidates,
                    trackID: track.id,
                    suggestedName: "\(track.artistLine) - \(track.name)",
                    fallbackExtension: "flac"
                ) {
                    return outcome
                }
            } catch {
                if Task.isCancelled {
                    throw error
                }
                log("Primary backend candidates failed for \(track.name): \(error.localizedDescription)")
            }
        }

        if resolvedSource.platform != .deezer {
            log("Attempting last-resort Deezer mapping for \(track.name)...")
            let deezerURL = await mapTrackToDeezerURL(track)
            if deezerURL == nil && resolvedSource.platform == .appleMusic {
                throw DownloadError.trackNotFound
            }
            if let deezerURL {
                let deezerSource = DownloadSourceChoice(
                    platform: .deezer,
                    url: deezerURL,
                    backendGenreSource: DownloadPlatform.deezer.backendGenreSource
                )
                let deezerCandidates = try await primaryCandidates(for: deezerSource, track: track)
                if !deezerCandidates.isEmpty {
                    if let outcome = try await executeCandidatesUntilSuccess(
                        deezerCandidates,
                        trackID: track.id,
                        suggestedName: "\(track.artistLine) - \(track.name)",
                        fallbackExtension: "flac"
                    ) {
                        return outcome
                    }
                }
            }
        }

        throw DownloadError.mappingFailed("All configured download backends failed.")
    }

    func preferredDownloadSource(for sourceURL: String) -> DownloadSourceChoice {
        let platform: DownloadPlatform
        if sourceURL.contains("music.apple.com") || sourceURL.contains("itunes.apple.com") {
            platform = .appleMusic
        } else if sourceURL.contains("spotify.com") {
            platform = .spotify
        } else if sourceURL.contains("deezer.com") {
            platform = .deezer
        } else if sourceURL.contains("qobuz.com") {
            platform = .qobuz
        } else if sourceURL.contains("tidal.com") {
            platform = .tidal
        } else if sourceURL.contains("music.amazon.") || sourceURL.contains("amazon.com/music") || sourceURL.contains("amazon.com/gp/product/") {
            platform = .amazon
        } else if sourceURL.contains("pandora.com") {
            platform = .pandora
        } else if sourceURL.contains("soundcloud.com") {
            platform = .soundcloud
        } else if sourceURL.contains("music.youtube.com") || sourceURL.contains("youtube.com") || sourceURL.contains("youtu.be") {
            platform = .youtubeMusic
        } else {
            platform = .unknown
        }
        return DownloadSourceChoice(platform: platform, url: sourceURL, backendGenreSource: platform.backendGenreSource)
    }

    func resolvedPrimaryDownloadSource(for track: DownloadTrack) async -> DownloadSourceChoice {
        var source = preferredDownloadSource(for: track.sourceURL)
        if source.platform == .appleMusic, let deezerURL = await mapTrackToDeezerURL(track) {
            source = DownloadSourceChoice(
                platform: .deezer,
                url: deezerURL,
                backendGenreSource: DownloadPlatform.deezer.backendGenreSource
            )
        }
        return source
    }

    func primaryCandidates(
        for source: DownloadSourceChoice,
        track: DownloadTrack? = nil
    ) async throws -> [BackendCandidate] {
        guard source.platform == .appleMusic || source.platform == .spotify || source.platform == .deezer || source.platform == .unknown else {
            return []
        }
        return try await downloadBackendCandidates(for: source, track: track)
    }

    func downloadBackendCandidates(
        for source: DownloadSourceChoice,
        track: DownloadTrack? = nil
    ) async throws -> [BackendCandidate] {
        let urlString = "\(Config.byeTunesApiUrl)/api/download"
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL(urlString)
        }

        let desiredFormat = desiredDownloadFormat()
        let wantsSyncedLyrics =
            UserDefaults.standard.bool(forKey: "fetchLyrics") ||
            UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")

        func makeCandidate(label: String, format: String, overrideURL: String? = nil) throws -> BackendCandidate {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "url": overrideURL ?? source.url,
                "format": format,
                "genreSource": source.backendGenreSource,
                "syncedLyrics": wantsSyncedLyrics
            ])
            return BackendCandidate(label: label, request: request, customDownload: nil, requestedFormat: format)
        }

        var candidates = [try makeCandidate(label: Config.downloadBackendLabel, format: desiredFormat)]
        if desiredFormat.lowercased() != "mp3" {
            candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (MP3 Fallback)", format: "mp3"))
        }

        if source.platform == .appleMusic, let track, let deezerURL = await mapTrackToDeezerURL(track) {
            candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (Deezer)", format: desiredFormat, overrideURL: deezerURL))
            if desiredFormat.lowercased() != "mp3" {
                candidates.append(try makeCandidate(label: "\(Config.downloadBackendLabel) (Deezer MP3 Fallback)", format: "mp3", overrideURL: deezerURL))
            }
        }

        return candidates
    }

    func desiredDownloadFormat() -> String {
        return UserDefaults.standard.string(forKey: "yoinkifyFormat") ?? "flac"
    }

    func executeCandidatesUntilSuccess(
        _ candidates: [BackendCandidate],
        trackID: String,
        suggestedName: String,
        fallbackExtension: String
    ) async throws -> BackendDownloadOutcome? {
        guard !candidates.isEmpty else {
            throw DownloadError.mappingFailed("No usable backend request was created.")
        }

        var lastError: Error = DownloadError.mappingFailed("All backend requests failed.")

        for candidate in candidates {
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            do {
                let candidateFallbackExtension = DownloadSupport.fallbackExtension(
                    forRequestedFormat: candidate.requestedFormat,
                    defaultingTo: fallbackExtension
                )
                let fileURL: URL
                if let customDownload = candidate.customDownload {
                    fileURL = try await customDownload(trackID, suggestedName, candidateFallbackExtension)
                } else if let request = candidate.request {
                    fileURL = try await executeDownloadRequest(
                        request,
                        trackID: trackID,
                        backendLabel: candidate.label,
                        suggestedName: suggestedName,
                        fallbackExtension: candidateFallbackExtension,
                        requestedFormat: candidate.requestedFormat
                    )
                } else {
                    throw DownloadError.mappingFailed("No usable backend request was created for \(candidate.label).")
                }
                log("\(candidate.label) backend succeeded.")
                BackendHealthStore.shared.recordSuccess(label: candidate.label)
                return BackendDownloadOutcome(fileURL: fileURL, backendLabel: candidate.label)
            } catch {
                if Task.isCancelled {
                    throw error
                }
                if (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                lastError = error
                log("\(candidate.label) backend failed: \(error.localizedDescription)")
                BackendHealthStore.shared.recordFailure(label: candidate.label, error: error.localizedDescription)
            }
        }

        throw lastError
    }

    func executeDownloadRequest(
        _ request: URLRequest,
        trackID: String,
        backendLabel: String,
        suggestedName: String,
        fallbackExtension: String,
        requestedFormat: String? = nil,
        depth: Int = 0
    ) async throws -> URL {
        if depth > 4 {
            throw DownloadError.mappingFailed("Too many redirect/manifest hops.")
        }

        var request = request
        applyZarzHeaders(to: &request)
        log("Requesting \(redactedDownloadURLString(request.url))")

        log("executeDownloadRequest track=\(trackID) backend=\(backendLabel) depth=\(depth) method=\(request.httpMethod ?? "GET")")
        let (data, response) = try await fetchDataWithProgress(for: request) { [weak self] progress, speedBps in
            self?.updateVisibleDownloadProgress(progress, speedBps: speedBps, trackID: trackID)
        }
        try validateHTTP(response: response, data: data)

        if let manifestURL = extractManifestURL(from: data) {
            log("Resolved manifest media URL: \(redactedDownloadURLString(manifestURL))")
            let redirectedRequest = URLRequest(url: manifestURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                trackID: trackID,
                backendLabel: backendLabel,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
                requestedFormat: requestedFormat,
                depth: depth + 1
            )
        }

        if let redirectedURL = extractRedirectURL(from: data) {
            log("Received JSON redirect: \(redactedDownloadURLString(redirectedURL))")
            let redirectedRequest = URLRequest(url: redirectedURL)
            return try await executeDownloadRequest(
                redirectedRequest,
                trackID: trackID,
                backendLabel: backendLabel,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension,
                requestedFormat: requestedFormat,
                depth: depth + 1
            )
        }

        let httpResponse = response as? HTTPURLResponse
        let mimeType = httpResponse?.value(forHTTPHeaderField: "Content-Type")

        guard !data.isEmpty else {
            throw DownloadError.emptyResponse
        }

        if let mimeType, mimeType.contains("application/json"), extractRedirectURL(from: data) == nil {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 json>"
            throw DownloadError.remoteFailure(bodyText)
        }

        recordQualityNoteIfNeeded(trackID: trackID, requestedFormat: requestedFormat, httpResponse: httpResponse)

        let fileExtension = DownloadSupport.fileExtension(for: mimeType, fallback: fallbackExtension)
        return try saveDownloadedData(data, suggestedName: suggestedName, fileExtension: fileExtension)
    }

    func recordQualityNoteIfNeeded(trackID: String, requestedFormat: String?, httpResponse: HTTPURLResponse?) {
        guard let requestedFormat else { return }
        guard let deliveredFormat = httpResponse?.value(forHTTPHeaderField: "X-Audio-Format") else { return }

        guard deliveredFormat.caseInsensitiveCompare(requestedFormat) != .orderedSame else {
            trackQualityNotes.removeValue(forKey: trackID)
            return
        }

        let source = httpResponse?.value(forHTTPHeaderField: "X-Audio-Source")
        let quality = httpResponse?.value(forHTTPHeaderField: "X-Audio-Quality")
        var note = "Requested \(requestedFormat.uppercased()), got \(deliveredFormat.uppercased())"
        if let quality, deliveredFormat.caseInsensitiveCompare("mp3") == .orderedSame {
            note += " \(quality)kbps"
        }
        note += ". Lossless wasn't available for this track"
        if let source {
            note += " (source: \(source.capitalized))"
        }
        trackQualityNotes[trackID] = note
        log("Quality note for \(trackID): \(note)")
    }

    func redactedDownloadURLString(_ url: URL?) -> String {
        guard let url else { return "<unknown>" }
        if url.host?.caseInsensitiveCompare(Config.byeTunesApiHost) == .orderedSame {
            return Config.downloadBackendLabel
        }
        return url.absoluteString
    }

    func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw DownloadError.httpError(http.statusCode, body)
        }
    }

    func extractManifestURL(from data: Data) -> URL? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let manifest = findFirstString(in: obj, matching: ["manifest"]),
           let resolved = decodeManifestMediaURL(manifest) {
            return resolved
        }

        if let direct = findFirstURLString(
            in: obj,
            matching: ["manifest_url", "manifestUrl", "stream_url", "streamUrl", "media_url", "mediaUrl"]
        ), let url = URL(string: direct) {
            return url
        }

        return nil
    }

    func decodeManifestMediaURL(_ manifest: String) -> URL? {
        let candidates = [manifest, manifest.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")]
        for candidate in candidates {
            let padded = padBase64(candidate)
            guard let data = Data(base64Encoded: padded) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let urls = obj["urls"] as? [String], let first = urls.first, let url = URL(string: first) {
                return url
            }
            let keys = ["url", "manifest_url", "media_url"]
            for key in keys {
                if let value = obj[key] as? String, let url = URL(string: value) {
                    return url
                }
            }
        }
        return nil
    }

    func findFirstURLString(in object: Any, matching preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = findFirstString(in: object, matching: [key]), URL(string: value) != nil {
                return value
            }
        }

        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let match = findFirstURLString(in: value, matching: preferredKeys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstURLString(in: value, matching: preferredKeys) {
                    return match
                }
            }
        } else if let string = object as? String, URL(string: string) != nil {
            return string
        }

        return nil
    }

    func findFirstString(in object: Any, matching keys: [String]) -> String? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })

        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if normalizedKeys.contains(key.lowercased()), let stringValue = value as? String, !stringValue.isEmpty {
                    return stringValue
                }
            }

            for value in dictionary.values {
                if let match = findFirstString(in: value, matching: keys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstString(in: value, matching: keys) {
                    return match
                }
            }
        }

        return nil
    }

    func findFirstBool(in object: Any, matching keys: [String]) -> Bool? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })

        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                guard normalizedKeys.contains(key.lowercased()) else { continue }
                if let boolValue = value as? Bool {
                    return boolValue
                }
                if let stringValue = value as? String {
                    switch stringValue.lowercased() {
                    case "true", "1", "yes":
                        return true
                    case "false", "0", "no":
                        return false
                    default:
                        break
                    }
                }
                if let intValue = value as? Int {
                    return intValue != 0
                }
            }

            for value in dictionary.values {
                if let match = findFirstBool(in: value, matching: keys) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findFirstBool(in: value, matching: keys) {
                    return match
                }
            }
        }

        return nil
    }

    func padBase64(_ value: String) -> String {
        let remainder = value.count % 4
        guard remainder != 0 else { return value }
        return value + String(repeating: "=", count: 4 - remainder)
    }

    func extractRedirectURL(from data: Data) -> URL? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let value = findFirstURLString(
            in: obj,
            matching: [
                "url",
                "download_url",
                "downloadUrl",
                "redirect_url",
                "redirectUrl",
                "direct_download_url",
                "directDownloadUrl",
                "stream_url",
                "streamUrl",
                "media_url",
                "mediaUrl",
                "link"
            ]
        ), let url = URL(string: value) {
            return url
        }
        return nil
    }

    func saveDownloadedData(_ data: Data, suggestedName: String, fileExtension: String) throws -> URL {
        let base = DownloadSupport.tidyFilename(suggestedName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadCache", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var url = directory.appendingPathComponent("\(base).\(fileExtension)")
            var suffix = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = directory.appendingPathComponent("\(base)-\(suffix).\(fileExtension)")
                suffix += 1
            }

            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw DownloadError.fileSaveFailed(error.localizedDescription)
        }
    }

    func persistDownloadedSongIfNeeded(_ song: SongMetadata) -> SongMetadata {
        guard UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else {
            return song
        }

        let directory = SongMetadata.persistentDownloadsDirectory()
        let needsSecurityScope = directory.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log("Failed to create persistent download folder: \(error.localizedDescription)")
            return song
        }

        let ext = song.localURL.pathExtension.isEmpty ? "flac" : song.localURL.pathExtension
        let baseName = DownloadSupport.tidyFilename("\(song.artist) - \(song.title)")
        var destination = directory.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) && destination.path != song.localURL.path {
            destination = directory.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
            suffix += 1
        }

        if destination.path == song.localURL.path {
            return song
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try AudioTagWriter.copyKeptSong(song, to: destination)
            var updatedSong = song
            updatedSong.localURL = destination
            return updatedSong
        } catch {
            log("Failed to persist downloaded song \(song.title): \(error.localizedDescription)")
            return song
        }
    }

    func matchKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func mapTrackToDeezerURL(_ track: DownloadTrack) async -> String? {
        let titleKey = matchKey(track.name)
        let artistKeys = track.artistLine
            .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
            .map { matchKey($0) }
            .filter { !$0.isEmpty }
        guard !titleKey.isEmpty else { return nil }

        let queries = ["\(track.name) \(track.artistLine)", track.name]
        for query in queries {
            let results = await SongMetadata.searchDeezer(query: query, limit: 25)
            let match = results.first { result in
                let resultTitle = matchKey(result.title)
                let resultArtist = matchKey(result.artist.name)
                let titleMatches = resultTitle == titleKey || resultTitle.hasPrefix(titleKey) || titleKey.hasPrefix(resultTitle)
                let artistMatches = artistKeys.isEmpty || artistKeys.contains { $0 == resultArtist || $0.contains(resultArtist) || resultArtist.contains($0) }
                return titleMatches && artistMatches
            }
            if let match {
                let url = match.link ?? "https://www.deezer.com/track/\(match.id)"
                log("Deezer match for \(track.name) - \(track.artistLine): \(url)")
                return url
            }
        }
        log("No Deezer match found for \(track.name) - \(track.artistLine)")
        return nil
    }

    func fetchDataWithProgress(
        for request: URLRequest,
        onProgress: @escaping (Double, Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let downloader = ProgressiveDataFetcher()
        return try await downloader.fetch(request: request) { progress, speedBps in
            Task { @MainActor in
                onProgress(progress, speedBps)
            }
        }
    }

    func applyZarzHeaders(to request: inout URLRequest) {
        guard request.url?.host?.contains("zarz.moe") == true else { return }
        request.setValue("SpotiFLAC-Mobile/4.5.5", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
    }
}
