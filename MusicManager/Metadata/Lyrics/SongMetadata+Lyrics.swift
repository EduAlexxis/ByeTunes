import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

// MARK: - Lyrics
extension SongMetadata {
    static func cleanLyrics(_ rawLyrics: String, title: String? = nil, artist: String? = nil) -> String {
        var cleaned = rawLyrics.replacingOccurrences(of: #"\[([a-z]+):.*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        
        cleaned = cleaned.replacingOccurrences(of: #"\[\d{2,}:\d{2}(\.\d{2,})?\]"#, with: "", options: .regularExpression)
        
        cleaned = cleaned.replacingOccurrences(of: #"\d+\s+Contributors"#, with: "", options: .regularExpression)
        
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)

        let lines = cleaned.components(separatedBy: .newlines)
        var resultLines: [String] = []
        
        let noiseWords = ["lyrics", "letra", "contributors", "official", "video", "audio"]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let last = resultLines.last, !last.isEmpty {
                    resultLines.append("")
                }
                continue
            }
            
            if let title = title {
                let lowLine = trimmed.lowercased()
                let lowTitle = title.lowercased()
                
                if lowLine == lowTitle {
                    continue
                }
                
                if lowLine.contains(lowTitle) {
                    var remainder = lowLine.replacingOccurrences(of: lowTitle, with: "")
                    for noise in noiseWords {
                        remainder = remainder.replacingOccurrences(of: noise, with: "")
                    }
                    let cleanRemainder = remainder.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                    if cleanRemainder.isEmpty {
                        continue 
                    }
                }
            }
            
            resultLines.append(trimmed)
        }
        
        return resultLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fetchLyricsFromLRCLIB(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        let titleEnc = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artistEnc = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let albumEnc = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let durationSec = durationMs / 1000
        
        let urlString = "https://lrclib.net/api/get?artist_name=\(artistEnc)&track_name=\(titleEnc)&album_name=\(albumEnc)&duration=\(durationSec)"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("ByeTunes/2.5 (https://github.com/EduAlexxis/ByeTunes)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await SongMetadataNetworking.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let lyrics = (json?["plainLyrics"] as? String) ?? (json?["syncedLyrics"] as? String)
            
            if let l = lyrics, !l.isEmpty {
                Logger.shared.log("[SongMetadata] Successfully fetched lyrics from LRCLIB")
                return SongMetadata.cleanLyrics(l, title: title, artist: artist)
            }
        } catch {
            Logger.shared.log("[SongMetadata] LRCLIB fetch failed: \(error)")
        }
        return nil
    }

    static func fetchLyrics(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        if let lrclibLyrics = await fetchLyricsFromLRCLIB(title: title, artist: artist, album: album, durationMs: durationMs) {
            return lrclibLyrics
        }

        if let musixMatchLyrics = await fetchLyricsFromMusixMatch(title: title, artist: artist, album: album, durationMs: durationMs) {
            return musixMatchLyrics
        }

        if let netEaseLyrics = await fetchLyricsFromNetEase(title: title, artist: artist, album: album, durationMs: durationMs) {
            return netEaseLyrics
        }

        return nil
    }

    private static var musixMatchAppURLCache: String?
    private static var musixMatchSecretCache: String?

    private static func fetchLyricsFromMusixMatch(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        do {
            guard let searchResponse = try await performMusixMatchRequest(
                endpoint: "track.search",
                queryItems: [
                    URLQueryItem(name: "q", value: "\(title) \(artist)"),
                    URLQueryItem(name: "f_has_lyrics", value: "true"),
                    URLQueryItem(name: "page_size", value: "5"),
                    URLQueryItem(name: "page", value: "1")
                ]
            ) else {
                return nil
            }

            guard let trackID = bestMusixMatchTrackID(from: searchResponse, title: title, artist: artist, album: album, durationMs: durationMs) else {
                Logger.shared.log("[SongMetadata] Musixmatch search returned no suitable lyric match")
                return nil
            }

            guard let lyricsResponse = try await performMusixMatchRequest(
                endpoint: "track.lyrics.get",
                queryItems: [URLQueryItem(name: "track_id", value: String(trackID))]
            ) else {
                return nil
            }

            guard
                let message = lyricsResponse["message"] as? [String: Any],
                let body = message["body"] as? [String: Any],
                let lyrics = body["lyrics"] as? [String: Any],
                let lyricsBody = lyrics["lyrics_body"] as? String
            else {
                return nil
            }

            let cleaned = cleanLyrics(stripMusixMatchFooter(from: lyricsBody), title: title, artist: artist)
            guard !cleaned.isEmpty else { return nil }

            Logger.shared.log("[SongMetadata] Successfully fetched lyrics from Musixmatch fallback")
            return cleaned
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch fallback failed: \(error)")
            return nil
        }
    }

    static func performMusixMatchRequest(endpoint: String, queryItems: [URLQueryItem]) async throws -> [String: Any]? {
        let baseURLString = "https://www.musixmatch.com/ws/1.1/\(endpoint)"
        let defaultItems: [(String, String)] = [
            ("app_id", "web-desktop-app-v1.0"),
            ("format", "json")
        ]
        let allItems = defaultItems + queryItems.map { ($0.name, $0.value ?? "") }
        let canonicalQuery = allItems
            .map { "\(musixMatchPercentEncode($0.0))=\(musixMatchPercentEncode($0.1))" }
            .joined(separator: "&")
            .replacingOccurrences(of: "%20", with: "+")
            .replacingOccurrences(of: " ", with: "+")
        let canonicalURLString = "\(baseURLString)?\(canonicalQuery)"

        let signature = try await musixMatchSignature(for: canonicalURLString)
        guard let signedURL = URL(string: canonicalURLString + signature) else { return nil }

        var request = URLRequest(url: signedURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode != 200 {
            return nil
        }

        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func bestMusixMatchTrackID(from response: [String: Any], title: String, artist: String, album: String, durationMs: Int) -> Int? {
        guard
            let message = response["message"] as? [String: Any],
            let body = message["body"] as? [String: Any],
            let trackList = body["track_list"] as? [[String: Any]]
        else {
            return nil
        }

        let normalizedTitle = normalizedLyricsMatchValue(title)
        let normalizedArtist = normalizedLyricsMatchValue(artist)
        let normalizedAlbum = normalizedLyricsMatchValue(album)
        let expectedDurationSec = durationMs > 0 ? durationMs / 1000 : nil

        let bestTrack = trackList.compactMap { entry -> (trackID: Int, score: Int)? in
            guard
                let track = entry["track"] as? [String: Any],
                let trackID = track["track_id"] as? Int
            else {
                return nil
            }

            let trackTitle = normalizedLyricsMatchValue(track["track_name"] as? String)
            let trackArtist = normalizedLyricsMatchValue(track["artist_name"] as? String)
            let trackAlbum = normalizedLyricsMatchValue(track["album_name"] as? String)
            let trackLength = track["track_length"] as? Int

            var score = 0

            if trackTitle == normalizedTitle {
                score += 120
            } else if trackTitle.contains(normalizedTitle) || normalizedTitle.contains(trackTitle) {
                score += 70
            }

            if trackArtist == normalizedArtist {
                score += 120
            } else if trackArtist.contains(normalizedArtist) || normalizedArtist.contains(trackArtist) {
                score += 70
            }

            if !normalizedAlbum.isEmpty {
                if trackAlbum == normalizedAlbum {
                    score += 30
                } else if trackAlbum.contains(normalizedAlbum) || normalizedAlbum.contains(trackAlbum) {
                    score += 15
                }
            }

            if let expectedDurationSec, let trackLength, trackLength > 0 {
                score += max(0, 30 - abs(trackLength - expectedDurationSec))
            }

            return (trackID, score)
        }
        .max(by: { $0.score < $1.score })

        guard let bestTrack, bestTrack.score >= 140 else { return nil }
        return bestTrack.trackID
    }

    private static func normalizedLyricsMatchValue(_ value: String?) -> String {
        guard let value else { return "" }
        let lowered = value.lowercased()
        let cleaned = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripMusixMatchFooter(from lyrics: String) -> String {
        if let footerRange = lyrics.range(of: "*******") {
            return String(lyrics[..<footerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var musixMatchUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    }

    private static func musixMatchPercentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func musixMatchSignature(for absoluteURL: String) async throws -> String {
        let secret = try await musixMatchSecret()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd"

        let message = Data((absoluteURL + dateFormatter.string(from: Date())).utf8)
        let key = SymmetricKey(data: Data(secret.utf8))
        let signatureData = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        let signature = signatureData.base64EncodedString()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedSignature = signature.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? signature
        return "&signature=\(encodedSignature)&signature_protocol=sha256"
    }

    private static func musixMatchSecret() async throws -> String {
        if let musixMatchSecretCache, !musixMatchSecretCache.isEmpty {
            return musixMatchSecretCache
        }

        let appURL = try await musixMatchAppURL()
        var request = URLRequest(url: appURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let javascript = String(decoding: data, as: UTF8.self)
        let pattern = #"from\(\s*"(.*?)"\s*\.split"#

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: javascript, range: NSRange(javascript.startIndex..., in: javascript)),
            let encodedRange = Range(match.range(at: 1), in: javascript)
        else {
            throw URLError(.cannotParseResponse)
        }

        let encoded = String(javascript[encodedRange])
        let reversed = String(encoded.reversed())

        guard
            let decodedData = Data(base64Encoded: reversed),
            let secret = String(data: decodedData, encoding: .utf8),
            !secret.isEmpty
        else {
            throw URLError(.cannotDecodeRawData)
        }

        musixMatchSecretCache = secret
        return secret
    }

    private static func musixMatchAppURL() async throws -> URL {
        if let cached = musixMatchAppURLCache, let url = URL(string: cached) {
            return url
        }

        guard let searchURL = URL(string: "https://www.musixmatch.com/search") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: searchURL)
        request.setValue(musixMatchUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("mxm_bab=AB", forHTTPHeaderField: "Cookie")

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let html = String(decoding: data, as: UTF8.self)
        let pattern = #"src="([^"]*/_next/static/chunks/pages/_app-[^"]+\.js)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw URLError(.cannotParseResponse)
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard
            let lastMatch = matches.last,
            let relativeRange = Range(lastMatch.range(at: 1), in: html)
        else {
            throw URLError(.cannotParseResponse)
        }

        let relativePath = String(html[relativeRange])
        let fullURLString: String
        if relativePath.hasPrefix("http://") || relativePath.hasPrefix("https://") {
            fullURLString = relativePath
        } else {
            fullURLString = "https://www.musixmatch.com" + relativePath
        }

        guard let url = URL(string: fullURLString) else {
            throw URLError(.badURL)
        }

        musixMatchAppURLCache = fullURLString
        return url
    }

    private static let netEaseHost = "music.163.com"
    private static let netEaseEapiPathSalt = "-36cd479b6b5-"
    private static let netEaseEapiAESKey = "e82ckenh8dichen8"
    private static let netEaseUserAgent = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154"
    private static let netEaseDefaultDeviceID = "pyncm!"

    private static func fetchLyricsFromNetEase(title: String, artist: String, album: String, durationMs: Int) async -> String? {
        do {
            guard let searchResponse = try await performNetEaseEapiRequest(
                path: "/eapi/cloudsearch/pc",
                payload: [
                    "s": "\(title) \(artist)",
                    "type": "1",
                    "limit": "5",
                    "offset": "0"
                ]
            ) else {
                return nil
            }

            guard let songID = bestNetEaseTrackID(from: searchResponse, title: title, artist: artist, album: album, durationMs: durationMs) else {
                Logger.shared.log("[SongMetadata] NetEase search returned no suitable lyric match")
                return nil
            }

            guard let lyricsResponse = try await performNetEaseEapiRequest(
                path: "/eapi/song/lyric/v1",
                payload: [
                    "id": String(songID),
                    "cp": false,
                    "lv": 0,
                    "tv": 0,
                    "rv": 0,
                    "kv": 0,
                    "yv": 0,
                    "ytv": 0,
                    "yrv": 0
                ]
            ) else {
                return nil
            }

            let lyricCandidates = [
                ((lyricsResponse["lrc"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["klyric"] as? [String: Any])?["lyric"] as? String),
                ((lyricsResponse["yrc"] as? [String: Any])?["lyric"] as? String)
            ]

            for candidate in lyricCandidates {
                guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let cleaned = cleanLyrics(stripTimedLyrics(candidate), title: title, artist: artist)
                if !cleaned.isEmpty {
                    Logger.shared.log("[SongMetadata] Successfully fetched lyrics from NetEase fallback")
                    return cleaned
                }
            }
        } catch {
            Logger.shared.log("[SongMetadata] NetEase fallback failed: \(error)")
        }

        return nil
    }

    static func performNetEaseEapiRequest(path: String, payload: [String: Any]) async throws -> [String: Any]? {
        let apiPath = path.replacingOccurrences(of: "/eapi/", with: "/api/")
        var requestPayload = payload
        requestPayload["header"] = netEaseHeaderJSONString()

        guard let payloadData = try? JSONSerialization.data(withJSONObject: requestPayload, options: []),
              let payloadJSONString = String(data: payloadData, encoding: .utf8) else {
            return nil
        }

        let digestSource = "nobody\(apiPath)use\(payloadJSONString)md5forencrypt"
        let digest = md5Hex(digestSource)
        let saltedPayload = "\(apiPath)\(netEaseEapiPathSalt)\(payloadJSONString)\(netEaseEapiPathSalt)\(digest)"
        guard let encryptedPayload = aesECBHexEncrypt(saltedPayload, key: netEaseEapiAESKey) else {
            return nil
        }

        guard let url = URL(string: "https://\(netEaseHost)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(netEaseUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("", forHTTPHeaderField: "Referer")
        request.setValue("os=iPhone OS; appver=10.0.0; osver=16.2; channel=distribution; deviceId=\(netEaseDefaultDeviceID)", forHTTPHeaderField: "Cookie")
        request.httpBody = "params=\(encryptedPayload)".data(using: .utf8)

        let (data, response) = try await SongMetadataNetworking.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard statusCode == 200 else { return nil }
        if let decryptedData = aesECBHexDecrypt(data, key: netEaseEapiAESKey),
           let json = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] {
            return json
        }

        if let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return rawJSON
        }
        return nil
    }

    private static func netEaseHeaderJSONString() -> String {
        let header: [String: String] = [
            "os": "iPhone OS",
            "appver": "10.0.0",
            "osver": "16.2",
            "channel": "distribution",
            "deviceId": netEaseDefaultDeviceID,
            "requestId": String(Int.random(in: 20_000_000...29_999_999))
        ]

        let data = try? JSONSerialization.data(withJSONObject: header, options: [])
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    private static func bestNetEaseTrackID(from response: [String: Any], title: String, artist: String, album: String, durationMs: Int) -> Int? {
        guard
            let result = response["result"] as? [String: Any],
            let songs = result["songs"] as? [[String: Any]]
        else {
            return nil
        }

        let normalizedTitle = normalizedLyricsMatchValue(title)
        let normalizedArtist = normalizedLyricsMatchValue(artist)
        let normalizedAlbum = normalizedLyricsMatchValue(album)

        let bestSong = songs.compactMap { song -> (id: Int, score: Int)? in
            guard let id = song["id"] as? Int else { return nil }

            let songTitle = normalizedLyricsMatchValue(song["name"] as? String)
            let albumName = normalizedLyricsMatchValue((song["album"] as? [String: Any])?["name"] as? String)
            let duration = song["dt"] as? Int
            let artists = (song["ar"] as? [[String: Any]]) ?? (song["artists"] as? [[String: Any]]) ?? []
            let artistNames = artists.compactMap { normalizedLyricsMatchValue($0["name"] as? String) }.joined(separator: " ")

            var score = 0

            if songTitle == normalizedTitle {
                score += 120
            } else if songTitle.contains(normalizedTitle) || normalizedTitle.contains(songTitle) {
                score += 70
            }

            if artistNames == normalizedArtist {
                score += 120
            } else if artistNames.contains(normalizedArtist) || normalizedArtist.contains(artistNames) {
                score += 70
            }

            if !normalizedAlbum.isEmpty {
                if albumName == normalizedAlbum {
                    score += 30
                } else if albumName.contains(normalizedAlbum) || normalizedAlbum.contains(albumName) {
                    score += 15
                }
            }

            if let duration, duration > 0, durationMs > 0 {
                score += max(0, 30 - abs((duration / 1000) - (durationMs / 1000)))
            }

            return (id, score)
        }
        .max(by: { $0.score < $1.score })

        guard let bestSong, bestSong.score >= 140 else { return nil }
        return bestSong.id
    }

    static func stripTimedLyrics(_ lyrics: String) -> String {
        let stripped = lyrics.replacingOccurrences(
            of: #"\[[^\]]*\]|\([0-9]+,[0-9]+\)"#,
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func md5Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func aesECBHexEncrypt(_ string: String, key: String) -> String? {
        guard let encrypted = aesECB(data: Data(string.utf8), key: Data(key.utf8), operation: CCOperation(kCCEncrypt)) else {
            return nil
        }
        return encrypted.map { String(format: "%02x", $0) }.joined()
    }

    private static func aesECBHexDecrypt(_ data: Data, key: String) -> Data? {
        let hexString = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cipherData = dataFromHexString(hexString) else { return nil }
        return aesECB(data: cipherData, key: Data(key.utf8), operation: CCOperation(kCCDecrypt))
    }

    private static func aesECB(data: Data, key: Data, operation: CCOperation) -> Data? {
        let outputLength = data.count + kCCBlockSizeAES128
        var outputData = Data(count: outputLength)
        var bytesProcessed: size_t = 0

        let status = outputData.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        dataBytes.baseAddress,
                        data.count,
                        outputBytes.baseAddress,
                        outputLength,
                        &bytesProcessed
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outputData.removeSubrange(bytesProcessed..<outputData.count)
        return outputData
    }

    private static func dataFromHexString(_ hex: String) -> Data? {
        let cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanHex.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: cleanHex.count / 2)
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = cleanHex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
