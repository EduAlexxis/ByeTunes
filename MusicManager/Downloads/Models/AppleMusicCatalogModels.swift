import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

struct AppleMusicAlbumResult: Decodable {
    let id: String
    let attributes: AppleMusicAlbumResultAttributes
}

struct AppleMusicAlbumResultAttributes: Decodable {
    let name: String
    let artistName: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

struct AppleMusicAlbumDetailsData: Decodable {
    let id: String?
    let attributes: AppleMusicDirectAlbumAttributes?
    let relationships: AppleMusicAlbumRelationships?
}

struct AppleMusicDirectAlbumAttributes: Decodable {
    let name: String
    let artistName: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
    let playParams: AppleMusicPlayParams?
}

struct AppleMusicPlayParams: Decodable {
    let id: String?
}

struct AppleMusicAlbumRelationships: Decodable {
    let tracks: AppleMusicAlbumTracksPage?
}

struct AppleMusicAlbumTracksPage: Decodable {
    let data: [AppleMusicAlbumTrack]
}

struct AppleMusicAlbumTrack: Decodable {
    let id: String
    let attributes: AppleMusicAlbumTrackAttributes
}

struct AppleMusicAlbumTrackAttributes: Decodable {
    let name: String
    let artistName: String
    let albumName: String?
    let url: String?
    let contentRating: String?
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

struct AppleMusicArtistResult: Decodable {
    let id: String
    let attributes: AppleMusicArtistAttributes
}

struct AppleMusicArtistAttributes: Decodable {
    let name: String
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

struct AppleMusicPlaylistResult: Decodable {
    let id: String
    let attributes: AppleMusicPlaylistAttributes
    let relationships: AppleMusicPlaylistRelationships?
}

struct AppleMusicPlaylistAttributes: Decodable {
    let name: String
    let curatorName: String?
    let artwork: AppleMusicAPI.AppleMusicArtwork?
}

struct AppleMusicPlaylistRelationships: Decodable {
    let tracks: AppleMusicPlaylistTracksPage?
}

struct AppleMusicPlaylistTracksPage: Decodable {
    let data: [AppleMusicAPI.AppleMusicSong]
}
