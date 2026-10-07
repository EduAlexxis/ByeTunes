import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

// MARK: - Spotify
extension DownloadViewModel {
    func fetchSpotifyToken() async -> String? {
        guard let url = URL(string: "https://open.spotify.com/get_access_token?reason=transport&productType=web_player") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["accessToken"] as? String {
                return token
            }
        } catch {
            log("Failed to fetch Spotify token: \(error.localizedDescription)")
        }
        return nil
    }

    func fetchSpotifyMetadata(url: String) async -> [String: Any]? {
        guard let endpoint = URL(string: "\(Config.byeTunesApiUrl)/api/metadata") else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return json
        } catch {
            log("Spotify metadata fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func spotifyTrackID(fromSpotifyURL spotifyURL: String) -> String? {
        firstRegexCapture(in: spotifyURL, pattern: #"track/([a-zA-Z0-9]+)"#, group: 1)
    }

    func downloadTrack(fromMetadataItem item: [String: Any], fallbackArtistLine: String, fallbackAlbumName: String, fallbackArtworkURL: URL?, sourceContext: DownloadTrack.SourceContext, albumIdentifier: String?) -> DownloadTrack? {
        guard let trackURLString = item["spotifyUrl"] as? String,
              let trackID = spotifyTrackID(fromSpotifyURL: trackURLString) else { return nil }
        let trackArtworkURL = (item["albumArt"] as? String).flatMap(URL.init(string:)) ?? fallbackArtworkURL
        return DownloadTrack(
            id: trackID,
            name: item["name"] as? String ?? "Unknown Title",
            artistLine: (item["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackArtistLine,
            albumName: item["album"] as? String ?? fallbackAlbumName,
            artworkURL: trackArtworkURL,
            isExplicit: item["explicit"] as? Bool ?? false,
            sourceURL: "https://open.spotify.com/track/\(trackID)",
            sourceContext: sourceContext,
            provider: .metadata,
            artistIdentifier: nil,
            albumIdentifier: albumIdentifier,
            previewURL: nil
        )
    }

    func fetchSpotifyTrack(id: String, sourceURL: String) async -> DownloadTrack? {
        if let json = await fetchSpotifyMetadata(url: sourceURL), json["type"] as? String == "track" {
            let artistLine = json["artist"] as? String ?? "Unknown Artist"
            let albumName = json["album"] as? String ?? "Unknown Album"
            let artworkURL = (json["albumArt"] as? String).flatMap(URL.init(string:))
            return DownloadTrack(
                id: id,
                name: json["name"] as? String ?? "Unknown Title",
                artistLine: artistLine,
                albumName: albumName,
                artworkURL: artworkURL,
                isExplicit: json["explicit"] as? Bool ?? false,
                sourceURL: sourceURL,
                sourceContext: .song,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: nil,
                previewURL: nil
            )
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/tracks/\(id)") else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    let name = json["name"] as? String ?? "Unknown Title"
                    let artists = json["artists"] as? [[String: Any]] ?? []
                    let artistLine = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    let album = json["album"] as? [String: Any]
                    let albumName = album?["name"] as? String ?? "Unknown Album"
                    let artworkURLString = (album?["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    let explicit = json["explicit"] as? Bool ?? false
                    let previewURLString = json["preview_url"] as? String
                    let previewURL = previewURLString.flatMap(URL.init(string:))
                    
                    return DownloadTrack(
                        id: id,
                        name: name,
                        artistLine: artistLine.isEmpty ? "Unknown Artist" : artistLine,
                        albumName: albumName,
                        artworkURL: artworkURL,
                        isExplicit: explicit,
                        sourceURL: sourceURL,
                        sourceContext: .song,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: album?["id"] as? String,
                        previewURL: previewURL
                    )
                }
            } catch {
                log("Spotify API track fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyTrackFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    func extractSpotifyJSONLD(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let jsonString = firstRegexCapture(in: html, pattern: pattern, group: 1) else {
            return nil
        }
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func fetchSpotifyTrackFromPublicPage(sourceURL: String, fallbackID: String) async -> DownloadTrack? {
        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var title = "Unknown Title"
            var artist = "Unknown Artist"
            var albumName = "Unknown Album"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    title = name
                }
                if let artists = jsonld["byArtist"] as? [[String: Any]] {
                    artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                } else if let artistObj = jsonld["byArtist"] as? [String: Any] {
                    artist = artistObj["name"] as? String ?? "Unknown Artist"
                }
                if let albumObj = jsonld["inAlbum"] as? [String: Any],
                   let aName = albumObj["name"] as? String {
                    albumName = aName
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if title == "Unknown Title" || artist == "Unknown Artist" || albumName == "Unknown Album" {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if title == "Unknown Title", let ogTitleClean = ogTitle {
                    if let range = ogTitleClean.range(of: " - song", options: .caseInsensitive) {
                        title = String(ogTitleClean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let range = ogTitleClean.range(of: " - album", options: .caseInsensitive) {
                        title = String(ogTitleClean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if ogTitleClean.contains("| Spotify") {
                        title = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        title = ogTitleClean
                    }
                }
                
                if let desc = ogDescription {
                    let parts = desc.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if artist == "Unknown Artist", parts.count >= 1 {
                        var rawArtist = parts[0]
                        if rawArtist.hasPrefix("Listen to ") {
                            rawArtist = rawArtist.replacingOccurrences(of: #"Listen to .*? on Spotify\.\s*"#, with: "", options: .regularExpression)
                        }
                        if !rawArtist.isEmpty {
                            artist = rawArtist
                        }
                    }
                    if albumName == "Unknown Album", parts.count >= 3 {
                        let p1Lower = parts[1].lowercased()
                        if p1Lower != "song" && p1Lower != "single" {
                            let hasSongIndicator = parts.contains { $0.lowercased() == "song" || $0.lowercased() == "single" }
                            if hasSongIndicator {
                                albumName = parts[1]
                            }
                        }
                    }
                }
                
                if artist == "Unknown Artist", let ogTitleClean = ogTitle {
                    if let byRange = ogTitleClean.range(of: "by ", options: .backwards) {
                        let afterBy = ogTitleClean[byRange.upperBound...]
                        let cleanArtist = afterBy.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanArtist.isEmpty {
                            artist = cleanArtist
                        }
                    }
                }
                
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            return DownloadTrack(
                id: fallbackID,
                name: title,
                artistLine: artist,
                albumName: albumName,
                artworkURL: artworkURL,
                isExplicit: false,
                sourceURL: sourceURL,
                sourceContext: .song,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: nil,
                previewURL: nil
            )
        } catch {
            log("Spotify public page track fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchSpotifyAlbum(id: String, sourceURL: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let json = await fetchSpotifyMetadata(url: sourceURL) {
            let albumName = json["name"] as? String ?? "Unknown Album"
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            let rawTracks = json["tracks"] as? [[String: Any]] ?? []
            let artistLine = rawTracks.first.flatMap { $0["albumArtist"] as? String ?? $0["artist"] as? String } ?? "Unknown Artist"

            let albumResult = DownloadAlbum(
                id: id,
                name: albumName,
                artistLine: artistLine,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: id
            )

            let tracks = rawTracks.compactMap {
                downloadTrack(fromMetadataItem: $0, fallbackArtistLine: artistLine, fallbackAlbumName: albumName, fallbackArtworkURL: artworkURL, sourceContext: .album, albumIdentifier: id)
            }

            if !tracks.isEmpty {
                return (albumResult, tracks)
            }
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/albums/\(id)") else { return nil }
            var albumRequest = URLRequest(url: url)
            albumRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (albumData, response) = try await session.data(for: albumRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: albumData) as? [String: Any] {
                    
                    let albumName = json["name"] as? String ?? "Unknown Album"
                    let artists = json["artists"] as? [[String: Any]] ?? []
                    let artistLine = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    let albumResult = DownloadAlbum(
                        id: id,
                        name: albumName,
                        artistLine: artistLine.isEmpty ? "Unknown Artist" : artistLine,
                        artworkURL: artworkURL,
                        sourceURL: sourceURL,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: id
                    )
                    
                    var tracks: [DownloadTrack] = []

                    if let tracksContainer = json["tracks"] as? [String: Any],
                       let items = tracksContainer["items"] as? [[String: Any]] {
                        for item in items {
                            if let trackID = item["id"] as? String {
                                let trackName = item["name"] as? String ?? "Unknown Title"
                                let trackArtists = item["artists"] as? [[String: Any]] ?? []
                                let trackArtistLine = trackArtists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                                let explicit = item["explicit"] as? Bool ?? false
                                let trackURL = "https://open.spotify.com/track/\(trackID)"

                                tracks.append(DownloadTrack(
                                    id: trackID,
                                    name: trackName,
                                    artistLine: trackArtistLine.isEmpty ? artistLine : trackArtistLine,
                                    albumName: albumName,
                                    artworkURL: artworkURL,
                                    isExplicit: explicit,
                                    sourceURL: trackURL,
                                    sourceContext: .album,
                                    provider: .metadata,
                                    artistIdentifier: nil,
                                    albumIdentifier: id,
                                    previewURL: (item["preview_url"] as? String).flatMap(URL.init(string:))
                                ))
                            }
                        }
                    }

                    return (albumResult, tracks)
                }
            } catch {
                log("Spotify API album fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyAlbumFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    func fetchSpotifyAlbumFromPublicPage(sourceURL: String, fallbackID: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let embedURL = URL(string: "https://open.spotify.com/embed/album/\(fallbackID)") {
            do {
                let (data, _) = try await session.data(from: embedURL)
                if let html = String(data: data, encoding: .utf8), !html.isEmpty,
                   let parsed = parseSpotifyEmbedHTML(in: html, fallbackID: fallbackID, sourceURL: sourceURL, sourceContext: .album) {
                    return parsed
                }
            } catch {
                log("Spotify public page album embed fetch failed: \(error.localizedDescription)")
            }
        }

        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var albumName = "Unknown Album"
            var artistName = "Unknown Artist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    albumName = name
                }
                if let artists = jsonld["byArtist"] as? [[String: Any]] {
                    artistName = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                } else if let artistObj = jsonld["byArtist"] as? [String: Any] {
                    artistName = artistObj["name"] as? String ?? "Unknown Artist"
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if albumName == "Unknown Album" || artistName == "Unknown Artist" || artworkURL == nil {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if let ogTitleClean = ogTitle {
                    albumName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let range = albumName.range(of: " - album", options: .caseInsensitive) {
                        albumName = String(albumName[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                if let desc = ogDescription {
                    let parts = desc.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count >= 1 {
                        var rawArtist = parts[0]
                        if rawArtist.hasPrefix("Listen to ") {
                            rawArtist = rawArtist.replacingOccurrences(of: #"Listen to .*? on Spotify\.\s*"#, with: "", options: .regularExpression)
                        }
                        if !rawArtist.isEmpty {
                            artistName = rawArtist
                        }
                    }
                }
                
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            let albumResult = DownloadAlbum(
                id: fallbackID,
                name: albumName,
                artistLine: artistName,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: fallbackID
            )
            
            let tracks = extractSpotifyTracksFromHTML(in: html, fallbackArtist: artistName, fallbackAlbumName: albumName, artworkURL: artworkURL, sourceContext: .album)
            let finalTracks = tracks.isEmpty ? [
                DownloadTrack(
                    id: fallbackID,
                    name: albumName,
                    artistLine: artistName,
                    albumName: albumName,
                    artworkURL: artworkURL,
                    isExplicit: false,
                    sourceURL: sourceURL,
                    sourceContext: .album,
                    provider: .metadata,
                    artistIdentifier: nil,
                    albumIdentifier: fallbackID,
                    previewURL: nil
                )
            ] : tracks
            return (albumResult, finalTracks)
        } catch {
            log("Spotify public page album failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchSpotifyPlaylistFromPublicPage(sourceURL: String, fallbackID: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let embedURL = URL(string: "https://open.spotify.com/embed/playlist/\(fallbackID)") {
            do {
                let (data, _) = try await session.data(from: embedURL)
                if let html = String(data: data, encoding: .utf8), !html.isEmpty,
                   let parsed = parseSpotifyEmbedHTML(in: html, fallbackID: fallbackID, sourceURL: sourceURL, sourceContext: .song) {
                    var enrichedAlbum = parsed.album
                    let creator = parsed.album.artistLine
                    let trackCount = parsed.tracks.count
                    let desc = "Playlist • \(creator) • \(trackCount) items"
                    enrichedAlbum = DownloadAlbum(
                        id: enrichedAlbum.id,
                        name: enrichedAlbum.name,
                        artistLine: desc,
                        artworkURL: enrichedAlbum.artworkURL,
                        sourceURL: enrichedAlbum.sourceURL,
                        provider: enrichedAlbum.provider,
                        artistIdentifier: enrichedAlbum.artistIdentifier,
                        albumIdentifier: enrichedAlbum.albumIdentifier
                    )
                    return (enrichedAlbum, parsed.tracks)
                }
            } catch {
                log("Spotify public page playlist embed fetch failed: \(error.localizedDescription)")
            }
        }

        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var playlistName = "Unknown Playlist"
            var description = "Spotify Playlist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    playlistName = name
                }
                if let desc = jsonld["description"] as? String {
                    description = desc
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if playlistName == "Unknown Playlist" || artworkURL == nil {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let ogDescription = extractHTMLMetaContent(property: "og:description", in: html) ??
                                    extractHTMLMetaContent(name: "description", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if playlistName == "Unknown Playlist", let ogTitleClean = ogTitle {
                    playlistName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if description == "Spotify Playlist", let desc = ogDescription {
                    description = desc
                }
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            let playlistResult = DownloadAlbum(
                id: fallbackID,
                name: playlistName,
                artistLine: description,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: fallbackID
            )
            
            let tracks = extractSpotifyTracksFromHTML(in: html, fallbackArtist: "Unknown Artist", fallbackAlbumName: playlistName, artworkURL: artworkURL, sourceContext: .song)
            return (playlistResult, tracks)
        } catch {
            log("Spotify public page playlist fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchSpotifyArtistFromPublicPage(sourceURL: String, fallbackID: String) async -> DownloadArtist? {
        guard let url = URL(string: sourceURL) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            try validateHTTP(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else { return nil }
            
            var artistName = "Unknown Artist"
            var artworkURL: URL?
            
            if let jsonld = extractSpotifyJSONLD(in: html) {
                if let name = jsonld["name"] as? String {
                    artistName = name
                }
                if let img = jsonld["image"] as? String {
                    artworkURL = URL(string: img)
                }
            }
            
            if artistName == "Unknown Artist" {
                let ogTitle = extractHTMLMetaContent(property: "og:title", in: html) ??
                              extractHTMLMetaContent(name: "twitter:title", in: html) ??
                              extractHTMLTagContent(tag: "title", in: html)
                
                let artwork = extractHTMLMetaContent(property: "og:image", in: html)
                
                if let ogTitleClean = ogTitle {
                    artistName = ogTitleClean.replacingOccurrences(of: "| Spotify", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if artworkURL == nil {
                    artworkURL = artwork.flatMap(URL.init(string:))
                }
            }
            
            return DownloadArtist(
                id: fallbackID,
                name: artistName,
                provider: .metadata,
                artworkURL: artworkURL
            )
        } catch {
            log("Spotify public page artist fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchSpotifyPlaylist(id: String, sourceURL: String) async -> (DownloadAlbum, [DownloadTrack])? {
        if let json = await fetchSpotifyMetadata(url: sourceURL) {
            let playlistName = json["name"] as? String ?? "Unknown Playlist"
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            let rawTracks = json["tracks"] as? [[String: Any]] ?? []
            let description = "Playlist • \(rawTracks.count) items"

            let playlistResult = DownloadAlbum(
                id: id,
                name: playlistName,
                artistLine: description,
                artworkURL: artworkURL,
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: id
            )

            let tracks = rawTracks.compactMap {
                downloadTrack(fromMetadataItem: $0, fallbackArtistLine: "Unknown Artist", fallbackAlbumName: playlistName, fallbackArtworkURL: artworkURL, sourceContext: .song, albumIdentifier: nil)
            }

            if !tracks.isEmpty {
                return (playlistResult, tracks)
            }
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/playlists/\(id)") else { return nil }
            var playlistRequest = URLRequest(url: url)
            playlistRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (playlistData, response) = try await session.data(for: playlistRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: playlistData) as? [String: Any] {
                    
                    let playlistName = json["name"] as? String ?? "Unknown Playlist"
                    let description = json["description"] as? String ?? "Spotify Playlist"
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    let playlistResult = DownloadAlbum(
                        id: id,
                        name: playlistName,
                        artistLine: description,
                        artworkURL: artworkURL,
                        sourceURL: sourceURL,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: id
                    )
                    
                    var tracks: [DownloadTrack] = []

                    if let tracksContainer = json["tracks"] as? [String: Any],
                       let items = tracksContainer["items"] as? [[String: Any]] {
                        for item in items {
                            if let track = item["track"] as? [String: Any],
                               let trackID = track["id"] as? String {
                                let trackName = track["name"] as? String ?? "Unknown Title"
                                let trackArtists = track["artists"] as? [[String: Any]] ?? []
                                let trackArtistLine = trackArtists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                                let explicit = track["explicit"] as? Bool ?? false
                                let trackURL = "https://open.spotify.com/track/\(trackID)"
                                let trackAlbum = track["album"] as? [String: Any]
                                let trackAlbumName = trackAlbum?["name"] as? String ?? "Unknown Album"
                                let trackArtworkURLString = (trackAlbum?["images"] as? [[String: Any]])?.first?["url"] as? String
                                let trackArtworkURL = trackArtworkURLString.flatMap(URL.init(string:))

                                tracks.append(DownloadTrack(
                                    id: trackID,
                                    name: trackName,
                                    artistLine: trackArtistLine.isEmpty ? "Unknown Artist" : trackArtistLine,
                                    albumName: trackAlbumName,
                                    artworkURL: trackArtworkURL ?? artworkURL,
                                    isExplicit: explicit,
                                    sourceURL: trackURL,
                                    sourceContext: .song,
                                    provider: .metadata,
                                    artistIdentifier: nil,
                                    albumIdentifier: trackAlbum?["id"] as? String,
                                    previewURL: (track["preview_url"] as? String).flatMap(URL.init(string:))
                                ))
                            }
                        }
                    }

                    return (playlistResult, tracks)
                }
            } catch {
                log("Spotify API playlist fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyPlaylistFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    func fetchSpotifyArtist(id: String, sourceURL: String) async -> DownloadArtist? {
        if let json = await fetchSpotifyMetadata(url: sourceURL),
           let name = json["name"] as? String {
            let artworkURL = (json["image"] as? String).flatMap(URL.init(string:))
            return DownloadArtist(
                id: id,
                name: name,
                provider: .metadata,
                artworkURL: artworkURL
            )
        }
        if let token = await fetchSpotifyToken() {
            guard let url = URL(string: "https://api.spotify.com/v1/artists/\(id)") else { return nil }
            var artistRequest = URLRequest(url: url)
            artistRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (artistData, response) = try await session.data(for: artistRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: artistData) as? [String: Any] {
                    
                    let name = json["name"] as? String ?? "Unknown Artist"
                    let artworkURLString = (json["images"] as? [[String: Any]])?.first?["url"] as? String
                    let artworkURL = artworkURLString.flatMap(URL.init(string:))
                    
                    return DownloadArtist(
                        id: id,
                        name: name,
                        provider: .metadata,
                        artworkURL: artworkURL
                    )
                }
            } catch {
                log("Spotify API artist fetch failed: \(error.localizedDescription)")
            }
        }
        return await fetchSpotifyArtistFromPublicPage(sourceURL: sourceURL, fallbackID: id)
    }

    func extractHTMLMetaContent(property: String, in html: String) -> String? {
        let patterns = [
            #"<meta[^>]*property=["']\#(property)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']\#(property)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let value = firstRegexCapture(in: html, pattern: pattern, group: 1) {
                return htmlDecoded(value)
            }
        }

        return nil
    }

    func extractHTMLMetaContent(name: String, in html: String) -> String? {
        let patterns = [
            #"<meta[^>]*name=["']\#(name)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*name=["']\#(name)["'][^>]*>"#
        ]

        for pattern in patterns {
            if let value = firstRegexCapture(in: html, pattern: pattern, group: 1) {
                return htmlDecoded(value)
            }
        }

        return nil
    }

    func extractHTMLTagContent(tag: String, in html: String) -> String? {
        let pattern = #"<\#(tag)[^>]*>(.*?)</\#(tag)>"#
        guard let value = firstRegexCapture(in: html, pattern: pattern, group: 1) else {
            return nil
        }
        return htmlDecoded(value)
    }

    func firstRegexCapture(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[range])
    }

    func htmlDecoded(_ value: String) -> String {
        let data = Data(value.utf8)
        if let decoded = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ).string {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func regexMatches(in text: String, pattern: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard group < match.numberOfRanges,
                  let range = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    func extractSpotifyTracksFromHTML(in html: String, fallbackArtist: String, fallbackAlbumName: String, artworkURL: URL?, sourceContext: DownloadTrack.SourceContext) -> [DownloadTrack] {
        var tracks: [DownloadTrack] = []
        let segments = html.components(separatedBy: "data-testid=\"track-row\"")
        guard segments.count > 1 else { return [] }
        
        for segment in segments.dropFirst() {
            guard let trackID = firstRegexCapture(in: segment, pattern: #"href=["']/track/([a-zA-Z0-9]+)["']"#, group: 1) else {
                continue
            }
            guard let title = firstRegexCapture(in: segment, pattern: #"<span[^>]*>([^<]+)</span>"#, group: 1) else {
                continue
            }

            let artistPattern = #"href=["']/artist/[a-zA-Z0-9]+["'][^>]*>([^<]+)</a>"#
            let artistNames = regexMatches(in: segment, pattern: artistPattern, group: 1)
            let artistLine = artistNames.joined(separator: ", ")
            
            let trackURL = "https://open.spotify.com/track/\(trackID)"
            
            tracks.append(
                DownloadTrack(
                    id: trackID,
                    name: htmlDecoded(title),
                    artistLine: artistLine.isEmpty ? fallbackArtist : htmlDecoded(artistLine),
                    albumName: fallbackAlbumName,
                    artworkURL: artworkURL,
                    isExplicit: false,
                    sourceURL: trackURL,
                    sourceContext: sourceContext,
                    provider: .metadata,
                    artistIdentifier: nil,
                    albumIdentifier: nil,
                    previewURL: nil
                )
            )
        }
        return tracks
    }

    func parseSpotifyEmbedHTML(in html: String, fallbackID: String, sourceURL: String, sourceContext: DownloadTrack.SourceContext) -> (album: DownloadAlbum, tracks: [DownloadTrack])? {
        let pattern = #"<script[^>]*id=["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#
        guard let jsonString = firstRegexCapture(in: html, pattern: pattern, group: 1),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let stateData = state["data"] as? [String: Any],
              let entity = stateData["entity"] as? [String: Any] else {
            return nil
        }
        
        let entityName = entity["name"] as? String ?? entity["title"] as? String ?? "Unknown Name"
        let subtitle = entity["subtitle"] as? String ?? ""
        
        var artworkURL: URL?
        if let coverArt = entity["coverArt"] as? [String: Any],
           let sources = coverArt["sources"] as? [[String: Any]],
           let firstSource = sources.first,
           let urlStr = firstSource["url"] as? String {
            artworkURL = URL(string: urlStr)
        }
        
        let albumResult = DownloadAlbum(
            id: fallbackID,
            name: entityName,
            artistLine: subtitle.isEmpty ? (sourceContext == .album ? "Unknown Artist" : "Spotify Playlist") : subtitle,
            artworkURL: artworkURL,
            sourceURL: sourceURL,
            provider: .metadata,
            artistIdentifier: nil,
            albumIdentifier: fallbackID
        )
        
        var parsedTracks: [DownloadTrack] = []
        if let trackList = entity["trackList"] as? [[String: Any]] {
            for trackObj in trackList {
                let uri = trackObj["uri"] as? String ?? ""
                let trackID: String
                if uri.hasPrefix("spotify:track:") {
                    trackID = String(uri.dropFirst("spotify:track:".count))
                } else {
                    continue
                }
                
                let title = trackObj["title"] as? String ?? "Unknown Title"
                let artists = trackObj["subtitle"] as? String ?? ""
                let explicit = trackObj["isExplicit"] as? Bool ?? false
                let trackURL = "https://open.spotify.com/track/\(trackID)"
                
                let previewURLString = (trackObj["audioPreview"] as? [String: Any])?["url"] as? String
                let previewURL = previewURLString.flatMap(URL.init(string:))
                
                parsedTracks.append(
                    DownloadTrack(
                        id: trackID,
                        name: htmlDecoded(title),
                        artistLine: artists.isEmpty ? (subtitle.isEmpty ? "Unknown Artist" : subtitle) : htmlDecoded(artists),
                        albumName: sourceContext == .album ? entityName : "Unknown Album",
                        artworkURL: artworkURL,
                        isExplicit: explicit,
                        sourceURL: trackURL,
                        sourceContext: sourceContext,
                        provider: .metadata,
                        artistIdentifier: nil,
                        albumIdentifier: sourceContext == .album ? fallbackID : nil,
                        previewURL: previewURL
                    )
                )
            }
        }
        
        return (albumResult, parsedTracks)
    }
}
