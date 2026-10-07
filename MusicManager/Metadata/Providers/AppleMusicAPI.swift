import Foundation
import AVFoundation
import UIKit
import CryptoKit
import CommonCrypto
import CoreMedia
import AudioToolbox

// MARK: - Apple Music API
actor AppleMusicAPI {
    static let shared = AppleMusicAPI()
    private let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    
    
    
    
    struct AppleMusicSong: Codable, Identifiable {
        let id: String
        let attributes: AppleMusicSongAttributes
        let relationships: AppleMusicSongRelationships?
    }
    
    struct AppleMusicSongAttributes: Codable {
        let name: String
        let artistName: String
        let albumName: String?
        let url: String?
        let audioTraits: [String]?
        let genreNames: [String]?
        let isrc: String?
        let contentRating: String?
        let releaseDate: String?
        let trackNumber: Int?
        let discNumber: Int?
        let durationInMillis: Int?
        let isAppleDigitalMaster: Bool?
        let isMasteredForItunes: Bool?
        let artwork: AppleMusicArtwork?
    }
    
    struct AppleMusicArtwork: Codable {
        let width: Int
        let height: Int
        let url: String
        let bgColor: String?
        let textColor1: String?
        let textColor2: String?
        let textColor3: String?
        let textColor4: String?
        
        var colors: AppleMusicArtworkColors? {
            guard let bgColor else {
                return nil
            }
            return AppleMusicArtworkColors(
                backgroundColor: bgColor,
                primaryTextColor: textColor1 ?? "FFFFFF",
                secondaryTextColor: textColor2 ?? textColor1 ?? "FFFFFF",
                tertiaryTextColor: textColor3 ?? textColor2 ?? textColor1 ?? "CCCCCC"
            )
        }
        
        func artworkURL(width w: Int = 1000, height h: Int = 1000) -> URL? {
            let processed = url.replacingOccurrences(of: "{w}", with: "\(w)")
                             .replacingOccurrences(of: "{h}", with: "\(h)")
                             .replacingOccurrences(of: "{c}", with: "bb")
                             .replacingOccurrences(of: "{f}", with: "jpg")
            return URL(string: processed)
        }
    }
    
    struct AppleMusicSongRelationships: Codable {
        let albums: AppleMusicAlbumsPage?
        let artists: AppleMusicDataPage?
        let composers: AppleMusicDataPage?
        let genres: AppleMusicDataPage?
    }
    
    struct AppleMusicDataPage: Codable {
        let data: [AppleMusicReference]
    }
    
    struct AppleMusicReference: Codable {
        let id: String
    }
    
    struct AppleMusicAlbumsPage: Codable {
        let data: [AppleMusicAlbum]
    }
    
    struct AppleMusicAlbum: Codable {
        let id: String
        let attributes: AppleMusicAlbumAttributes
    }
    
    struct AppleMusicAlbumAttributes: Codable {
        let copyright: String?
        let releaseDate: String?
    }

    struct PublicCatalogAlbum: Identifiable {
        let id: String
        let name: String
        let artistName: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    struct PublicCatalogPlaylist: Identifiable {
        let id: String
        let name: String
        let curatorName: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    struct PublicCatalogArtist: Identifiable {
        let id: String
        let name: String
        let url: String
        let artwork: AppleMusicArtwork?
    }

    private struct PublicSearchPageEnvelope: Decodable {
        let data: [PublicSearchPageNode]
    }

    private struct PublicSearchPageNode: Decodable {
        let data: PublicSearchPageData
    }

    private struct PublicSearchPageData: Decodable {
        let sections: [PublicSearchSection]
    }

    private struct PublicSearchSection: Decodable {
        let header: PublicSearchSectionHeader?
        let items: [PublicSearchItem]?
    }

    private struct PublicSearchSectionHeader: Decodable {
        let item: PublicSearchHeaderItem?
    }

    private struct PublicSearchHeaderItem: Decodable {
        let titleLink: PublicSearchTextLink?
    }

    private struct PublicSearchItem: Decodable {
        let title: String?
        let titleLinks: [PublicSearchTextLink]?
        let subtitle: String?
        let subtitleLinks: [PublicSearchTextLink]?
        let artwork: PublicSearchArtworkWrapper?
        let contentDescriptor: PublicSearchContentDescriptor?
        let segue: PublicSearchSegue?
        let duration: Int?
        let showExplicitBadge: Bool?
    }

    private struct PublicSearchTextLink: Decodable {
        let title: String?
        let segue: PublicSearchSegue?
    }

    private struct PublicSearchArtworkWrapper: Decodable {
        let dictionary: PublicSearchArtworkDictionary?
    }

    private struct PublicSearchArtworkDictionary: Decodable {
        let width: Int?
        let height: Int?
        let url: String?
        let bgColor: String?
        let textColor1: String?
        let textColor2: String?
        let textColor3: String?
        let textColor4: String?
    }

    private struct PublicSearchContentDescriptor: Decodable {
        let identifiers: PublicSearchIdentifiers?
        let url: String?
    }

    private struct PublicSearchIdentifiers: Decodable {
        let storeAdamID: String?
    }

    private struct PublicSearchSegue: Decodable {
        let subactions: [PublicSearchSubaction]?
        let destination: PublicSearchDestination?
    }

    private struct PublicSearchSubaction: Decodable {
        let destination: PublicSearchDestination?
    }

    private struct PublicSearchDestination: Decodable {
        let contentDescriptor: PublicSearchContentDescriptor?
        let prominentItemIdentifier: String?
    }

    private struct PublicAlbumPageEnvelope: Decodable {
        let data: [PublicAlbumPageNode]
    }

    private struct PublicAlbumPageNode: Decodable {
        let intent: PublicAlbumPageIntent?
        let data: PublicAlbumPageData
    }

    private struct PublicAlbumPageIntent: Decodable {
        let contentDescriptor: PublicSearchContentDescriptor?
        let prominentItemIdentifier: String?
    }

    private struct PublicAlbumPageData: Decodable {
        let sections: [PublicAlbumPageSection]
    }

    private struct PublicAlbumPageSection: Decodable {
        let id: String?
        let itemKind: String?
        let items: [PublicAlbumPageItem]?
    }

    private struct PublicAlbumPageItem: Decodable {
        let title: String?
        let tertiaryLinks: [PublicSearchTextLink]?
        let subtitleLinks: [PublicSearchTextLink]?
        let quaternaryTitle: String?
        let artwork: PublicSearchArtworkWrapper?
        let tallArtwork: PublicSearchArtworkWrapper?
        let uberArtwork: PublicSearchArtworkWrapper?
        let audioBadges: PublicAlbumAudioBadges?
        let contentDescriptor: PublicSearchContentDescriptor?
        let trackNumber: Int?
        let duration: Int?
        let showExplicitBadge: Bool?
        let composer: String?
        let discNumber: Int?
        let artistName: String?
        let previewUrl: String?
        let isProminent: Bool?
    }

    private struct PublicAlbumAudioBadges: Decodable {
        let dolbyAtmos: Bool?
        let lossless: Bool?
        let hiResLossless: Bool?
        let digitalMaster: Bool?
    }

    func searchSongs(query: String, limit: Int = 5, offset: Int = 0) async -> [AppleMusicSong] {
        return await searchSongsViaPublicSearch(query: query, limit: limit, offset: offset).songs
    }

    func searchSongsWithAvailability(query: String, limit: Int, offset: Int) async -> (songs: [AppleMusicSong], hasMore: Bool) {
        return await searchSongsViaPublicSearch(query: query, limit: limit, offset: offset)
    }

    func searchSong(query: String, albumHint: String? = nil, titleHint: String? = nil, requireAlbumMatch: Bool = false) async -> AppleMusicSong? {
        let hasAlbumHint = albumHint.map { !$0.isEmpty && $0 != "Unknown Album" } ?? false
        let hasTitleHint = titleHint.map { !Self.titleKey($0).isEmpty } ?? false
        let candidates: [AppleMusicSong]
        if hasTitleHint {
            candidates = await searchSongs(query: query, limit: 10, offset: 0)
        } else if hasAlbumHint {
            candidates = await searchSongs(query: query, limit: 5, offset: 0)
        } else {
            candidates = await searchSongs(query: query, limit: 1, offset: 0)
        }

        guard let song = Self.bestMatch(for: candidates, albumHint: albumHint, titleHint: titleHint, requireAlbumMatch: requireAlbumMatch) else {
            return nil
        }

        if song.attributes.audioTraits != nil || song.attributes.trackNumber != nil {
            return song
        }

        if let detailed = await fetchSongViaPublicPage(urlString: song.attributes.url, expectedTrackID: song.id) {
            return detailed
        }

        return song
    }

    private static func titleKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func fullTitleKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func bestMatch(for candidates: [AppleMusicSong], albumHint: String?, titleHint: String?, requireAlbumMatch: Bool = false) -> AppleMusicSong? {
        let hintKey = titleHint.map { titleKey($0) } ?? ""
        let hintFullKey = titleHint.map { fullTitleKey($0) } ?? ""
        var pool = candidates

        if !hintKey.isEmpty {
            let fullExact = candidates.filter { fullTitleKey($0.attributes.name) == hintFullKey }
            let exact = candidates.filter { titleKey($0.attributes.name) == hintKey }
            if !fullExact.isEmpty {
                pool = fullExact
            } else if !exact.isEmpty && !requireAlbumMatch {
                pool = exact
            } else if requireAlbumMatch {
                return nil
            } else {
                let loose = candidates.filter { candidate in
                    let key = titleKey(candidate.attributes.name)
                    return !key.isEmpty && (key.contains(hintKey) || hintKey.contains(key))
                }
                guard !loose.isEmpty else { return nil }
                pool = loose
            }
        }

        guard let albumHint, !albumHint.isEmpty, albumHint != "Unknown Album" else {
            return pool.first
        }

        let normalizedHint = fullTitleKey(albumHint)
        if let albumMatch = pool.first(where: { candidate in
            guard let candidateAlbum = candidate.attributes.albumName else { return false }
            let normalizedCandidate = fullTitleKey(candidateAlbum)
            return normalizedCandidate.contains(normalizedHint) || normalizedHint.contains(normalizedCandidate)
        }) {
            return albumMatch
        }

        return requireAlbumMatch ? nil : pool.first
    }

    func fetchSong(id: String, urlHint: String? = nil) async -> AppleMusicSong? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let publicURL = urlHint ?? "https://music.apple.com/\(region)/song/\(id)"
        if let publicSong = await fetchSongViaPublicPage(urlString: publicURL, expectedTrackID: id) {
            return publicSong
        }
        return nil
    }

    func searchAlbumsPublic(query: String, limit: Int = 15, offset: Int = 0) async -> [PublicCatalogAlbum] {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Albums")
        guard offset < sectionItems.count else { return [] }
        let slice = sectionItems.dropFirst(offset).prefix(limit)
        return slice.compactMap { item in
            guard let id = item.contentDescriptor?.identifiers?.storeAdamID,
                  let url = item.contentDescriptor?.url,
                  let name = item.titleLinks?.first?.title ?? item.title else {
                return nil
            }
            let artistName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Unknown Artist"
            return PublicCatalogAlbum(
                id: id,
                name: name,
                artistName: artistName,
                url: url,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            )
        }
    }

    func searchPlaylistsPublic(query: String, limit: Int = 15, offset: Int = 0) async -> [PublicCatalogPlaylist] {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Playlists")
        guard offset < sectionItems.count else { return [] }
        let slice = sectionItems.dropFirst(offset).prefix(limit)
        return slice.compactMap { item in
            guard let id = item.contentDescriptor?.identifiers?.storeAdamID,
                  let url = item.contentDescriptor?.url,
                  let name = item.titleLinks?.first?.title ?? item.title else {
                return nil
            }
            let curatorName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Apple Music Playlist"
            return PublicCatalogPlaylist(
                id: id,
                name: name,
                curatorName: curatorName,
                url: url,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            )
        }
    }

    func fetchAlbumPublic(id: String, urlHint: String? = nil) async -> PublicCatalogAlbum? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/album/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let albumID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let artistName = headerItem?.subtitleLinks?.first?.title ?? "Unknown Artist"
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)

        return PublicCatalogAlbum(
            id: albumID,
            name: name,
            artistName: artistName,
            url: url,
            artwork: mapPublicArtwork(headerItem?.artwork?.dictionary)
        )
    }

    func fetchAlbumTracksPublic(id: String, urlHint: String? = nil) async -> [AppleMusicSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/album/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return []
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let albumID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id
        let albumName = headerItem?.title ?? "Unknown Album"
        let defaultArtist = headerItem?.subtitleLinks?.first?.title ?? "Unknown Artist"
        let artistID = headerItem?.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let releaseDate = parsePublicReleaseDate(headerItem?.quaternaryTitle)
        let fallbackArtwork = mapPublicArtwork(headerItem?.artwork?.dictionary)
        let audioTraits = traits(from: headerItem?.audioBadges)

        let trackItems = node.data.sections
            .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
            .items ?? []

        return trackItems.compactMap { item in
            guard let trackID = item.contentDescriptor?.identifiers?.storeAdamID,
                  let title = item.title else {
                return nil
            }

            let artistName = item.artistName ?? defaultArtist
            let artwork = mapPublicArtwork(item.artwork?.dictionary) ?? fallbackArtwork
            let relationships = AppleMusicSongRelationships(
                albums: AppleMusicAlbumsPage(data: [
                    AppleMusicAlbum(
                        id: albumID,
                        attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: releaseDate)
                    )
                ]),
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            return AppleMusicSong(
                id: trackID,
                attributes: AppleMusicSongAttributes(
                    name: title,
                    artistName: artistName,
                    albumName: albumName,
                    url: item.contentDescriptor?.url,
                    audioTraits: audioTraits,
                    genreNames: parsePublicGenres(headerItem?.quaternaryTitle),
                    isrc: nil,
                    contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                    releaseDate: releaseDate,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    durationInMillis: item.duration,
                    isAppleDigitalMaster: headerItem?.audioBadges?.digitalMaster ?? false,
                    isMasteredForItunes: headerItem?.audioBadges?.digitalMaster ?? false,
                    artwork: artwork
                ),
                relationships: relationships
            )
        }
    }

    func fetchPlaylistPublic(id: String, urlHint: String? = nil) async -> PublicCatalogPlaylist? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/playlist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let playlistID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let curatorName = headerItem?.subtitleLinks?.first?.title ?? "Apple Music Playlist"
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let artwork = mapPublicArtwork(headerItem?.tallArtwork?.dictionary) ?? mapPublicArtwork(headerItem?.artwork?.dictionary)

        return PublicCatalogPlaylist(
            id: playlistID,
            name: name,
            curatorName: curatorName,
            url: url,
            artwork: artwork
        )
    }

    func fetchPlaylistTracksPublic(id: String, urlHint: String? = nil) async -> [AppleMusicSong] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/playlist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return []
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
            .items?
            .first

        let playlistURL = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let fallbackArtwork = mapPublicArtwork(headerItem?.artwork?.dictionary)

        let trackItems = node.data.sections
            .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
            .items ?? []

        return trackItems.compactMap { item in
            guard let trackID = item.contentDescriptor?.identifiers?.storeAdamID,
                  let title = item.title else {
                return nil
            }

            let artistName = item.subtitleLinks?.first?.title ?? item.artistName ?? "Unknown Artist"
            let artistID = item.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let albumName = item.tertiaryLinks?.first?.title
            let albumID = item.tertiaryLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let artwork = mapPublicArtwork(item.artwork?.dictionary) ?? fallbackArtwork
            let audioTraits = traits(from: item.audioBadges)

            let relationships = AppleMusicSongRelationships(
                albums: albumID.map {
                    AppleMusicAlbumsPage(data: [
                        AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: nil))
                    ])
                },
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            return AppleMusicSong(
                id: trackID,
                attributes: AppleMusicSongAttributes(
                    name: title,
                    artistName: artistName,
                    albumName: albumName,
                    url: item.contentDescriptor?.url ?? playlistURL,
                    audioTraits: audioTraits,
                    genreNames: nil,
                    isrc: nil,
                    contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                    releaseDate: nil,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    durationInMillis: item.duration,
                    isAppleDigitalMaster: item.audioBadges?.digitalMaster,
                    isMasteredForItunes: item.audioBadges?.digitalMaster,
                    artwork: artwork
                ),
                relationships: relationships
            )
        }
    }

    func fetchArtistPublic(id: String, urlHint: String? = nil) async -> PublicCatalogArtist? {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        let fallbackURL = "https://music.apple.com/\(region)/artist/\(id)"
        guard let node = await fetchPublicCatalogPageNode(urlString: urlHint ?? fallbackURL) else {
            return nil
        }

        let headerItem = node.data.sections
            .first(where: { ($0.itemKind ?? "").contains("artistDetailHeaderLockup") })?
            .items?
            .first

        let artistID = node.intent?.contentDescriptor?.identifiers?.storeAdamID ??
            headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
            id

        guard let name = headerItem?.title, !name.isEmpty else { return nil }
        let url = node.intent?.contentDescriptor?.url ?? headerItem?.contentDescriptor?.url ?? (urlHint ?? fallbackURL)
        let artwork = mapPublicArtwork(headerItem?.uberArtwork?.dictionary) ?? mapPublicArtwork(headerItem?.artwork?.dictionary)

        return PublicCatalogArtist(
            id: artistID,
            name: name,
            url: url,
            artwork: artwork
        )
    }

    private func fetchPublicSearchSection(query: String, title: String) async -> [PublicSearchItem] {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        var components = URLComponents(string: "https://music.apple.com/\(region)/search")!
        components.queryItems = [URLQueryItem(name: "term", value: query), URLQueryItem(name: "l", value: "en")]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html) else {
                await Logger.shared.log("[AppleMusicAPI] Public search page JSON was not found for query: \(query)")
                return []
            }

            let jsonString = String(html[range])
            guard let jsonData = jsonString.data(using: .utf8) else { return [] }
            let decoded = try JSONDecoder().decode(PublicSearchPageEnvelope.self, from: jsonData)
            let sections = decoded.data.first?.data.sections ?? []
            let matchedSection = sections.first { section in
                section.header?.item?.titleLink?.title == title
            }
            return matchedSection?.items ?? []
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public search page fallback failed for \(title): \(error)")
            return []
        }
    }

    private func fetchPublicCatalogPageNode(urlString: String) async -> PublicAlbumPageNode? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let jsonData = String(html[range]).data(using: .utf8) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(PublicAlbumPageEnvelope.self, from: jsonData)
            return decoded.data.first
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public catalog page fetch failed for \(urlString): \(error)")
            return nil
        }
    }

    private func searchSongsViaPublicSearch(query: String, limit: Int, offset: Int) async -> (songs: [AppleMusicSong], hasMore: Bool) {
        let sectionItems = await fetchPublicSearchSection(query: query, title: "Songs")
        guard offset < sectionItems.count else { return ([], false) }
        let hasMore = sectionItems.count > offset + limit
        let page = Array(sectionItems.dropFirst(offset).prefix(limit))

        let lightweightSongs = page.compactMap(mapPublicSearchSong)
        guard !lightweightSongs.isEmpty else { return ([], false) }

        let songs = await withTaskGroup(of: (Int, AppleMusicSong).self) { group in
            for (index, song) in lightweightSongs.enumerated() {
                group.addTask {
                    if song.attributes.albumName != nil {
                        return (index, song)
                    }

                    if let hydrated = await self.fetchSongViaPublicPage(
                        urlString: song.attributes.url,
                        expectedTrackID: song.id
                    ) {
                        return (index, hydrated)
                    }

                    return (index, song)
                }
            }

            var orderedSongs = Array<AppleMusicSong?>(repeating: nil, count: lightweightSongs.count)
            for await (index, song) in group {
                orderedSongs[index] = song
            }
            return orderedSongs.compactMap { $0 }
        }
        return (songs, hasMore)
    }

    private func fetchSongViaPublicPage(urlString: String?, expectedTrackID: String) async -> AppleMusicSong? {
        guard let urlString, let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await SongMetadataNetworking.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = #"<script[^>]*type="application/json"[^>]*>(.*?)</script>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let jsonData = String(html[range]).data(using: .utf8) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(PublicAlbumPageEnvelope.self, from: jsonData)
            guard let node = decoded.data.first else { return nil }
            let sections = node.data.sections
            let prominentID = node.intent?.prominentItemIdentifier ?? expectedTrackID

            let headerItem = sections
                .first(where: { ($0.itemKind ?? "").contains("containerDetailHeaderLockup") })?
                .items?
                .first

            let trackItems = sections
                .first(where: { ($0.id ?? "").contains("track-list") || ($0.itemKind ?? "").contains("trackLockup") })?
                .items ?? []

            guard let matchedTrack = trackItems.first(where: {
                $0.contentDescriptor?.identifiers?.storeAdamID == expectedTrackID ||
                $0.contentDescriptor?.identifiers?.storeAdamID == prominentID ||
                $0.isProminent == true
            }) else {
                return nil
            }

            let albumID = headerItem?.contentDescriptor?.identifiers?.storeAdamID ??
                matchedTrack.contentDescriptor?.identifiers?.storeAdamID
            let artistID = headerItem?.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
            let releaseDate = parsePublicReleaseDate(headerItem?.quaternaryTitle)
            let artwork = matchedTrack.artwork?.dictionary.flatMap(mapPublicArtwork) ?? headerItem?.artwork?.dictionary.flatMap(mapPublicArtwork)
            let audioTraits = traits(from: headerItem?.audioBadges)
            let artistName = matchedTrack.artistName ??
                headerItem?.subtitleLinks?.first?.title ??
                "Unknown Artist"
            let albumName = headerItem?.title ?? "Unknown Album"
            let contentRating = (matchedTrack.showExplicitBadge ?? false) ? "explicit" : nil

            let relationships = AppleMusicSongRelationships(
                albums: albumID.map { AppleMusicAlbumsPage(data: [AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: releaseDate))]) },
                artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
                composers: nil,
                genres: nil
            )

            let song = AppleMusicSong(
                id: expectedTrackID,
                attributes: AppleMusicSongAttributes(
                    name: matchedTrack.title ?? "Unknown Title",
                    artistName: artistName,
                    albumName: albumName,
                    url: matchedTrack.contentDescriptor?.url ?? urlString,
                    audioTraits: audioTraits,
                    genreNames: parsePublicGenres(headerItem?.quaternaryTitle),
                    isrc: nil,
                    contentRating: contentRating,
                    releaseDate: releaseDate,
                    trackNumber: matchedTrack.trackNumber,
                    discNumber: matchedTrack.discNumber,
                    durationInMillis: matchedTrack.duration,
                    isAppleDigitalMaster: headerItem?.audioBadges?.digitalMaster ?? false,
                    isMasteredForItunes: headerItem?.audioBadges?.digitalMaster ?? false,
                    artwork: artwork
                ),
                relationships: relationships
            )
            return song
        } catch {
            await Logger.shared.log("[AppleMusicAPI] Public song page fallback failed for \(expectedTrackID): \(error)")
            return nil
        }
    }

    private func mapPublicSearchSong(_ item: PublicSearchItem) -> AppleMusicSong? {
        let trackID = item.contentDescriptor?.identifiers?.storeAdamID ??
            item.segue?.subactions?.last?.destination?.prominentItemIdentifier
        guard let trackID,
              let title = item.title,
              let url = item.contentDescriptor?.url else {
            return nil
        }

        let artistName = item.subtitleLinks?.first?.title ?? item.subtitle ?? "Unknown Artist"
        let artistID = item.subtitleLinks?.first?.segue?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let albumID = item.segue?.subactions?.last?.destination?.contentDescriptor?.identifiers?.storeAdamID
        let relationships = AppleMusicSongRelationships(
            albums: albumID.map { AppleMusicAlbumsPage(data: [AppleMusicAlbum(id: $0, attributes: AppleMusicAlbumAttributes(copyright: nil, releaseDate: nil))]) },
            artists: artistID.map { AppleMusicDataPage(data: [AppleMusicReference(id: $0)]) },
            composers: nil,
            genres: nil
        )

        return AppleMusicSong(
            id: trackID,
            attributes: AppleMusicSongAttributes(
                name: title,
                artistName: artistName,
                albumName: nil,
                url: url,
                audioTraits: nil,
                genreNames: nil,
                isrc: nil,
                contentRating: (item.showExplicitBadge ?? false) ? "explicit" : nil,
                releaseDate: nil,
                trackNumber: nil,
                discNumber: nil,
                durationInMillis: item.duration,
                isAppleDigitalMaster: nil,
                isMasteredForItunes: nil,
                artwork: mapPublicArtwork(item.artwork?.dictionary)
            ),
            relationships: relationships
        )
    }

    private func traits(from badges: PublicAlbumAudioBadges?) -> [String] {
        guard let badges else { return [] }
        var values: [String] = ["lossy-stereo"]
        if badges.hiResLossless == true { values.append("hi-res-lossless") }
        if badges.lossless == true { values.append("lossless") }
        if badges.dolbyAtmos == true {
            values.append("atmos")
            values.append("spatial")
        }
        return values
    }

    private func parsePublicGenres(_ quaternaryTitle: String?) -> [String]? {
        guard let quaternaryTitle else { return nil }
        let components = quaternaryTitle
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = components.first, !first.isEmpty else { return nil }
        return [first]
    }

    private func parsePublicReleaseDate(_ quaternaryTitle: String?) -> String? {
        guard let quaternaryTitle else { return nil }
        let components = quaternaryTitle
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let yearComponent = components.last, yearComponent.allSatisfy(\.isNumber) {
            return yearComponent
        }
        return nil
    }

    private func mapPublicArtwork(_ dictionary: PublicSearchArtworkDictionary?) -> AppleMusicArtwork? {
        guard let dictionary, let url = dictionary.url else { return nil }
        return AppleMusicArtwork(
            width: dictionary.width ?? 1000,
            height: dictionary.height ?? 1000,
            url: url,
            bgColor: dictionary.bgColor,
            textColor1: dictionary.textColor1,
            textColor2: dictionary.textColor2,
            textColor3: dictionary.textColor3,
            textColor4: dictionary.textColor4
        )
    }
}
