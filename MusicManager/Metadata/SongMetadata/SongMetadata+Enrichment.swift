import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

// MARK: - Enrichment
extension SongMetadata {
    private static func deezerTrackID(from trackID: String) -> Int? {
        guard trackID.hasPrefix("deezer-") else { return nil }
        return Int(trackID.dropFirst("deezer-".count))
    }

    static func enrichDownloadedSong(_ initialSong: SongMetadata, sourceTrack: DownloadTrack? = nil) async -> SongMetadata {
        var song = initialSong

        if let sourceTrack {
            if let deezerID = deezerTrackID(from: sourceTrack.id) {
                if let exact = await fetchDeezerTrack(id: deezerID) {
                    Logger.shared.log("[SongMetadata] Using exact Deezer track \(deezerID) from album \(exact.album.title)")
                    song = await applyDeezerMatch(exact, to: song)
                }
                song = await enrichWithAppleMusicMetadata(song, requireAlbumMatch: true)
            } else if sourceTrack.id.hasPrefix("itunes-") {
                song.album = sourceTrack.albumName == "Unknown Album" ? song.album : sourceTrack.albumName
                song = await enrichWithAppleMusicMetadata(song, requireAlbumMatch: true)
            } else {
                song = await enrichWithExactAppleMusicTrack(song, trackID: sourceTrack.id, urlHint: sourceTrack.sourceURL)
                if song.storeId == 0 {
                    song = await enrichWithAppleMusicMetadata(song)
                }
            }
        } else {
            let metadataSource = UserDefaults.standard.string(forKey: "metadataSource") ?? "apple"
            let autofetch = UserDefaults.standard.bool(forKey: "autofetchMetadata")

            if metadataSource == "apple" && autofetch {
                song = await enrichWithAppleMusicMetadata(song)
            } else if metadataSource == "itunes" && autofetch {
                song = await enrichWithiTunesMetadata(song)
            } else if metadataSource == "deezer" && autofetch {
                song = await enrichWithDeezerMetadata(song)
            } else if metadataSource == "local" && autofetch {
                if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
                    song = await matchAppleMusicMetadata(song)
                }
            }
        }

        let fetchLyricsEnabled = UserDefaults.standard.bool(forKey: "fetchLyrics")
        let appleSubscriptionLyrics = UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")
        if fetchLyricsEnabled && !appleSubscriptionLyrics && (song.lyrics == nil || song.lyrics?.isEmpty == true) {
            if let fetchedLyrics = await SongMetadata.fetchLyrics(
                title: song.title,
                artist: song.artist,
                album: song.album,
                durationMs: song.durationMs
            ) {
                song.lyrics = fetchedLyrics
            }
        }

        return song
    }
}
