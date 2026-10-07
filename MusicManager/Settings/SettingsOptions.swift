import Foundation

enum MetadataSourceOption: String, CaseIterable, Identifiable, CustomStringConvertible {
    case local
    case itunes
    case deezer
    case apple

    var id: String { rawValue }

    var description: String {
        switch self {
        case .local: return "Local Files"
        case .itunes: return "iTunes API"
        case .deezer: return "Deezer API (US only)"
        case .apple: return "Apple Music"
        }
    }
}

enum DownloadSearchProviderOption: String, CaseIterable, Identifiable, CustomStringConvertible {
    case appleMusic
    case spotify
    case tidal
    case metadata
    case itunes
    case deezer

    static var allCases: [DownloadSearchProviderOption] {
        [.appleMusic, .itunes, .deezer]
    }

    var id: String { rawValue }

    var description: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .tidal: return "Tidal"
        case .metadata: return "iTunes + Deezer"
        case .itunes: return "iTunes"
        case .deezer: return "Deezer"
        }
    }
}

struct MetadataStoreRegionOption: Identifiable, CustomStringConvertible, RawRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    var description: String {
        Locale.current.localizedString(forRegionCode: rawValue) ?? rawValue
    }

    static var allCases: [MetadataStoreRegionOption] {
        SongMetadata.storefrontMap.keys
            .map { MetadataStoreRegionOption(rawValue: $0.uppercased()) }
            .sorted { $0.description < $1.description }
    }
}

enum DownloaderYoinkifyFormatOption: String, CaseIterable, Identifiable, CustomStringConvertible {
    case mp3
    case flac
    case alac

    var id: String { rawValue }
    var description: String { rawValue.uppercased() }
}
