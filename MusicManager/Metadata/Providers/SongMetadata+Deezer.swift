import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

struct LossyDecodableList<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            do {
                result.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(Skip.self)
            }
        }
        elements = result
    }
}

struct DeezerSearchResult: Codable {
    let data: [DeezerSong]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(LossyDecodableList<DeezerSong>.self, forKey: .data).elements
    }
}

struct DeezerSong: Codable, Identifiable {
    let id: Int
    let title: String
    let link: String?
    let preview: String?
    let artist: DeezerReference
    let album: DeezerAlbumReference
    let duration: Int
    let explicit_lyrics: Bool?
    let isrc: String?
    let rank: Int?
    
    
    var trackName: String { title }
    var artistName: String { artist.name }
    var albumName: String { album.title }
    var artworkUrl: String { album.cover_xl ?? "" }
}

struct DeezerReference: Codable {
    let id: Int
    let name: String
}

struct DeezerAlbumReference: Codable {
    let id: Int
    let title: String
    let cover_xl: String?
}

struct DeezerTrackDetails: Codable {
    let track_position: Int?
    let disk_number: Int?
    let release_date: String?
}

struct DeezerTracksWrapper: Codable {
    let data: [DeezerSong]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(LossyDecodableList<DeezerSong>.self, forKey: .data).elements
    }
}

struct DeezerAlbumDetail: Codable {
    let id: Int
    let title: String
    let cover_xl: String?
    let artist: DeezerReference
    let tracks: DeezerTracksWrapper
}

struct DeezerPlaylistDetail: Codable {
    let id: Int
    let title: String
    let picture_xl: String?
    let creator: DeezerReference
    let tracks: DeezerTracksWrapper
}

struct DeezerArtistDetail: Codable {
    let id: Int
    let name: String
    let picture_xl: String?
}

struct DeezerArtistTopTracksResult: Codable {
    let data: [DeezerSong]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(LossyDecodableList<DeezerSong>.self, forKey: .data).elements
    }
}

struct DeezerArtistAlbumSummary: Codable {
    let id: Int
    let title: String
    let cover_xl: String?
}

struct DeezerArtistAlbumsResult: Codable {
    let data: [DeezerArtistAlbumSummary]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(LossyDecodableList<DeezerArtistAlbumSummary>.self, forKey: .data).elements
    }
}



// MARK: - Deezer
extension SongMetadata {
    
    
    static func searchDeezer(query: String, limit: Int = 10, index: Int = 0) async -> [DeezerSong] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let boundedLimit = min(max(limit, 1), 100)
        let boundedIndex = max(index, 0)
        guard let url = URL(string: "https://api.deezer.com/search?q=\(encodedQuery)&limit=\(boundedLimit)&index=\(boundedIndex)") else {
            return []
        }
        
        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            let result = try JSONDecoder().decode(DeezerSearchResult.self, from: data)
            return result.data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer search failed: \(error)")
            return []
        }
    }
    
    static func fetchDeezerTrackDetails(id: Int) async -> DeezerTrackDetails? {
        guard let url = URL(string: "https://api.deezer.com/track/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerTrackDetails.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Failed to fetch Deezer track details: \(error)")
            return nil
        }
    }

    static func fetchDeezerTrack(id: Int) async -> DeezerSong? {
        guard let url = URL(string: "https://api.deezer.com/track/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerSong.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer track fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerAlbum(id: Int) async -> DeezerAlbumDetail? {
        guard let url = URL(string: "https://api.deezer.com/album/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerAlbumDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer album fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerPlaylist(id: Int) async -> DeezerPlaylistDetail? {
        guard let url = URL(string: "https://api.deezer.com/playlist/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerPlaylistDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer playlist fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerArtist(id: Int) async -> DeezerArtistDetail? {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)") else { return nil }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistDetail.self, from: data)
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist fetch failed for \(id): \(error)")
            return nil
        }
    }

    static func fetchDeezerArtistTopTracks(id: Int, limit: Int = 100) async -> [DeezerSong] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)/top?limit=\(limit)") else { return [] }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistTopTracksResult.self, from: data).data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist top tracks fetch failed for \(id): \(error)")
            return []
        }
    }

    static func fetchDeezerArtistAlbums(id: Int, limit: Int = 100) async -> [DeezerArtistAlbumSummary] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)/albums?limit=\(limit)") else { return [] }

        do {
            let (data, _) = try await SongMetadataNetworking.data(from: url)
            return try JSONDecoder().decode(DeezerArtistAlbumsResult.self, from: data).data
        } catch {
            Logger.shared.log("[SongMetadata] Deezer artist albums fetch failed for \(id): \(error)")
            return []
        }
    }

    
    
    static func applyDeezerMatch(_ match: DeezerSong, to song: SongMetadata) async -> SongMetadata {
        var newSong = song
        
        newSong.title = match.title
        newSong.artist = match.artist.name
        newSong.album = match.album.title
        
        if let explicit = match.explicit_lyrics {
            newSong.explicitRating = explicit ? 1 : 0
        }
        
        newSong.durationMs = match.duration * 1000
        
        
        if let details = await fetchDeezerTrackDetails(id: match.id) {
            newSong.trackNumber = details.track_position
            newSong.discNumber = details.disk_number
            
            if let releaseDate = details.release_date {
                
                let components = releaseDate.split(separator: "-")
                if let yearStr = components.first, let yearInt = Int(yearStr) {
                    newSong.year = yearInt
                }
            }
            Logger.shared.log("[SongMetadata] Enhanced with Deezer details: Trk \(details.track_position ?? 0), Disc \(details.disk_number ?? 0), Year \(newSong.year)")
        }
        
        
        if let artUrl = match.album.cover_xl.flatMap({ URL(string: $0) }),
           let (artData, _) = try? await SongMetadataNetworking.data(from: artUrl) {
            newSong.artworkData = artData
            Logger.shared.log("[SongMetadata] Updated artwork with Deezer High-Res version: \(artData.count) bytes")
        }
        
        return newSong
    }
    
    static func enrichWithDeezerMetadata(_ song: SongMetadata) async -> SongMetadata {
        Logger.shared.log("[SongMetadata] Searching Deezer for: \(song.artist) - \(song.title)")
        let query = "\(song.artist) \(song.title)"
        let results = await searchDeezer(query: query)
        
        var enrichedSong = song
        if let firstMatch = results.first {
             Logger.shared.log("[SongMetadata] ✓ Deezer match: \(firstMatch.title) by \(firstMatch.artist.name)")
             enrichedSong = await applyDeezerMatch(firstMatch, to: song)
        }
        
        if UserDefaults.standard.bool(forKey: "appleRichMetadata") {
            enrichedSong = await matchAppleMusicMetadata(enrichedSong)
        }
        
        return enrichedSong
    }
}
