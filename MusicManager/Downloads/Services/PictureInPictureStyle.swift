import UIKit

enum PictureInPictureTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case midnight
    case ocean
    case sunset
    case forest
    case rose
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match App"
        case .dark: return "Dark"
        case .midnight: return "Midnight"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .rose: return "Rose"
        case .custom: return "Custom"
        }
    }
}

struct PictureInPicturePalette {
    let background: UIColor
    let backgroundEnd: UIColor?
    let card: UIColor
    let label: UIColor
    let secondary: UIColor
    let fill: UIColor
    let accent: UIColor
}

struct PictureInPictureStyle {
    enum Key {
        static let theme = "pipTheme"
        static let background = "pipCustomBackground"
        static let backgroundEnd = "pipCustomBackgroundEnd"
        static let gradient = "pipCustomGradient"
        static let card = "pipCustomCard"
        static let text = "pipCustomText"
        static let accent = "pipCustomAccent"
        static let nextUpCount = "pipNextUpCount"
        static let showArtwork = "pipShowArtwork"
        static let showSpeed = "pipShowSpeed"
        static let showCounter = "pipShowCounter"
        static let useBackgroundImage = "pipUseBackgroundImage"
        static let backgroundImageVersion = "pipBackgroundImageVersion"
        static let backgroundDim = "pipBackgroundDim"
    }

    enum Default {
        static let background = "#1C1C1E"
        static let backgroundEnd = "#3A2A5C"
        static let card = "#2C2C2E"
        static let text = "#FFFFFF"
        static let accent = "#0A84FF"
    }

    var theme: PictureInPictureTheme = .system
    var customBackground: UIColor = UIColor(hex: Default.background) ?? .black
    var customBackgroundEnd: UIColor = UIColor(hex: Default.backgroundEnd) ?? .black
    var customGradient = false
    var customCard: UIColor = UIColor(hex: Default.card) ?? .darkGray
    var customText: UIColor = UIColor(hex: Default.text) ?? .white
    var customAccent: UIColor = UIColor(hex: Default.accent) ?? .systemBlue
    var nextUpCount = 1
    var showArtwork = true
    var showSpeed = true
    var showCounter = true
    var useBackgroundImage = false
    var backgroundImageVersion = ""
    var backgroundDim = 0.35

    static func current() -> PictureInPictureStyle {
        let defaults = UserDefaults.standard
        var style = PictureInPictureStyle()
        style.theme = PictureInPictureTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        style.customBackground = UIColor(hex: defaults.string(forKey: Key.background) ?? Default.background) ?? style.customBackground
        style.customBackgroundEnd = UIColor(hex: defaults.string(forKey: Key.backgroundEnd) ?? Default.backgroundEnd) ?? style.customBackgroundEnd
        style.customGradient = defaults.bool(forKey: Key.gradient)
        style.customCard = UIColor(hex: defaults.string(forKey: Key.card) ?? Default.card) ?? style.customCard
        style.customText = UIColor(hex: defaults.string(forKey: Key.text) ?? Default.text) ?? style.customText
        style.customAccent = UIColor(hex: defaults.string(forKey: Key.accent) ?? Default.accent) ?? style.customAccent
        style.nextUpCount = min(max(defaults.object(forKey: Key.nextUpCount) as? Int ?? 1, 0), 3)
        style.showArtwork = defaults.object(forKey: Key.showArtwork) as? Bool ?? true
        style.showSpeed = defaults.object(forKey: Key.showSpeed) as? Bool ?? true
        style.showCounter = defaults.object(forKey: Key.showCounter) as? Bool ?? true
        style.useBackgroundImage = defaults.bool(forKey: Key.useBackgroundImage)
        style.backgroundImageVersion = defaults.string(forKey: Key.backgroundImageVersion) ?? ""
        style.backgroundDim = min(max(defaults.object(forKey: Key.backgroundDim) as? Double ?? 0.35, 0), 0.8)
        return style
    }

    func palette(traits: UITraitCollection) -> PictureInPicturePalette {
        switch theme {
        case .system:
            return PictureInPicturePalette(
                background: UIColor.systemGroupedBackground.resolvedColor(with: traits),
                backgroundEnd: nil,
                card: UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits),
                label: UIColor.label.resolvedColor(with: traits),
                secondary: UIColor.secondaryLabel.resolvedColor(with: traits),
                fill: UIColor.systemFill.resolvedColor(with: traits),
                accent: UIColor.systemBlue.resolvedColor(with: traits)
            )
        case .dark:
            return Self.make(background: "#000000", end: nil, card: "#1C1C1E", text: "#FFFFFF", accent: "#0A84FF")
        case .midnight:
            return Self.make(background: "#0B1020", end: "#1A1F3D", card: "#202750", text: "#F2F4FF", accent: "#7C8CFF")
        case .ocean:
            return Self.make(background: "#062B3A", end: "#0B4F6C", card: "#0F5A78", text: "#EAFBFF", accent: "#4FD1C5")
        case .sunset:
            return Self.make(background: "#2B1020", end: "#5B2333", card: "#6B2D3F", text: "#FFF1EC", accent: "#FF8A5B")
        case .forest:
            return Self.make(background: "#0F1F17", end: "#1B3A2A", card: "#25493A", text: "#EFFFF4", accent: "#6BDB8B")
        case .rose:
            return Self.make(background: "#FDE8EE", end: nil, card: "#FFFFFF", text: "#3A1020", accent: "#E91E63")
        case .custom:
            return PictureInPicturePalette(
                background: customBackground,
                backgroundEnd: customGradient ? customBackgroundEnd : nil,
                card: customCard,
                label: customText,
                secondary: customText.withAlphaComponent(0.6),
                fill: customText.withAlphaComponent(0.16),
                accent: customAccent
            )
        }
    }

    private static func make(background: String, end: String?, card: String, text: String, accent: String) -> PictureInPicturePalette {
        let label = UIColor(hex: text) ?? .white
        return PictureInPicturePalette(
            background: UIColor(hex: background) ?? .black,
            backgroundEnd: end.flatMap { UIColor(hex: $0) },
            card: UIColor(hex: card) ?? .darkGray,
            label: label,
            secondary: label.withAlphaComponent(0.6),
            fill: label.withAlphaComponent(0.16),
            accent: UIColor(hex: accent) ?? .systemBlue
        )
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

@MainActor
enum PictureInPictureBackgroundStore {
    private static var cachedVersion: String?
    private static var cachedImage: UIImage?

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PictureInPicture", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("background.jpg")
    }

    static func image(version: String) -> UIImage? {
        if cachedVersion == version, cachedImage != nil || version.isEmpty {
            return cachedImage
        }
        cachedVersion = version
        cachedImage = version.isEmpty ? nil : UIImage(contentsOfFile: fileURL.path)
        return cachedImage
    }

    static func save(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.shared.log("[PiP] Could not save background picture: \(error.localizedDescription)")
            return nil
        }
        let version = UUID().uuidString
        cachedVersion = version
        cachedImage = resized
        return version
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        cachedVersion = ""
        cachedImage = nil
    }
}
