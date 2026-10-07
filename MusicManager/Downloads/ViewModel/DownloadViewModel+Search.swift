import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func search(query: String, provider: DownloadView.SearchProvider) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            artistResults = []
            songResults = []
            albumResults = []
            playlistResults = []
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            return
        }
        lastSearchQuery = trimmed
        lastSearchProvider = provider
        metadataCachedSearchTracks = []
        metadataCachedSearchAlbums = []
        metadataCachedSearchPlaylists = []
        metadataAlbumTrackCache = [:]
        metadataDeezerOffset = 0
        metadataCanFetchMoreDeezer = false
        isSearching = true
        errorText = nil
        defer { isSearching = false }

        if let directLink = parseDirectLink(from: trimmed) {
            let handled = await handleDirectLinkSearch(directLink)
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            if handled {
                return
            }
        }

        if isUnsupportedPastedTidalLink(trimmed) {
            errorText = "Tidal pasted links are not supported. Paste an Apple Music link instead."
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false
            return
        }

        switch provider {
        case .appleMusic:
            artistResults = []
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: trimmed, limit: songPageSize, offset: 0)
            let albums = await searchAlbums(query: trimmed, limit: albumPageSize, offset: 0)
            let playlists = await searchPlaylists(query: trimmed, limit: playlistPageSize, offset: 0)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

            songResults = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            albumResults = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults = playlists.map { item in
                let playlistURL = "https://music.apple.com/\(region)/playlist/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: playlistURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            canLoadMoreSongs = songsHaveMore
            canLoadMoreAlbums = albums.count == albumPageSize
            canLoadMorePlaylists = playlists.count == playlistPageSize

        case .spotify:
            artistResults = []

            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: trimmed, limit: songPageSize, offset: 0)
            let albums = await searchAlbums(query: trimmed, limit: albumPageSize, offset: 0)
            let playlists = await searchPlaylists(query: trimmed, limit: playlistPageSize, offset: 0)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

            songResults = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .spotify,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            albumResults = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults = playlists.map { item in
                let playlistURL = "https://music.apple.com/\(region)/playlist/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: playlistURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            canLoadMoreSongs = songsHaveMore
            canLoadMoreAlbums = albums.count == albumPageSize
            canLoadMorePlaylists = playlists.count == playlistPageSize

        case .metadata:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: true
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false

        case .itunes:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: true,
                includeDeezer: false
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = 0
            metadataCanFetchMoreDeezer = false
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = false
            canLoadMoreAlbums = false
            canLoadMorePlaylists = false

        case .deezer:
            artistResults = []

            let batch = await fetchMetadataSearchTracks(
                query: trimmed,
                limit: songPageSize,
                deezerIndex: 0,
                includeITunes: false,
                includeDeezer: true
            )
            metadataCachedSearchTracks = uniqueTracks(batch.tracks)
            metadataDeezerOffset = batch.deezerCount
            metadataCanFetchMoreDeezer = batch.deezerCount == songPageSize
            metadataCachedSearchAlbums = buildMetadataAlbums(from: metadataCachedSearchTracks)
            metadataCachedSearchPlaylists = []

            songResults = Array(metadataCachedSearchTracks.prefix(songPageSize))
            albumResults = Array(metadataCachedSearchAlbums.prefix(albumPageSize))
            playlistResults = []
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMoreSongs() async {
        guard !isLoadingMoreSongs, canLoadMoreSongs, !lastSearchQuery.isEmpty else { return }
        isLoadingMoreSongs = true
        defer { isLoadingMoreSongs = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = songResults.count
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: lastSearchQuery, limit: songPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedSongs = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }
            songResults.append(contentsOf: mappedSongs.filter { incoming in
                !songResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreSongs = songsHaveMore
        case .spotify:
            let offset = songResults.count
            let (songs, songsHaveMore) = await AppleMusicAPI.shared.searchSongsWithAvailability(query: lastSearchQuery, limit: songPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedSongs = songs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .spotify,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }
            songResults.append(contentsOf: mappedSongs.filter { incoming in
                !songResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreSongs = songsHaveMore
        case .metadata:
            await expandMetadataSearchCacheIfNeeded(minimumTrackCount: songResults.count + songPageSize)
            let nextCount = min(songResults.count + songPageSize, metadataCachedSearchTracks.count)
            songResults = Array(metadataCachedSearchTracks.prefix(nextCount))
            albumResults = Array(metadataCachedSearchAlbums.prefix(max(albumResults.count, min(albumPageSize, metadataCachedSearchAlbums.count))))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        case .itunes:
            canLoadMoreSongs = false
        case .deezer:
            await expandMetadataSearchCacheIfNeeded(minimumTrackCount: songResults.count + songPageSize)
            let nextCount = min(songResults.count + songPageSize, metadataCachedSearchTracks.count)
            songResults = Array(metadataCachedSearchTracks.prefix(nextCount))
            albumResults = Array(metadataCachedSearchAlbums.prefix(max(albumResults.count, min(albumPageSize, metadataCachedSearchAlbums.count))))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMoreAlbums() async {
        guard !isLoadingMoreAlbums, canLoadMoreAlbums, !lastSearchQuery.isEmpty else { return }
        isLoadingMoreAlbums = true
        defer { isLoadingMoreAlbums = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = albumResults.count
            let albums = await searchAlbums(query: lastSearchQuery, limit: albumPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedAlbums = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            albumResults.append(contentsOf: mappedAlbums.filter { incoming in
                !albumResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreAlbums = albums.count == albumPageSize
        case .spotify:
            let offset = albumResults.count
            let albums = await searchAlbums(query: lastSearchQuery, limit: albumPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedAlbums = albums.map { item in
                let albumURL = "https://music.apple.com/\(region)/album/\(item.id)"
                return DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: albumURL,
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            albumResults.append(contentsOf: mappedAlbums.filter { incoming in
                !albumResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMoreAlbums = albums.count == albumPageSize
        case .metadata:
            let desiredAlbumCount = albumResults.count + albumPageSize
            await expandMetadataSearchCacheIfNeeded(minimumAlbumCount: desiredAlbumCount)
            albumResults = Array(metadataCachedSearchAlbums.prefix(min(desiredAlbumCount, metadataCachedSearchAlbums.count)))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        case .itunes:
            canLoadMoreAlbums = false
        case .deezer:
            let desiredAlbumCount = albumResults.count + albumPageSize
            await expandMetadataSearchCacheIfNeeded(minimumAlbumCount: desiredAlbumCount)
            albumResults = Array(metadataCachedSearchAlbums.prefix(min(desiredAlbumCount, metadataCachedSearchAlbums.count)))
            canLoadMoreSongs = songResults.count < metadataCachedSearchTracks.count || metadataCanFetchMoreDeezer
            canLoadMoreAlbums = albumResults.count < metadataCachedSearchAlbums.count || metadataCanFetchMoreDeezer
            canLoadMorePlaylists = false
        }
    }

    func loadMorePlaylists() async {
        guard !isLoadingMorePlaylists, canLoadMorePlaylists, !lastSearchQuery.isEmpty else { return }
        isLoadingMorePlaylists = true
        defer { isLoadingMorePlaylists = false }

        switch lastSearchProvider {
        case .appleMusic:
            let offset = playlistResults.count
            let playlists = await searchPlaylists(query: lastSearchQuery, limit: playlistPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedPlaylists = playlists.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/playlist/\(item.id)",
                    provider: .appleMusic,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults.append(contentsOf: mappedPlaylists.filter { incoming in
                !playlistResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMorePlaylists = playlists.count == playlistPageSize
        case .spotify:
            let offset = playlistResults.count
            let playlists = await searchPlaylists(query: lastSearchQuery, limit: playlistPageSize, offset: offset)
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let mappedPlaylists = playlists.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.curatorName ?? "Apple Music Playlist",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/playlist/\(item.id)",
                    provider: .spotify,
                    artistIdentifier: nil,
                    albumIdentifier: item.id
                )
            }
            playlistResults.append(contentsOf: mappedPlaylists.filter { incoming in
                !playlistResults.contains(where: { $0.id == incoming.id })
            })
            canLoadMorePlaylists = playlists.count == playlistPageSize
        case .metadata, .itunes, .deezer:
            canLoadMorePlaylists = false
        }
    }

    func loadArtistProfile(for artist: DownloadArtist) async -> DownloadArtistProfile {
        switch artist.provider {
        case .appleMusic:
            let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
            let filteredSongs = await fetchAppleMusicArtistSongs(artistName: artist.name)
            let tracks = filteredSongs.map { item in
                let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
                return DownloadTrack(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    albumName: item.attributes.albumName ?? "Unknown Album",
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    isExplicit: item.attributes.contentRating == "explicit",
                    sourceURL: songURL,
                    sourceContext: .song,
                    provider: .appleMusic,
                    artistIdentifier: item.relationships?.artists?.data.first?.id,
                    albumIdentifier: item.relationships?.albums?.data.first?.id,
                    previewURL: nil
                )
            }

            let filteredAlbums = await fetchAppleMusicArtistAlbums(artistName: artist.name)
            let mappedAlbums = filteredAlbums.map { item in
                DownloadAlbum(
                    id: item.id,
                    name: item.attributes.name,
                    artistLine: item.attributes.artistName,
                    artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                    sourceURL: "https://music.apple.com/\(region)/album/\(item.id)",
                    provider: .appleMusic,
                    artistIdentifier: artist.id,
                    albumIdentifier: item.id
                )
            }

            return DownloadArtistProfile(tracks: tracks, albums: uniqueAlbums(mappedAlbums))

        case .metadata, .spotify, .itunes, .deezer:
            if artist.id.hasPrefix("deezer-artist-"),
               let numericID = Int(artist.id.dropFirst("deezer-artist-".count)) {
                let profile = await buildDeezerArtistProfile(id: numericID, fallbackName: artist.name)
                if !profile.tracks.isEmpty || !profile.albums.isEmpty {
                    return profile
                }
            }
            return await buildMetadataArtistProfile(for: artist.name)
        }
    }

    func buildDeezerArtistProfile(id: Int, fallbackName: String) async -> DownloadArtistProfile {
        async let topTracksResult = SongMetadata.fetchDeezerArtistTopTracks(id: id, limit: 100)
        async let albumsResult = SongMetadata.fetchDeezerArtistAlbums(id: id, limit: 100)

        let tracks = await topTracksResult.map { metadataTrack(from: $0) }
        let albums = await albumsResult.map { summary in
            DownloadAlbum(
                id: "deezer-album-\(summary.id)",
                name: summary.title,
                artistLine: fallbackName,
                artworkURL: summary.cover_xl.flatMap { URL(string: $0) },
                sourceURL: "https://www.deezer.com/album/\(summary.id)",
                provider: .metadata,
                artistIdentifier: "deezer-artist-\(id)",
                albumIdentifier: "deezer-album-\(summary.id)"
            )
        }
        return DownloadArtistProfile(tracks: tracks, albums: albums)
    }

    func buildMetadataArtistProfile(for artistName: String) async -> DownloadArtistProfile {
        let batch = await fetchMetadataSearchTracks(
            query: artistName,
            limit: 100,
            deezerIndex: 0,
            includeITunes: true
        )
        let tracks = uniqueTracksForMetadataProfile(batch.tracks).filter {
            matchesArtistLine($0.artistLine, artistName: artistName)
        }
        let albums = uniqueAlbumsForMetadataProfile(buildMetadataAlbums(from: tracks))
        return DownloadArtistProfile(
            tracks: Array(tracks.prefix(100)),
            albums: Array(albums.prefix(100))
        )
    }
}
