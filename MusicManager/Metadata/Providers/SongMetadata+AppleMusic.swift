import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

extension SongMetadata {
    static func applyAppleMusicMatch(_ match: AppleMusicAPI.AppleMusicSong, to song: SongMetadata) async -> SongMetadata {
        var enrichedSong = song
        let amsMatch = match
        
        enrichedSong.title = amsMatch.attributes.name
        enrichedSong.artist = amsMatch.attributes.artistName
        if let alb = amsMatch.attributes.albumName { enrichedSong.album = alb }
        if let trackNumber = amsMatch.attributes.trackNumber {
            enrichedSong.trackNumber = trackNumber
        }
        if let discNumber = amsMatch.attributes.discNumber {
            enrichedSong.discNumber = discNumber
        }
        if let durationInMillis = amsMatch.attributes.durationInMillis, durationInMillis > 0 {
            enrichedSong.durationMs = durationInMillis
        }
        enrichedSong.appleMusicAudioTraits = amsMatch.attributes.audioTraits ?? []
        enrichedSong.isAppleDigitalMaster = amsMatch.attributes.isAppleDigitalMaster ?? false
        enrichedSong.isMasteredForItunes = amsMatch.attributes.isMasteredForItunes ?? false
        
        if let songIdInt = Int64(amsMatch.id) {
            enrichedSong.storeId = songIdInt
        }
        
        if let dateStr = amsMatch.attributes.releaseDate {
            if let yearInt = Int(dateStr.prefix(4)) {
                enrichedSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(dateStr) {
                enrichedSong.releaseDate = epoch
            }
        } else if let firstAlbum = amsMatch.relationships?.albums?.data.first,
                  let albDateStr = firstAlbum.attributes.releaseDate {
            if let yearInt = Int(albDateStr.prefix(4)) {
                enrichedSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(albDateStr) {
                enrichedSong.releaseDate = epoch
            }
        }
        
        if let isrc = amsMatch.attributes.isrc, !isrc.isEmpty {
            enrichedSong.xid = isrc
        }
        
        if let rating = amsMatch.attributes.contentRating {
            enrichedSong.explicitRating = (rating == "explicit") ? 1 : (rating == "clean" ? 2 : 0)
        }
        
        if let firstAlbum = amsMatch.relationships?.albums?.data.first,
           let cprt = firstAlbum.attributes.copyright {
            enrichedSong.copyright = cprt
        }
        
        if let firstArtist = amsMatch.relationships?.artists?.data.first,
           let artistIdInt = Int64(firstArtist.id) {
            enrichedSong.artistId = artistIdInt
        }
        
        if let firstComposer = amsMatch.relationships?.composers?.data.first,
           let composerIdInt = Int64(firstComposer.id) {
            enrichedSong.composerId = composerIdInt
        }
        
        if let firstGenre = amsMatch.relationships?.genres?.data.first,
           let genreIdInt = Int64(firstGenre.id) {
            enrichedSong.genreStoreId = genreIdInt
        }
        
        if let firstGenreName = amsMatch.attributes.genreNames?.first {
            enrichedSong.genre = canonicalGenre(firstGenreName)
        }
        
        if let firstAlbum = amsMatch.relationships?.albums?.data.first,
           let albumIdInt = Int64(firstAlbum.id) {
            enrichedSong.playlistId = albumIdInt
        }
        
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        enrichedSong.storefrontId = SongMetadata.storefrontMap[region] ?? 143441
        
        if let artworkUrl = amsMatch.attributes.artwork?.artworkURL() {
            if let (data, _) = try? await SongMetadataNetworking.data(from: artworkUrl) {
                enrichedSong.artworkData = data
            }
        }
        enrichedSong.appleMusicArtworkColors = amsMatch.attributes.artwork?.colors

        enrichedSong.genre = canonicalGenre(enrichedSong.genre)
        enrichedSong.richAppleMetadataFetched = true
        return enrichedSong
    }

    static func enrichWithAppleMusicMetadata(_ song: SongMetadata, requireAlbumMatch: Bool = false) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Performing full Apple Music fetch for: \(song.artist) - \(song.title)")
        let query = "\(song.artist) \(song.title)"

        if let amsMatch = await AppleMusicAPI.shared.searchSong(query: query, albumHint: song.album, titleHint: song.title, requireAlbumMatch: requireAlbumMatch) {
            let enriched = await applyAppleMusicMatch(amsMatch, to: song)
            Logger.shared.log("[SongMetadata] ✓ Apple Music match (\(enriched.appleMetadataMatchTier)): \(enriched.title) (\(enriched.storeId))")
            return enriched
        }

        Logger.shared.log("[SongMetadata] Apple Music fetch returned no match for: \(song.artist) - \(song.title)")
        return song
    }

    static func enrichWithExactAppleMusicTrack(_ song: SongMetadata, trackID: String, urlHint: String? = nil) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Performing exact Apple Music fetch for track ID: \(trackID)")

        guard let amsMatch = await AppleMusicAPI.shared.fetchSong(id: trackID, urlHint: urlHint) else {
            Logger.shared.log("[SongMetadata] Exact Apple Music fetch failed for track ID: \(trackID)")
            return song
        }

        let enriched = await applyAppleMusicMatch(amsMatch, to: song)
        Logger.shared.log("[SongMetadata] ✓ Exact Apple Music match (\(enriched.appleMetadataMatchTier)): \(enriched.title) (\(enriched.storeId))")
        return enriched
    }
    
    static func matchAppleMusicMetadata(_ song: SongMetadata) async -> SongMetadata {
        let query = "\(song.artist) \(song.title)"
        Logger.shared.log("[SongMetadata] 🔍 Shadow-searching Apple Music for rich metadata: '\(query)'")

        if let amsMatch = await AppleMusicAPI.shared.searchSong(query: query, albumHint: song.album, titleHint: song.title) {
            Logger.shared.log("[SongMetadata] ✨ Found Apple Music Server Match: \(amsMatch.attributes.name) by \(amsMatch.attributes.artistName) (ID: \(amsMatch.id))")
            let enriched = await applyAppleMusicMatch(amsMatch, to: song)
            Logger.shared.log("[SongMetadata] ✨ Rich Apple metadata tier: \(enriched.appleMetadataMatchTier) for \(enriched.title)")
            return enriched
        } else {
            Logger.shared.log("[SongMetadata] ⚠️ No rich metadata match found on Apple Music for: '\(query)'")
        }
        
        return song
    }
}
