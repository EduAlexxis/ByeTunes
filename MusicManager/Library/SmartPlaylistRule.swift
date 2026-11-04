import Foundation

struct SmartPlaylistRule: Codable, Equatable {
    enum Kind: String, Codable {
        case genre
        case decade
        case explicitRating
        case artist
        case fileFormat
    }

    let kind: Kind
    let values: [String]

    func matchingSongs(in songs: [DeviceManager.ExportableSongInfo]) -> [DeviceManager.ExportableSongInfo] {
        switch kind {
        case .genre:
            let set = Set(values)
            return songs.filter { set.contains($0.genre.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .decade:
            let decades = Set(values.compactMap { Int($0) })
            return songs.filter { $0.year > 0 && decades.contains(($0.year / 10) * 10) }
        case .explicitRating:
            let ratings = Set(values.compactMap { Int($0) })
            return songs.filter { ratings.contains($0.explicitRating) }
        case .artist:
            let set = Set(values)
            return songs.filter { song in
                !set.isDisjoint(with: DeviceLibraryBrowserView.splitArtistNames(song.artist))
            }
        case .fileFormat:
            let set = Set(values.map { $0.lowercased() })
            return songs.filter { set.contains($0.fileExtension.lowercased()) }
        }
    }
}
