import Foundation
import Combine
import SwiftUI

/// A favorited/rated song imported from the device's MediaLibrary (`item_stats`).
struct DeviceFavorite: Codable, Identifiable {
    let itemPid: Int64
    let title: String
    let artist: String
    let album: String
    /// 0 none, 1 disliked, 2 loved (favorite). Mirrors `item_stats.liked_state`.
    let likedState: Int
    /// Star rating 0–5. Mirrors `item_stats.user_rating`.
    let userRating: Int
    let playCount: Int
    /// When the like/rating was last changed on device (Apple reference date, 2001-01-01).
    let likedStateChangedDate: Double

    var id: Int64 { itemPid }
    var isLoved: Bool { likedState == 2 }
    var isDisliked: Bool { likedState == 1 }
    var dateFavorited: Date {
        Date(timeIntervalSinceReferenceDate: likedStateChangedDate)
    }
}

/// Local persistence for favorites & ratings imported from the device.
/// Keyed by `item_pid`, so re-importing replaces entries for the same songs.
final class DeviceFavoritesStore: ObservableObject {
    static let shared = DeviceFavoritesStore()

    private static let storageKey = "ByeTunes.importedDeviceFavorites"

    @Published var favorites: [DeviceFavorite] = []

    private init() {
        load()
    }

    var lovedCount: Int { favorites.filter(\.isLoved).count }
    var ratedCount: Int { favorites.filter { $0.userRating > 0 }.count }

    func replaceAll(_ newFavorites: [DeviceFavorite]) {
        favorites = newFavorites.sorted {
            if $0.likedStateChangedDate != $1.likedStateChangedDate {
                return $0.likedStateChangedDate > $1.likedStateChangedDate
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        save()
    }

    func clear() {
        favorites = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([DeviceFavorite].self, from: data) {
            favorites = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
