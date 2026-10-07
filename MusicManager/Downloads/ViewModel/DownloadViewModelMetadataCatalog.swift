import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

// MARK: - Metadata Catalog
extension DownloadViewModel {
    func searchAlbums(query: String, limit: Int, offset: Int = 0) async -> [AppleMusicAlbumResult] {
        let fallback = await AppleMusicAPI.shared.searchAlbumsPublic(query: query, limit: limit, offset: offset)
        if !fallback.isEmpty {
            log("Album search is using Apple Music public search page.")
        }
        return fallback.map {
            AppleMusicAlbumResult(
                id: $0.id,
                attributes: AppleMusicAlbumResultAttributes(
                    name: $0.name,
                    artistName: $0.artistName,
                    artwork: $0.artwork
                )
            )
        }
    }

    func searchPlaylists(query: String, limit: Int, offset: Int = 0) async -> [AppleMusicPlaylistResult] {
        let fallback = await AppleMusicAPI.shared.searchPlaylistsPublic(query: query, limit: limit, offset: offset)
        if !fallback.isEmpty {
            log("Playlist search is using Apple Music public search page.")
        }
        return fallback.map {
            AppleMusicPlaylistResult(
                id: $0.id,
                attributes: AppleMusicPlaylistAttributes(
                    name: $0.name,
                    curatorName: $0.curatorName,
                    artwork: $0.artwork
                ),
                relationships: nil
            )
        }
    }


    func metadataTrack(from song: iTunesSong) -> DownloadTrack? {
        guard
            let trackID = song.trackId,
            let title = song.trackName,
            let artist = song.artistName
        else { return nil }

        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let albumID = song.collectionId.map { "itunes-album-\($0)" } ?? "itunes-album-\(DownloadSupport.normalizedSearchValue(artist))-\(DownloadSupport.normalizedSearchValue(song.collectionName ?? "Unknown Album"))"
        let artworkURL = song.artworkUrl100?
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")

        return DownloadTrack(
            id: "itunes-\(trackID)",
            name: title,
            artistLine: artist,
            albumName: song.collectionName ?? "Unknown Album",
            artworkURL: artworkURL.flatMap(URL.init(string:)),
            isExplicit: false,
            sourceURL: song.trackViewUrl ?? "https://music.apple.com/\(region)/song/\(trackID)",
            sourceContext: .song,
            provider: .metadata,
            artistIdentifier: song.artistId.map { "itunes-artist-\($0)" },
            albumIdentifier: albumID,
            previewURL: song.previewUrl.flatMap(URL.init(string:))
        )
    }

    func metadataTrack(from song: DeezerSong, sourceURLOverride: String? = nil) -> DownloadTrack {
        return DownloadTrack(
            id: "deezer-\(song.id)",
            name: song.title,
            artistLine: song.artist.name,
            albumName: song.album.title,
            artworkURL: song.album.cover_xl.flatMap { URL(string: $0) },
            isExplicit: song.explicit_lyrics ?? false,
            sourceURL: sourceURLOverride ?? song.link ?? "https://www.deezer.com/track/\(song.id)",
            sourceContext: .song,
            provider: .metadata,
            artistIdentifier: "deezer-artist-\(song.artist.id)",
            albumIdentifier: "deezer-album-\(song.album.id)",
            previewURL: song.preview.flatMap(URL.init(string:))
        )
    }

    func buildMetadataAlbums(from tracks: [DownloadTrack]) -> [DownloadAlbum] {
        var grouped: [String: [DownloadTrack]] = [:]
        var orderedKeys: [String] = []

        for track in tracks {
            let key = track.albumIdentifier ?? "metadata-album-\(DownloadSupport.normalizedSearchValue(track.artistLine))-\(DownloadSupport.normalizedSearchValue(track.albumName))"
            if grouped[key] == nil {
                grouped[key] = []
                orderedKeys.append(key)
            }
            grouped[key]?.append(track)
        }

        metadataAlbumTrackCache = grouped

        return orderedKeys.compactMap { key in
            guard let groupTracks = grouped[key], let firstTrack = groupTracks.first else { return nil }
            return DownloadAlbum(
                id: key,
                name: firstTrack.albumName,
                artistLine: mostCommonArtistLine(in: groupTracks),
                artworkURL: firstTrack.artworkURL,
                sourceURL: firstTrack.sourceURL,
                provider: .metadata,
                artistIdentifier: firstTrack.artistIdentifier,
                albumIdentifier: key
            )
        }
    }

    func mostCommonArtistLine(in tracks: [DownloadTrack]) -> String {
        var counts: [String: Int] = [:]
        for track in tracks {
            counts[track.artistLine, default: 0] += 1
        }
        let mostCommon = counts.max { lhs, rhs in lhs.value < rhs.value }?.key
        return (mostCommon?.isEmpty == false) ? mostCommon! : (tracks.first?.artistLine ?? "")
    }

    func fetchAlbumTracks(albumID: String, fallbackAlbumName: String, sourceURL: String? = nil) async -> [DownloadTrack] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"

        let publicTracks = await AppleMusicAPI.shared.fetchAlbumTracksPublic(id: albumID, urlHint: sourceURL)
        return publicTracks.map { item in
            let songURL = item.attributes.url ?? "https://music.apple.com/\(region)/song/\(item.id)"
            return DownloadTrack(
                id: item.id,
                name: item.attributes.name,
                artistLine: item.attributes.artistName,
                albumName: item.attributes.albumName ?? fallbackAlbumName,
                artworkURL: item.attributes.artwork?.artworkURL(width: 400, height: 400),
                isExplicit: item.attributes.contentRating == "explicit",
                sourceURL: songURL,
                sourceContext: .album,
                provider: .appleMusic,
                artistIdentifier: item.relationships?.artists?.data.first?.id,
                albumIdentifier: item.relationships?.albums?.data.first?.id ?? albumID,
                previewURL: nil
            )
        }
    }
}
