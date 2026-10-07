import Foundation
import SQLite3
import CommonCrypto
import UIKit

// MARK: - Database Version Support
struct DatabaseVersion: Equatable {
    enum SchemaFamily: Equatable {
        case ios16
        case ios17Or18
        case ios26
        case ios26Subscription
    }

    var major: Int
    var minor: Int = 0
    var patch: Int = 0
    var isSubscription: Bool = false

    init(major: Int, minor: Int = 0, patch: Int = 0, isSubscription: Bool = false) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.isSubscription = isSubscription
    }

    static func ios(_ major: Int, minor: Int = 0, patch: Int = 0, isSub: Bool = false) -> DatabaseVersion {
        return DatabaseVersion(major: major, minor: minor, patch: patch, isSubscription: isSub)
    }

    static var unknown: DatabaseVersion {
        return DatabaseVersion(major: 16)
    }

    var schemaFamily: SchemaFamily {
        switch major {
        case 26:
            return isSubscription ? .ios26Subscription : .ios26
        case 17, 18:
            return .ios17Or18
        case 16:
            return .ios16
        default:
            return .ios16
        }
    }

    var userVersion: Int32 {
        switch schemaFamily {
        case .ios26Subscription:
            return 2310000
        case .ios26:
            return 2320030
        case .ios17Or18:
            return 2120020
        case .ios16:
            return 2320030
        }
    }

    var hasCanonicalIDs: Bool {
        switch schemaFamily {
        case .ios26, .ios26Subscription:
            return true
        case .ios16, .ios17Or18:
            return false
        }
    }

    var hasAlbumArtistSortColumns: Bool {
        switch schemaFamily {
        case .ios16:
            return false
        case .ios17Or18, .ios26, .ios26Subscription:
            return true
        }
    }

    var hasAlbumStoreId: Bool {
        switch schemaFamily {
        case .ios16:
            return false
        case .ios17Or18, .ios26, .ios26Subscription:
            return true
        }
    }

    var supportsIOS264ArtworkDisplay: Bool {
        if major > 26 { return true }
        return major == 26 && minor >= 4
    }

    var description: String {
        let version = patch > 0 ? "\(major).\(minor).\(patch)" : (minor > 0 ? "\(major).\(minor)" : "\(major)")
        return "iOS \(version)\(isSubscription ? " (Subscription)" : "")"
    }
}
