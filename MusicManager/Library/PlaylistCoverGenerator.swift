import UIKit

enum PlaylistCoverGenerator {
    private static let palettes: [[String]] = [
        ["9DF2F2", "7140FF", "3A00B3", "190040"],
        ["9DC8F2", "FF6D40", "0058B3", "001F40"],
        ["9DF29D", "46FF40", "06B300", "004000"],
        ["F2C69D", "FFA140", "B35600", "401600"],
        ["F2B99D", "FF7840", "B33A00", "400900"],
        ["9DEDF2", "40F0FF", "00B399", "400000"],
        ["B5AFCF", "ECFF89", "7758FF", "2A244F"],
        ["2A82D0", "FA0034", "0083F9", "00172D"],
        ["E4F0EE", "C2B3FC", "73FFE8", "001C47"],
        ["F1BCC2", "5DB6FF", "FF475C", "6B1B00"]
    ]

    static func randomCover(side: CGFloat = 1000) -> Data? {
        let palette = (palettes.randomElement() ?? palettes[0]).map { color(hex: $0) }
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            palette[3].setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let spots: [(UIColor, CGPoint, CGFloat)] = [
                (palette[0], jitter(0.2, 0.15), 0.95),
                (palette[1], jitter(0.85, 0.3), 0.75),
                (palette[2], jitter(0.35, 0.95), 0.85)
            ]
            let space = CGColorSpaceCreateDeviceRGB()
            for (color, center, radius) in spots {
                let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { continue }
                let point = CGPoint(x: center.x * side, y: center.y * side)
                cg.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius * side, options: [])
            }
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    private static func jitter(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x + CGFloat.random(in: -0.12...0.12), y: y + CGFloat.random(in: -0.12...0.12))
    }

    private static func color(hex: String) -> UIColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
