import Foundation
import SQLite3
import CommonCrypto
import UIKit

// MARK: - Color Analysis
extension MediaLibraryBuilder {
    static func colorAnalysisJSON(for song: SongMetadata, version: DatabaseVersion) -> String {
        guard version.supportsIOS264ArtworkDisplay else {
            return fallbackColorAnalysisJSON()
        }

        if let customHex = song.customAlbumBackgroundColor,
           let background = rgbColor(from: customHex) {
            let backgroundLight = relativeLuminance(red: background.r, green: background.g, blue: background.b) > 0.62
            let textLight = !backgroundLight
            let primary = textLight ? mix(background, with: (255, 255, 255), amount: 0.92) : mix(background, with: (0, 0, 0), amount: 0.86)
            let secondary = textLight ? mix(background, with: (255, 255, 255), amount: 0.82) : mix(background, with: (0, 0, 0), amount: 0.72)
            let tertiary = textLight ? mix(background, with: (255, 255, 255), amount: 0.66) : mix(background, with: (0, 0, 0), amount: 0.58)
            return """
            {"ColorAnalysis":{"1":{"primaryTextColorLight":"\(textLight ? "YES" : "NO")","secondaryTextColorLight":"\(textLight ? "YES" : "NO")","secondaryTextColor":"\(hexColor(secondary))","tertiaryTextColorLight":"NO","primaryTextColor":"\(hexColor(primary))","tertiaryTextColor":"\(hexColor(tertiary))","backgroundColorLight":"\(backgroundLight ? "YES" : "NO")","backgroundColor":"\(hexColor(background))"}}}
            """
        }

        if let appleColors = song.appleMusicArtworkColors,
           let background = rgbColor(from: appleColors.backgroundColor) {
            return colorAnalysisJSON(for: appleColors, fallbackBackground: background)
        }

        let background = representativeArtworkColor(from: song.artworkData ?? Data()) ?? (r: 51, g: 51, b: 51)
        let backgroundLight = relativeLuminance(red: background.r, green: background.g, blue: background.b) > 0.62
        let textLight = !backgroundLight

        let primary = textLight ? mix(background, with: (255, 255, 255), amount: 0.92) : mix(background, with: (0, 0, 0), amount: 0.86)
        let secondary = textLight ? mix(background, with: (255, 255, 255), amount: 0.82) : mix(background, with: (0, 0, 0), amount: 0.72)
        let tertiary = textLight ? mix(background, with: (255, 255, 255), amount: 0.66) : mix(background, with: (0, 0, 0), amount: 0.58)

        return """
        {"ColorAnalysis":{"1":{"primaryTextColorLight":"\(textLight ? "YES" : "NO")","secondaryTextColorLight":"\(textLight ? "YES" : "NO")","secondaryTextColor":"\(hexColor(secondary))","tertiaryTextColorLight":"NO","primaryTextColor":"\(hexColor(primary))","tertiaryTextColor":"\(hexColor(tertiary))","backgroundColorLight":"\(backgroundLight ? "YES" : "NO")","backgroundColor":"\(hexColor(background))"}}}
        """
    }

    static func colorAnalysisJSON(for appleColors: AppleMusicArtworkColors) -> String {
        guard let background = rgbColor(from: appleColors.backgroundColor) else {
            return fallbackColorAnalysisJSON()
        }
        return colorAnalysisJSON(for: appleColors, fallbackBackground: background)
    }

    static func fallbackColorAnalysisJSON() -> String {
        return """
        {"ColorAnalysis":{"1":{"primaryTextColorLight":"NO","secondaryTextColorLight":"NO","secondaryTextColor":"#FFFFFF","tertiaryTextColorLight":"NO","primaryTextColor":"#FFFFFF","tertiaryTextColor":"#CCCCCC","backgroundColorLight":"NO","backgroundColor":"#333333"}}}
        """
    }

    static func colorAnalysisJSON(for appleColors: AppleMusicArtworkColors, fallbackBackground background: (r: Int, g: Int, b: Int)) -> String {
        let primary = rgbColor(from: appleColors.primaryTextColor) ?? mix(background, with: (255, 255, 255), amount: 0.92)
        let secondary = rgbColor(from: appleColors.secondaryTextColor) ?? primary
        let tertiary = rgbColor(from: appleColors.tertiaryTextColor) ?? secondary
        let backgroundLight = relativeLuminance(red: background.r, green: background.g, blue: background.b) > 0.62

        return """
        {"ColorAnalysis":{"1":{"primaryTextColorLight":"\(isLight(primary) ? "YES" : "NO")","secondaryTextColorLight":"\(isLight(secondary) ? "YES" : "NO")","secondaryTextColor":"\(hexColor(secondary))","tertiaryTextColorLight":"NO","primaryTextColor":"\(hexColor(primary))","tertiaryTextColor":"\(hexColor(tertiary))","backgroundColorLight":"\(backgroundLight ? "YES" : "NO")","backgroundColor":"\(hexColor(background))"}}}
        """
    }

    static func rgbColor(from hex: String) -> (r: Int, g: Int, b: Int)? {
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }
        return (
            r: (value >> 16) & 0xFF,
            g: (value >> 8) & 0xFF,
            b: value & 0xFF
        )
    }

    static func representativeArtworkColor(from data: Data) -> (r: Int, g: Int, b: Int)? {
        guard let cgImage = UIImage(data: data)?.cgImage else {
            return nil
        }

        let width = 40
        let height = 40
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: (weight: Double, red: Double, green: Double, blue: Double)] = [:]

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let alpha = Int(pixels[offset + 3])

            guard alpha > 200 else {
                continue
            }

            let luminance = relativeLuminance(red: red, green: green, blue: blue)
            guard luminance > 0.06 && luminance < 0.94 else {
                continue
            }

            let saturation = saturation(red: red, green: green, blue: blue)
            let weight = 1.0 + (saturation * 3.0) + (abs(luminance - 0.5) * 0.35)
            let key = ((red / 24) << 16) | ((green / 24) << 8) | (blue / 24)
            let bucket = buckets[key] ?? (weight: 0, red: 0, green: 0, blue: 0)
            buckets[key] = (
                weight: bucket.weight + weight,
                red: bucket.red + Double(red) * weight,
                green: bucket.green + Double(green) * weight,
                blue: bucket.blue + Double(blue) * weight
            )
        }

        guard let best = buckets.max(by: { $0.value.weight < $1.value.weight })?.value, best.weight > 0 else {
            return nil
        }

        let red = Int((best.red / best.weight).rounded())
        let green = Int((best.green / best.weight).rounded())
        let blue = Int((best.blue / best.weight).rounded())
        return displayBackgroundColor(red: red, green: green, blue: blue)
    }

    static func displayBackgroundColor(red: Int, green: Int, blue: Int) -> (r: Int, g: Int, b: Int) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: 1
        ).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let adjustedSaturation = min(max(saturation * 1.15, 0.18), 0.9)
        let adjustedBrightness = min(max(brightness * 0.82, 0.18), 0.62)
        let color = UIColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1)

        var adjustedRed: CGFloat = 0
        var adjustedGreen: CGFloat = 0
        var adjustedBlue: CGFloat = 0
        color.getRed(&adjustedRed, green: &adjustedGreen, blue: &adjustedBlue, alpha: &alpha)

        return (
            r: Int((adjustedRed * 255).rounded()),
            g: Int((adjustedGreen * 255).rounded()),
            b: Int((adjustedBlue * 255).rounded())
        )
    }

    static func mix(_ color: (r: Int, g: Int, b: Int), with other: (Int, Int, Int), amount: Double) -> (r: Int, g: Int, b: Int) {
        let inverse = 1.0 - amount
        return (
            r: Int((Double(color.r) * inverse + Double(other.0) * amount).rounded()),
            g: Int((Double(color.g) * inverse + Double(other.1) * amount).rounded()),
            b: Int((Double(color.b) * inverse + Double(other.2) * amount).rounded())
        )
    }

    static func hexColor(_ color: (r: Int, g: Int, b: Int)) -> String {
        return String(format: "#%02X%02X%02X", clampColor(color.r), clampColor(color.g), clampColor(color.b))
    }

    static func isLight(_ color: (r: Int, g: Int, b: Int)) -> Bool {
        return relativeLuminance(red: color.r, green: color.g, blue: color.b) > 0.62
    }

    static func clampColor(_ value: Int) -> Int {
        return min(max(value, 0), 255)
    }

    static func saturation(red: Int, green: Int, blue: Int) -> Double {
        let maxValue = Double(max(red, green, blue)) / 255.0
        let minValue = Double(min(red, green, blue)) / 255.0
        guard maxValue > 0 else {
            return 0
        }
        return (maxValue - minValue) / maxValue
    }

    static func relativeLuminance(red: Int, green: Int, blue: Int) -> Double {
        return (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255.0
    }
}
