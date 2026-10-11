import Foundation
import Combine
import UIKit
import SwiftUI

enum ServerState: String {
    case active
    case maintenance
    case dead
}

struct ServerStatusStateConfig: Codable {
    var title: String?
    var message: String?
    var icon: String?
    var color: String?
    var showBanner: Bool?
    var blockDownloads: Bool?
    var blockMessage: String?
    var dismissible: Bool?
    var buttonTitle: String?
    var buttonURL: String?
    var eta: String?
    var etaLabel: String?

    func overlaid(on base: ServerStatusStateConfig) -> ServerStatusStateConfig {
        ServerStatusStateConfig(
            title: title ?? base.title,
            message: message ?? base.message,
            icon: icon ?? base.icon,
            color: color ?? base.color,
            showBanner: showBanner ?? base.showBanner,
            blockDownloads: blockDownloads ?? base.blockDownloads,
            blockMessage: blockMessage ?? base.blockMessage,
            dismissible: dismissible ?? base.dismissible,
            buttonTitle: buttonTitle ?? base.buttonTitle,
            buttonURL: buttonURL ?? base.buttonURL,
            eta: eta ?? base.eta,
            etaLabel: etaLabel ?? base.etaLabel
        )
    }
}

struct ServerStatusFile: Codable {
    var status: String
    var updatedAt: String?
    var startsAt: String?
    var expiresAt: String?
    var minVersion: String?
    var maxVersion: String?
    var states: [String: ServerStatusStateConfig]?
    var overrides: ServerStatusStateConfig

    private enum CodingKeys: String, CodingKey {
        case status, updatedAt, startsAt, expiresAt, minVersion, maxVersion, states
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
        minVersion = try container.decodeIfPresent(String.self, forKey: .minVersion)
        maxVersion = try container.decodeIfPresent(String.self, forKey: .maxVersion)
        states = try container.decodeIfPresent([String: ServerStatusStateConfig].self, forKey: .states)
        overrides = try ServerStatusStateConfig(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(minVersion, forKey: .minVersion)
        try container.encodeIfPresent(maxVersion, forKey: .maxVersion)
        try container.encodeIfPresent(states, forKey: .states)
        try overrides.encode(to: encoder)
    }
}

struct ResolvedServerStatus: Equatable {
    var state: ServerState = .active
    var title = ""
    var message = ""
    var icon = "checkmark.circle.fill"
    var colorName = "green"
    var showBanner = false
    var blockDownloads = false
    var blockMessage: String?
    var dismissible = false
    var buttonTitle: String?
    var buttonURL: URL?
    var eta: Date?
    var etaLabel = "Back around"
    var bannerID = "active"
}

private struct StoredServerStatus: Codable {
    let file: ServerStatusFile
    let savedAt: Date
}

@MainActor
final class ServerStatusStore: ObservableObject {
    static let shared = ServerStatusStore()

    @Published private(set) var resolved = ResolvedServerStatus()
    @Published private(set) var dismissedIDs: Set<String> = []

    private static let sourceURLs = [
        "https://raw.githubusercontent.com/EduAlexxis/EduAlexxis-Altstore-Repo/main/ServerStatus.json"
    ]
    private static let storedKey = "serverStatus.last.v2"
    private static let dismissedKey = "serverStatus.dismissed.v1"
    private static let storedMaxAge: TimeInterval = 6 * 60 * 60
    private static let minRefreshInterval: TimeInterval = 20

    private var lastFile: ServerStatusFile?
    private var lastRefresh = Date.distantPast
    private var isRefreshing = false
    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?

    private init() {
        dismissedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
        loadStored()
    }

    var isVisible: Bool {
        resolved.showBanner && !dismissedIDs.contains(resolved.bannerID)
    }

    var blocksDownloads: Bool {
        resolved.blockDownloads
    }

    var blockedDownloadMessage: String {
        if let custom = resolved.blockMessage, !custom.isEmpty { return custom }
        return [resolved.title, resolved.message].filter { !$0.isEmpty }.joined(separator: ": ")
    }

    func dismissBanner() {
        guard resolved.dismissible else { return }
        dismissedIDs.insert(resolved.bannerID)
        UserDefaults.standard.set(Array(dismissedIDs.suffix(40)), forKey: Self.dismissedKey)
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.refresh()
            }
        }
        Task { await refresh(force: true) }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        guard force || Date().timeIntervalSince(lastRefresh) >= Self.minRefreshInterval else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            guard let data = try await loadData() else {
                lastRefresh = Date()
                return
            }
            let file = try JSONDecoder().decode(ServerStatusFile.self, from: data)
            lastRefresh = Date()
            apply(file)
            store(file)
        } catch {
            Logger.shared.log("[ServerStatus] Could not load the status file: \(error.localizedDescription)")
        }
    }

    private func loadData() async throws -> Data? {
        var lastError: Error?
        for source in Self.sourceURLs {
            guard let url = URL(string: source) else { continue }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 8
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    Logger.shared.log("[ServerStatus] Unexpected response from \(url.host ?? "source")")
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    private func apply(_ file: ServerStatusFile) {
        if lastFile == nil || lastFile?.status != file.status {
            Logger.shared.log("[ServerStatus] Loaded status file: \(file.status)")
        }
        lastFile = file
        let newResolved = Self.resolve(file)
        if newResolved.state != resolved.state {
            Logger.shared.log("[ServerStatus] Status is now \(newResolved.state.rawValue)")
        }
        resolved = newResolved
    }

    private func store(_ file: ServerStatusFile) {
        let stored = StoredServerStatus(file: file, savedAt: Date())
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storedKey)
        }
    }

    private func loadStored() {
        guard let data = UserDefaults.standard.data(forKey: Self.storedKey),
              let stored = try? JSONDecoder().decode(StoredServerStatus.self, from: data),
              Date().timeIntervalSince(stored.savedAt) < Self.storedMaxAge else { return }
        apply(stored.file)
    }

    private static func builtInDefaults(for state: ServerState) -> ServerStatusStateConfig {
        switch state {
        case .active:
            return ServerStatusStateConfig()
        case .maintenance:
            return ServerStatusStateConfig(
                title: "Server Maintenance",
                message: "Downloads may be slow or fail while the server is being updated.",
                icon: "wrench.and.screwdriver.fill", color: "orange",
                showBanner: true, blockDownloads: false, dismissible: false, etaLabel: "Back around"
            )
        case .dead:
            return ServerStatusStateConfig(
                title: "Thanks for using ByeTunes",
                message: "We had a good run. Hope you guys enjoyed it.",
                icon: "heart.fill", color: "pink",
                showBanner: true, blockDownloads: true, dismissible: false, etaLabel: "Back around"
            )
        }
    }

    static func resolve(_ file: ServerStatusFile, now: Date = Date()) -> ResolvedServerStatus {
        let rawStatus = file.status.trimmingCharacters(in: .whitespaces).lowercased()
        let requested = rawStatus == "online" ? ServerState.active : (ServerState(rawValue: rawStatus) ?? .active)
        guard requested != .active else { return ResolvedServerStatus() }

        if let startsAt = parseDate(file.startsAt), now < startsAt { return ResolvedServerStatus() }
        if let expiresAt = parseDate(file.expiresAt), now >= expiresAt { return ResolvedServerStatus() }

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if let minVersion = file.minVersion, compareVersions(appVersion, minVersion) == .orderedAscending { return ResolvedServerStatus() }
        if let maxVersion = file.maxVersion, compareVersions(appVersion, maxVersion) == .orderedDescending { return ResolvedServerStatus() }

        var config = builtInDefaults(for: requested)
        if let perState = file.states?[requested.rawValue] {
            config = perState.overlaid(on: config)
        }
        config = file.overrides.overlaid(on: config)

        var result = ResolvedServerStatus()
        result.state = requested
        result.title = config.title ?? ""
        result.message = config.message ?? ""
        result.icon = (config.icon?.isEmpty == false) ? config.icon! : "info.circle.fill"
        result.colorName = config.color ?? "orange"
        result.showBanner = config.showBanner ?? (requested != .active)
        result.blockDownloads = config.blockDownloads ?? (requested == .dead)
        result.blockMessage = config.blockMessage
        result.dismissible = config.dismissible ?? false
        result.buttonTitle = config.buttonTitle
        result.buttonURL = config.buttonURL.flatMap { URL(string: $0) }
        result.eta = parseDate(config.eta)
        result.etaLabel = config.etaLabel ?? "Back around"
        result.bannerID = [requested.rawValue, result.title, result.message, file.updatedAt ?? ""].joined(separator: "|")
        return result
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default:
            if let uiColor = UIColor(hex: name) { return Color(uiColor) }
            return .orange
        }
    }
}
