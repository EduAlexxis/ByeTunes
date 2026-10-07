import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func handleDirectLinkSearch(_ link: DirectLinkKind) async -> Bool {
        artistResults = []
        songResults = []
        albumResults = []
        playlistResults = []
        pendingDirectLinkAction = nil

        switch link {
        case .appleSong(let id, let sourceURL):
            guard let song = await AppleMusicAPI.shared.fetchSong(id: id, urlHint: sourceURL) else {
                errorText = "Could not load that Apple Music song link."
                return true
            }
            let track = makeAppleMusicTrack(from: song, sourceURLOverride: sourceURL)
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .appleAlbum(let id, let sourceURL):
            guard let album = await fetchAppleMusicAlbum(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music album link."
                return true
            }
            let albumResult = makeAppleMusicAlbum(from: album, sourceURLOverride: sourceURL)
            let tracks = await fetchAlbumTracks(albumID: id, fallbackAlbumName: album.attributes?.name ?? "Unknown Album", sourceURL: sourceURL)
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .appleArtist(let id, let sourceURL):
            guard let artistData = await fetchAppleMusicArtist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music artist link."
                return true
            }
            let artist = DownloadArtist(
                id: artistData.id,
                name: artistData.attributes.name,
                provider: .appleMusic,
                artworkURL: artistData.attributes.artwork?.artworkURL(width: 400, height: 400)
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .applePlaylist(let id, let sourceURL):
            guard let playlist = await fetchAppleMusicPlaylist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Apple Music playlist link."
                return true
            }
            let tracks = playlist.relationships?.tracks?.data.map {
                makeAppleMusicTrack(from: $0)
            } ?? []
            let playlistContainer = DownloadAlbum(
                id: playlist.id,
                name: playlist.attributes.name,
                artistLine: playlist.attributes.curatorName ?? "Apple Music Playlist",
                artworkURL: playlist.attributes.artwork?.artworkURL(width: 400, height: 400) ?? tracks.first?.artworkURL,
                sourceURL: sourceURL,
                provider: .appleMusic,
                artistIdentifier: nil,
                albumIdentifier: playlist.id
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .spotifyTrack(let id, let sourceURL):
            guard let track = await fetchSpotifyTrack(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify track link."
                return true
            }
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .spotifyAlbum(let id, let sourceURL):
            guard let (albumResult, tracks) = await fetchSpotifyAlbum(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify album link."
                return true
            }
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .spotifyArtist(let id, let sourceURL):
            guard let artist = await fetchSpotifyArtist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify artist link."
                return true
            }
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .spotifyPlaylist(let id, let sourceURL):
            guard let (playlistContainer, tracks) = await fetchSpotifyPlaylist(id: id, sourceURL: sourceURL) else {
                errorText = "Could not load that Spotify playlist link."
                return true
            }
            albumTrackIDs[playlistContainer.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .deezerTrack(let id, let sourceURL):
            guard let numericID = Int(id), let song = await SongMetadata.fetchDeezerTrack(id: numericID) else {
                errorText = "Could not load that Deezer track link."
                return true
            }
            let track = metadataTrack(from: song, sourceURLOverride: sourceURL)
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .track(track))
            return true

        case .deezerAlbum(let id, let sourceURL):
            guard let numericID = Int(id), let albumDetail = await SongMetadata.fetchDeezerAlbum(id: numericID) else {
                errorText = "Could not load that Deezer album link."
                return true
            }
            let tracks = albumDetail.tracks.data.map { metadataTrack(from: $0) }
            guard let firstTrack = tracks.first else {
                errorText = "Could not load that Deezer album link."
                return true
            }
            let albumResult = DownloadAlbum(
                id: firstTrack.albumIdentifier ?? "deezer-album-\(albumDetail.id)",
                name: albumDetail.title,
                artistLine: albumDetail.artist.name,
                artworkURL: albumDetail.cover_xl.flatMap { URL(string: $0) },
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: firstTrack.artistIdentifier,
                albumIdentifier: firstTrack.albumIdentifier
            )
            albumTrackIDs[albumResult.id] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: albumResult,
                    tracks: tracks,
                    title: "Album Download",
                    helperText: "Choose the tracks you want to download, or grab the full album in one tap."
                )
            )
            return true

        case .deezerArtist(let id, _):
            guard let numericID = Int(id), let artistDetail = await SongMetadata.fetchDeezerArtist(id: numericID) else {
                errorText = "Could not load that Deezer artist link."
                return true
            }
            let artist = DownloadArtist(
                id: "deezer-artist-\(artistDetail.id)",
                name: artistDetail.name,
                provider: .metadata,
                artworkURL: artistDetail.picture_xl.flatMap { URL(string: $0) }
            )
            pendingDirectLinkAction = DownloadDirectLinkAction(payload: .artist(artist))
            return true

        case .deezerPlaylist(let id, let sourceURL):
            guard let numericID = Int(id), let playlistDetail = await SongMetadata.fetchDeezerPlaylist(id: numericID) else {
                errorText = "Could not load that Deezer playlist link."
                return true
            }
            let tracks = playlistDetail.tracks.data.map { metadataTrack(from: $0) }
            guard !tracks.isEmpty else {
                errorText = "Could not load that Deezer playlist link."
                return true
            }
            let playlistContainerID = "deezer-playlist-\(playlistDetail.id)"
            let playlistContainer = DownloadAlbum(
                id: playlistContainerID,
                name: playlistDetail.title,
                artistLine: playlistDetail.creator.name,
                artworkURL: playlistDetail.picture_xl.flatMap { URL(string: $0) },
                sourceURL: sourceURL,
                provider: .metadata,
                artistIdentifier: nil,
                albumIdentifier: playlistContainerID
            )
            albumTrackIDs[playlistContainerID] = tracks.map(\.id)
            pendingDirectLinkAction = DownloadDirectLinkAction(
                payload: .collection(
                    album: playlistContainer,
                    tracks: tracks,
                    title: "Playlist Download",
                    helperText: "Choose the songs you want to download, or grab the full playlist in one tap."
                )
            )
            return true

        case .deezerShortLink(let sourceURL):
            if let resolvedURL = await resolveDeezerShortLink(sourceURL),
               let mappedDeezerLink = parseDirectLink(from: resolvedURL) {
                return await handleDirectLinkSearch(mappedDeezerLink)
            }
            errorText = "Could not resolve that Deezer link."
            return true
        }
    }

    func parseDirectLink(from value: String) -> DirectLinkKind? {
        guard let components = URLComponents(string: value),
              let host = components.host?.lowercased() else {
            return nil
        }

        let sourceURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        if host.contains("music.apple.com") {
            if let songID = components.queryItems?.first(where: { $0.name == "i" })?.value, !songID.isEmpty {
                return .appleSong(id: songID, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "song"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleSong(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .appleArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).last,
               !id.isEmpty {
                return .applePlaylist(id: id, sourceURL: sourceURL)
            }
        } else if host.contains("spotify.com") {
            if let index = pathParts.firstIndex(of: "track"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyTrack(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .spotifyPlaylist(id: id, sourceURL: sourceURL)
            }
        } else if host.contains("deezer.page.link") || host == "link.deezer.com" {
            return .deezerShortLink(sourceURL: sourceURL)
        } else if host.contains("deezer.com") {
            if let index = pathParts.firstIndex(of: "track"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerTrack(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "album"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerAlbum(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "artist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerArtist(id: id, sourceURL: sourceURL)
            }

            if let index = pathParts.firstIndex(of: "playlist"),
               let id = pathParts.dropFirst(index + 1).first,
               !id.isEmpty {
                return .deezerPlaylist(id: id, sourceURL: sourceURL)
            }
        }

        return nil
    }

    func isUnsupportedPastedTidalLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let host = components.host?.lowercased() else {
            return false
        }
        return host.contains("tidal.com")
    }

    func resolveDeezerShortLink(_ sourceURL: String) async -> String? {
        guard let url = URL(string: sourceURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let finalURL = response.url, finalURL.host?.lowercased().contains("deezer.com") == true else {
                return nil
            }
            return finalURL.absoluteString
        } catch {
            log("Deezer short link resolution failed: \(error.localizedDescription)")
            return nil
        }
    }

    func makeAppleMusicTrack(
        from item: AppleMusicAPI.AppleMusicSong,
        sourceURLOverride: String? = nil,
        provider: DownloadView.SearchProvider = .appleMusic,
        trackIDOverride: String? = nil
    ) -> DownloadTrack {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let songURL = sourceURLOverride ?? item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
        return DownloadTrack(
            id: trackIDOverride ?? item.id,
            name: item.attributes.name,
            artistLine: item.attributes.artistName,
            albumName: item.attributes.albumName ?? "Unknown Album",
            artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
            isExplicit: item.attributes.contentRating == "explicit",
            sourceURL: songURL,
            sourceContext: .song,
            provider: provider,
            artistIdentifier: item.relationships?.artists?.data.first?.id,
            albumIdentifier: item.relationships?.albums?.data.first?.id,
            previewURL: nil
        )
    }

    func makeAppleMusicAlbum(
        from item: AppleMusicAPI.AppleMusicSong,
        provider: DownloadView.SearchProvider = .appleMusic,
        sourceURLOverride: String? = nil
    ) -> DownloadAlbum? {
        guard let albumID = item.relationships?.albums?.data.first?.id else {
            return nil
        }
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        return DownloadAlbum(
            id: albumID,
            name: item.attributes.albumName ?? "Unknown Album",
            artistLine: item.attributes.artistName,
            artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
            sourceURL: sourceURLOverride ?? "https://music.apple.com/\(region)/album/\(albumID)",
            provider: provider,
            artistIdentifier: item.relationships?.artists?.data.first?.id,
            albumIdentifier: albumID
        )
    }

    func makeAppleMusicAlbum(
        from item: AppleMusicAlbumDetailsData,
        sourceURLOverride: String? = nil
    ) -> DownloadAlbum {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let albumID = item.id ?? item.attributes?.playParams?.id ?? "unknown-album"
        return DownloadAlbum(
            id: albumID,
            name: item.attributes?.name ?? "Unknown Album",
            artistLine: item.attributes?.artistName ?? "Unknown Artist",
            artworkURL: item.attributes?.artwork?.artworkURL(width: 400, height: 400),
            sourceURL: sourceURLOverride ?? "https://music.apple.com/\(region)/album/\(albumID)",
            provider: .appleMusic,
            artistIdentifier: nil,
            albumIdentifier: albumID
        )
    }

    func fetchAppleMusicArtistSongs(artistName: String) async -> [AppleMusicAPI.AppleMusicSong] {
        let pageSize = 50
        let maxPages = 5
        var offset = 0
        var collected: [AppleMusicAPI.AppleMusicSong] = []
        var seenIDs = Set<String>()

        for _ in 0..<maxPages {
            let page = await AppleMusicAPI.shared.searchSongs(query: artistName, limit: pageSize, offset: offset)
            if page.isEmpty { break }

            let filteredPage = page.filter {
                matchesArtistLine($0.attributes.artistName, artistName: artistName)
            }

            for song in filteredPage where !seenIDs.contains(song.id) {
                seenIDs.insert(song.id)
                collected.append(song)
            }

            if page.count < pageSize { break }
            offset += pageSize
        }

        return collected
    }

    func fetchAppleMusicArtistAlbums(artistName: String) async -> [AppleMusicAlbumResult] {
        let pageSize = 50
        let maxPages = 5
        var offset = 0
        var collected: [AppleMusicAlbumResult] = []
        var seenIDs = Set<String>()

        for _ in 0..<maxPages {
            let page = await searchAlbums(query: artistName, limit: pageSize, offset: offset)
            if page.isEmpty { break }

            let filteredPage = page.filter {
                matchesArtistLine($0.attributes.artistName, artistName: artistName)
            }

            for album in filteredPage where !seenIDs.contains(album.id) {
                seenIDs.insert(album.id)
                collected.append(album)
            }

            if page.count < pageSize { break }
            offset += pageSize
        }

        return collected
    }

    func fetchAppleMusicAlbum(id: String, sourceURL: String? = nil) async -> AppleMusicAlbumDetailsData? {
        guard let fallbackAlbum = await AppleMusicAPI.shared.fetchAlbumPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        let fallbackTracks = await AppleMusicAPI.shared.fetchAlbumTracksPublic(id: id, urlHint: sourceURL)
        return AppleMusicAlbumDetailsData(
            id: fallbackAlbum.id,
            attributes: AppleMusicDirectAlbumAttributes(
                name: fallbackAlbum.name,
                artistName: fallbackAlbum.artistName,
                artwork: fallbackAlbum.artwork,
                playParams: AppleMusicPlayParams(id: fallbackAlbum.id)
            ),
            relationships: AppleMusicAlbumRelationships(
                tracks: AppleMusicAlbumTracksPage(data: fallbackTracks.map {
                    AppleMusicAlbumTrack(
                        id: $0.id,
                        attributes: AppleMusicAlbumTrackAttributes(
                            name: $0.attributes.name,
                            artistName: $0.attributes.artistName,
                            albumName: $0.attributes.albumName,
                            url: $0.attributes.url,
                            contentRating: $0.attributes.contentRating,
                            artwork: $0.attributes.artwork
                        )
                    )
                })
            )
        )
    }

    func fetchAppleMusicArtist(id: String, sourceURL: String? = nil) async -> AppleMusicArtistResult? {
        guard let fallbackArtist = await AppleMusicAPI.shared.fetchArtistPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        return AppleMusicArtistResult(
            id: fallbackArtist.id,
            attributes: AppleMusicArtistAttributes(
                name: fallbackArtist.name,
                artwork: fallbackArtist.artwork
            )
        )
    }

    func fetchAppleMusicPlaylist(id: String, sourceURL: String? = nil) async -> AppleMusicPlaylistResult? {
        guard let fallbackPlaylist = await AppleMusicAPI.shared.fetchPlaylistPublic(id: id, urlHint: sourceURL) else {
            return nil
        }

        let fallbackTracks = await AppleMusicAPI.shared.fetchPlaylistTracksPublic(id: id, urlHint: sourceURL)
        return AppleMusicPlaylistResult(
            id: fallbackPlaylist.id,
            attributes: AppleMusicPlaylistAttributes(
                name: fallbackPlaylist.name,
                curatorName: fallbackPlaylist.curatorName,
                artwork: fallbackPlaylist.artwork
            ),
            relationships: AppleMusicPlaylistRelationships(
                tracks: AppleMusicPlaylistTracksPage(data: fallbackTracks)
            )
        )
    }

    func fetchMetadataSearchTracks(
        query: String,
        limit: Int,
        deezerIndex: Int,
        includeITunes: Bool,
        includeDeezer: Bool = true
    ) async -> MetadataSearchBatch {
        async let deezerResults = includeDeezer ? SongMetadata.searchDeezer(query: query, limit: limit, index: deezerIndex) : []
        async let iTunesResults = includeITunes ? SongMetadata.searchiTunes(query: query, limit: min(limit, 50)) : []

        let deezerSongs = await deezerResults
        let iTunesSongs = await iTunesResults
        let tracks = iTunesSongs.compactMap(metadataTrack(from:)) + deezerSongs.map { self.metadataTrack(from: $0) }
        return MetadataSearchBatch(tracks: tracks, deezerCount: deezerSongs.count)
    }

    func expandMetadataSearchCacheIfNeeded(minimumTrackCount: Int? = nil, minimumAlbumCount: Int? = nil) async {
        while metadataCanFetchMoreDeezer {
            let hasEnoughTracks = minimumTrackCount.map { metadataCachedSearchTracks.count >= $0 } ?? false
            let hasEnoughAlbums = minimumAlbumCount.map { metadataCachedSearchAlbums.count >= $0 } ?? false

            if minimumTrackCount != nil, hasEnoughTracks {
                break
            }
            if minimumAlbumCount != nil, hasEnoughAlbums {
                break
            }

            let batch = await fetchMetadataSearchTracks(
                query: lastSearchQuery,
                limit: songPageSize,
                deezerIndex: metadataDeezerOffset,
                includeITunes: false
            )
            metadataDeezerOffset += batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize

            let existingIDs = Set(metadataCachedSearchTracks.map(\.id))
            let freshTracks = batch.tracks.filter { !existingIDs.contains($0.id) }
            if freshTracks.isEmpty {
                break
            }

            metadataCachedSearchTracks = uniqueTracks(metadataCachedSearchTracks + freshTracks)
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
        }
    }
}
