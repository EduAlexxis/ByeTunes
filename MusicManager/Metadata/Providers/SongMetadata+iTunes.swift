import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

struct iTunesSearchResult: Codable {
    let results: [iTunesSong]
}

struct iTunesSong: Codable, Identifiable {
    var id: Int { trackId ?? Int.random(in: 0...Int.max) }
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackViewUrl: String?
    let previewUrl: String?
    let primaryGenreName: String?
    let artistId: Int?
    let collectionId: Int?
    let releaseDate: String?
    let artworkUrl100: String?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
}

extension SongMetadata {
    static func searchiTunes(query: String, limit: Int = 10) async -> [iTunesSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion") ?? "US"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let boundedLimit = min(max(limit, 1), 200)
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=\(boundedLimit)&country=\(region)") else {
            return []
        }
        
        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
            return result.results
        } catch {
            Logger.shared.log("[SongMetadata] iTunes search failed: \(error)")
            return []
        }
    }
    
    
    static func applyiTunesMatch(_ match: iTunesSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        if let t = match.trackName { newSong.title = t }
        if let a = match.artistName { newSong.artist = a }
        if let al = match.collectionName { newSong.album = al }
        if let g = match.primaryGenreName { newSong.genre = canonicalGenre(g) }
        if let aId = match.artistId { newSong.artistId = Int64(aId) }
        if let cId = match.collectionId { newSong.playlistId = Int64(cId) }
        if let tId = match.trackId { newSong.storeId = Int64(tId) }
        newSong.storefrontId = 143441
        
        newSong.trackNumber = match.trackNumber
        newSong.trackCount = match.trackCount
        newSong.discNumber = match.discNumber
        newSong.discCount = match.discCount
        
        if let dateStr = match.releaseDate {
            if let yearInt = Int(dateStr.prefix(4)) {
                newSong.year = yearInt
            }
            if let epoch = parseDateToEpoch(dateStr) {
                newSong.releaseDate = epoch
            }
        }
        
        
        if let artUrl = match.artworkUrl100 {
            
            let highResUrlString = artUrl.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
            if let highResUrl = URL(string: highResUrlString),
               let (artData, _) = try? await SongMetadataNetworking.data(from: highResUrl) {
                newSong.artworkData = artData
                Logger.shared.log("[SongMetadata] Updated artwork with iTunes High-Res version: \(artData.count) bytes")
            }
        }
        
        newSong.genre = canonicalGenre(newSong.genre)
        return newSong
    }

    
    static func enrichWithiTunesMetadata(_ song: SongMetadata) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Searching iTunes for: \(song.artist) - \(song.title)")
        
        let query = "\(song.artist) \(song.title)"
        let results = await searchiTunes(query: query)
        
        
        var bestMatch: iTunesSong?
        
        for match in results {
            guard let remoteArtist = match.artistName,
                  let remoteTitle = match.trackName else { continue }
            
            
            if song.artist != "Unknown Artist" {
                let localNorm = song.artist.lowercased().filter { !$0.isPunctuation }
                let remoteNorm = remoteArtist.lowercased().filter { !$0.isPunctuation }
                
                
                if localNorm.contains(remoteNorm) || remoteNorm.contains(localNorm) {
                    bestMatch = match
                    Logger.shared.log("[SongMetadata] ✓ Validated match: \(remoteTitle) by \(remoteArtist)")
                    break 
                } else {
                    Logger.shared.log("[SongMetadata] x Rejected match: \(remoteTitle) by \(remoteArtist) (Artist mismatch)")
                }
            } else {
                
                bestMatch = match
                break
            }
        }
        
        guard let match = bestMatch else {
            Logger.shared.log("[SongMetadata] No valid iTunes match found after filtering.")
            return song
        }
        
        var enrichedSong = await applyiTunesMatch(match, to: song)
        
        if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
            enrichedSong = await matchAppleMusicMetadata(enrichedSong)
        }
        
        return enrichedSong
    }
}
