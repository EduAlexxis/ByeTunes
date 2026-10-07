import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

struct LRCLIBResult: Codable, Identifiable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LyricsSearchService: String, CaseIterable, Identifiable {
    case lrclib
    case musixmatch
    case netease

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lrclib:
            return "LRCLIB"
        case .musixmatch:
            return "Musixmatch"
        case .netease:
            return "NetEase"
        }
    }
}

struct LyricsSearchResult: Identifiable {
    let id: String
    let service: LyricsSearchService
    let title: String
    let artist: String
    let album: String?
    let durationMs: Int?
    let hasSyncedLyrics: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    let remoteID: Int?
}

extension SongMetadata {
    static func searchLyrics(query: String, service: LyricsSearchService) async -> [LyricsSearchResult] {
        switch service {
        case .lrclib:
            return await searchLyricsFromLRCLIB(query: query)
        case .musixmatch:
            return await searchLyricsFromMusixMatch(query: query)
        case .netease:
            return await searchLyricsFromNetEase(query: query)
        }
    }

    static func resolveLyrics(for result: LyricsSearchResult, songTitle: String, songArtist: String) async -> String? {
        switch result.service {
        case .lrclib:
            let raw = result.syncedLyrics ?? result.plainLyrics ?? ""
            let cleaned = cleanLyrics(raw, title: songTitle, artist: songArtist)
            return cleaned.isEmpty ? nil : cleaned
        case .musixmatch:
            guard let remoteID = result.remoteID else { return nil }
            return await fetchLyricsFromMusixMatchTrackID(remoteID, title: songTitle, artist: songArtist)
        case .netease:
            guard let remoteID = result.remoteID else { return nil }
            return await fetchLyricsFromNetEaseTrackID(remoteID, title: songTitle, artist: songArtist)
        }
    }

    private static func searchLyricsFromLRCLIB(query: String) async -> [LyricsSearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://lrclib.net/api/search?q=\(encodedQuery)") else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("ByeTunes/2.5 (https://github.com/EduAlexxis/ByeTunes)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await SongMetadataNetworking.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard statusCode == 200 else { return [] }
            let results = try JSONDecoder().decode([LRCLIBResult].self, from: data)
            return results.map {
                LyricsSearchResult(
                    id: "lrclib-\($0.id)",
                    service: .lrclib,
                    title: $0.trackName ?? "Unknown Title",
                    artist: $0.artistName ?? "Unknown Artist",
                    album: $0.albumName,
                    durationMs: $0.duration.map { Int($0 * 1000) },
                    hasSyncedLyrics: $0.syncedLyrics?.isEmpty == false,
                    plainLyrics: $0.plainLyrics,
                    syncedLyrics: $0.syncedLyrics,
                    remoteID: $0.id
                )
            }
        } catch {
            Logger.shared.log("[SongMetadata] LRCLIB search failed: \(error)")
            return []
        }
    }

    private static func searchLyricsFromMusixMatch(query: String) async -> [LyricsSearchResult] {
        do {
            guard let response = try await performMusixMatchRequest(
                endpoint: "track.search",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "f_has_lyrics", value: "true"),
                    URLQueryItem(name: "page_size", value: "20"),
                    URLQueryItem(name: "page", value: "1")
                ]
            ) else {
                return []
            }

            guard
                let message = response["message"] as? [String: Any],
                let body = message["body"] as? [String: Any],
                let trackList = body["track_list"] as? [[String: Any]]
            else {
                return []
            }

            let results = trackList.compactMap { entry -> LyricsSearchResult? in
                guard
                    let track = entry["track"] as? [String: Any],
                    let trackID = track["track_id"] as? Int
                else {
                    return nil
                }

                return LyricsSearchResult(
                    id: "musixmatch-\(trackID)",
                    service: .musixmatch,
                    title: (track["track_name"] as? String) ?? "Unknown Title",
                    artist: (track["artist_name"] as? String) ?? "Unknown Artist",
                    album: track["album_name"] as? String,
                    durationMs: (track["track_length"] as? Int).map { $0 * 1000 },
                    hasSyncedLyrics: (track["has_richsync"] as? Int == 1) || (track["has_subtitles"] as? Int == 1),
                    plainLyrics: nil,
                    syncedLyrics: nil,
                    remoteID: trackID
                )
            }
            return results
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch search failed: \(error)")
            return []
        }
    }

    private static func searchLyricsFromNetEase(query: String) async -> [LyricsSearchResult] {
        do {
            guard let response = try await performNetEaseEapiRequest(
                path: "/eapi/cloudsearch/pc",
                payload: [
                    "s": query,
                    "type": "1",
                    "limit": "20",
                    "offset": "0"
                ]
            ) else {
                return []
            }

            guard
                let result = response["result"] as? [String: Any],
                let songs = result["songs"] as? [[String: Any]]
            else {
                return []
            }

            let results = songs.compactMap { song -> LyricsSearchResult? in
                guard let id = song["id"] as? Int else { return nil }
                let artists = (song["ar"] as? [[String: Any]]) ?? (song["artists"] as? [[String: Any]]) ?? []
                let artistNames = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                let albumName = (song["al"] as? [String: Any])?["name"] as? String ?? (song["album"] as? [String: Any])?["name"] as? String

                return LyricsSearchResult(
                    id: "netease-\(id)",
                    service: .netease,
                    title: (song["name"] as? String) ?? "Unknown Title",
                    artist: artistNames.isEmpty ? "Unknown Artist" : artistNames,
                    album: albumName,
                    durationMs: song["dt"] as? Int,
                    hasSyncedLyrics: true,
                    plainLyrics: nil,
                    syncedLyrics: nil,
                    remoteID: id
                )
            }
            return results
        } catch {
            Logger.shared.log("[SongMetadata] NetEase search failed: \(error)")
            return []
        }
    }

    private static func fetchLyricsFromMusixMatchTrackID(_ trackID: Int, title: String, artist: String) async -> String? {
        do {
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
            if !cleaned.isEmpty {
                Logger.shared.log("[SongMetadata] Found lyrics from Musixmatch")
            }
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            Logger.shared.log("[SongMetadata] Musixmatch lyrics resolve failed: \(error)")
            return nil
        }
    }

    private static func fetchLyricsFromNetEaseTrackID(_ trackID: Int, title: String, artist: String) async -> String? {
        do {
            guard let lyricsResponse = try await performNetEaseEapiRequest(
                path: "/eapi/song/lyric/v1",
                payload: [
                    "id": String(trackID),
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
                    Logger.shared.log("[SongMetadata] Found lyrics from NetEase")
                    return cleaned
                }
            }
            return nil
        } catch {
            Logger.shared.log("[SongMetadata] NetEase lyrics resolve failed: \(error)")
            return nil
        }
    }
}
