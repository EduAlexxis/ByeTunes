import UIKit
import CoreMedia
import CoreVideo

@MainActor
final class PictureInPictureRenderer {
    private var width = 640
    private var height = 300

    private var displayedProgress: [String: Double] = [:]
    private var lastItems: [String: PictureInPictureItem] = [:]
    private var completions: [(item: PictureInPictureItem, slot: Int, start: CFTimeInterval)] = []
    private var lastSlots: [String: Int] = [:]
    private var artwork: [URL: UIImage] = [:]
    private var loadingArtwork: Set<URL> = []

    static let headerHeight: CGFloat = 48
    static let compactTop: CGFloat = 10
    static let activeRowHeight: CGFloat = 84
    static let queuedRowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8

    static func canvasSize(style: PictureInPictureStyle, maxActive: Int) -> CGSize {
        let top = style.showCounter ? headerHeight : compactTop
        let active = CGFloat(max(maxActive, 1)) * (activeRowHeight + rowSpacing)
        let queued = CGFloat(style.nextUpCount) * (queuedRowHeight + rowSpacing)
        return CGSize(width: 640, height: max(top + active + queued + 6, 120))
    }

    func configure(size: CGSize) {
        width = Int(size.width)
        height = Int(size.height)
    }

    func previewImage(style: PictureInPictureStyle, time: TimeInterval) -> UIImage? {
        configure(size: Self.canvasSize(style: style, maxActive: 2))
        let now = CACurrentMediaTime()
        let snapshot = Self.demoSnapshot(time: time)
        update(with: snapshot, now: now, animated: true)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        draw(snapshot: snapshot, style: style, in: context, now: now)
        UIGraphicsPopContext()

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func demoSnapshot(time: TimeInterval) -> PictureInPictureSnapshot {
        func item(_ id: String, _ title: String, _ artist: String, _ progress: Double, _ speed: Double) -> PictureInPictureItem {
            PictureInPictureItem(id: id, title: title, artist: artist, progress: progress, speedBps: speed, artworkURL: nil)
        }
        let first = (time / 10).truncatingRemainder(dividingBy: 1)
        let secondPhase = (time / 12).truncatingRemainder(dividingBy: 1)
        let second = secondPhase < 0.25 ? 0 : (secondPhase - 0.25) / 0.75
        return PictureInPictureSnapshot(
            doneCount: 3,
            totalCount: 12,
            overallProgress: 0.3,
            speedBps: 1_400_000,
            activeItems: [
                {
                    var current = item("a", "ByeTunes", "EduAlexxis", max(first, 0.01), 1_480_000)
                    if first > 0.85 {
                        current = PictureInPictureItem(id: "a", title: "ByeTunes", artist: "EduAlexxis", progress: 1, speedBps: 0, artworkURL: nil, isFetchingMetadata: true)
                    }
                    return current
                }(),
                item("b", "Wow, I'm a Song", "Some Bytes", second, second > 0 ? 1_120_000 : 0)
            ],
            upNext: [
                item("c", "Please Don't Skip Me", "The Lonely Playlist", 0, 0),
                item("d", "Definitely Not a Rickroll", "Totally Legit Band", 0, 0),
                item("e", "Plot Twist: Still Downloading", "Mr. Progress Bar", 0, 0)
            ],
            pendingCount: 6,
            states: [:]
        )
    }

    func reset() {
        displayedProgress = [:]
        lastItems = [:]
        completions = []
        lastSlots = [:]
    }

    func makeFrame(snapshot: PictureInPictureSnapshot, style: PictureInPictureStyle, timebase: CMTimebase?, animated: Bool = true) -> CMSampleBuffer? {
        let now = CACurrentMediaTime()
        update(with: snapshot, now: now, animated: animated)

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        draw(snapshot: snapshot, style: style, in: context, now: now)
        UIGraphicsPopContext()

        return Self.sampleBuffer(from: pixelBuffer, timebase: timebase)
    }

    private func update(with snapshot: PictureInPictureSnapshot, now: CFTimeInterval, animated: Bool) {
        var currentSlots: [String: Int] = [:]
        for (slot, item) in snapshot.activeItems.enumerated() {
            currentSlots[item.id] = slot
            let target = item.progress
            let current = displayedProgress[item.id] ?? 0
            displayedProgress[item.id] = animated ? current + (target - current) * 0.2 : target
            lastItems[item.id] = item
            if let url = item.artworkURL { loadArtworkIfNeeded(url) }
        }
        for item in snapshot.upNext.prefix(3) {
            if let url = item.artworkURL { loadArtworkIfNeeded(url) }
        }

        for (id, slot) in lastSlots where currentSlots[id] == nil {
            if snapshot.states[id] == .done, let item = lastItems[id] {
                completions.append((item, slot, now))
            }
            displayedProgress[id] = nil
        }
        lastSlots = currentSlots
        completions.removeAll { now - $0.start > 1.8 }
    }

    private func loadArtworkIfNeeded(_ url: URL) {
        guard artwork[url] == nil, !loadingArtwork.contains(url) else { return }
        loadingArtwork.insert(url)
        Task { [weak self] in
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                self?.artwork[url] = image
            }
            self?.loadingArtwork.remove(url)
        }
    }

    private typealias Palette = PictureInPicturePalette

    private func currentTraits() -> UITraitCollection {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        return window?.traitCollection ?? UITraitCollection.current
    }

    private func draw(snapshot: PictureInPictureSnapshot, style: PictureInPictureStyle, in context: CGContext, now: CFTimeInterval) {
        let palette = style.palette(traits: currentTraits())
        let backgroundImage = style.useBackgroundImage ? PictureInPictureBackgroundStore.image(version: style.backgroundImageVersion) : nil
        drawBackground(context, palette: palette, image: backgroundImage, dim: style.backgroundDim)

        var cursor = Self.compactTop
        if style.showCounter {
            let headerLabel = backgroundImage == nil ? palette.label : UIColor.white
            let headerSecondary = backgroundImage == nil ? palette.secondary : UIColor(white: 1, alpha: 0.78)
            drawHeader(snapshot, context, palette: palette, label: headerLabel, secondary: headerSecondary)
            cursor = Self.headerHeight
        }

        let slotCount = max(snapshot.activeItems.count, (completions.map(\.slot).max() ?? -1) + 1)
        if slotCount == 0 {
            drawWaitingRow(context, y: cursor, palette: palette)
            cursor += Self.activeRowHeight + Self.rowSpacing
        } else {
            for slot in 0..<slotCount {
                if let completion = completions.first(where: { $0.slot == slot }) {
                    drawCompletedRow(completion.item, context, y: cursor, age: now - completion.start, style: style, palette: palette)
                } else if slot < snapshot.activeItems.count {
                    drawActiveRow(snapshot.activeItems[slot], context, y: cursor, now: now, style: style, palette: palette)
                }
                cursor += Self.activeRowHeight + Self.rowSpacing
            }
        }

        for item in snapshot.upNext.prefix(style.nextUpCount) {
            drawQueuedRow(item, context, y: cursor, style: style, palette: palette)
            cursor += Self.queuedRowHeight + Self.rowSpacing
        }
    }

    private func drawBackground(_ context: CGContext, palette: Palette, image: UIImage?, dim: Double) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(palette.background.cgColor)
        context.fill(bounds)

        if let image {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawRect = CGRect(x: (bounds.width - drawSize.width) / 2, y: (bounds.height - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
            context.saveGState()
            context.clip(to: bounds)
            image.draw(in: drawRect)
            context.restoreGState()
            context.setFillColor(UIColor.black.withAlphaComponent(CGFloat(dim)).cgColor)
            context.fill(bounds)
            return
        }

        if let end = palette.backgroundEnd,
           let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [palette.background.cgColor, end.cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: CGFloat(height)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private func drawHeader(_ snapshot: PictureInPictureSnapshot, _ context: CGContext, palette: Palette, label: UIColor, secondary: UIColor) {
        if let icon = UIImage(systemName: "arrow.down.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))?.withTintColor(palette.accent, renderingMode: .alwaysOriginal) {
            icon.draw(in: CGRect(x: 26, y: 12, width: 26, height: 26))
        }
        drawText("Downloading", in: CGRect(x: 60, y: 11, width: 320, height: 28), font: .systemFont(ofSize: 21, weight: .bold), color: label)
        drawText("\(snapshot.doneCount) of \(snapshot.totalCount)", in: CGRect(x: 420, y: 13, width: 194, height: 26), font: .monospacedDigitSystemFont(ofSize: 19, weight: .semibold), color: secondary, alignment: .right)
    }

    private func drawActiveRow(_ item: PictureInPictureItem, _ context: CGContext, y: CGFloat, now: CFTimeInterval, style: PictureInPictureStyle, palette: Palette) {
        let card = CGRect(x: 24, y: y, width: 592, height: Self.activeRowHeight)
        fillRoundedRect(context, rect: card, radius: 14, color: palette.card)
        let textInset: CGFloat = style.showArtwork ? 84 : 18
        if style.showArtwork {
            drawArtwork(item, context, rect: CGRect(x: card.minX + 14, y: card.minY + 14, width: 56, height: 56), palette: palette)
        }

        let textX = card.minX + textInset
        let rightReserve: CGFloat = item.isFetchingMetadata ? 220 : 130
        let textWidth = card.width - textInset - rightReserve
        drawText(item.title, in: CGRect(x: textX, y: card.minY + 12, width: textWidth, height: 26), font: .systemFont(ofSize: 21, weight: .semibold), color: palette.label)
        drawText(item.artist, in: CGRect(x: textX, y: card.minY + 38, width: textWidth, height: 20), font: .systemFont(ofSize: 16, weight: .regular), color: palette.secondary)

        let progress = displayedProgress[item.id] ?? 0
        let preparing = item.progress <= 0.001 || item.isFetchingMetadata
        let bar = CGRect(x: textX, y: card.minY + 65, width: card.width - textInset - 16, height: 6)
        drawProgressBar(context, rect: bar, progress: progress, now: now, indeterminate: preparing, palette: palette)

        let rightX = card.maxX - 126
        if item.isFetchingMetadata {
            drawText("Fetching metadata…", in: CGRect(x: card.maxX - 214, y: card.minY + 13, width: 198, height: 22), font: .systemFont(ofSize: 16, weight: .medium), color: palette.secondary, alignment: .right)
        } else if preparing {
            drawText("Preparing…", in: CGRect(x: rightX, y: card.minY + 13, width: 110, height: 22), font: .systemFont(ofSize: 16, weight: .medium), color: palette.secondary, alignment: .right)
        } else {
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            drawText("\(percent)%", in: CGRect(x: rightX, y: card.minY + 11, width: 110, height: 26), font: .monospacedDigitSystemFont(ofSize: 21, weight: .semibold), color: palette.label, alignment: .right)
            if style.showSpeed, item.speedBps > 1 {
                drawText(Self.formatSpeed(item.speedBps), in: CGRect(x: rightX - 10, y: card.minY + 37, width: 120, height: 18), font: .monospacedDigitSystemFont(ofSize: 14, weight: .regular), color: palette.secondary, alignment: .right)
            }
        }
    }

    private func drawCompletedRow(_ item: PictureInPictureItem, _ context: CGContext, y: CGFloat, age: CFTimeInterval, style: PictureInPictureStyle, palette: Palette) {
        let card = CGRect(x: 24, y: y, width: 592, height: Self.activeRowHeight)
        fillRoundedRect(context, rect: card, radius: 14, color: palette.card)
        let textInset: CGFloat = style.showArtwork ? 84 : 18
        if style.showArtwork {
            drawArtwork(item, context, rect: CGRect(x: card.minX + 14, y: card.minY + 14, width: 56, height: 56), palette: palette)
        }

        let t = CGFloat(min(age / 0.35, 1))
        let scale = 0.4 + 0.6 * easeOut(t)
        let badgeSize: CGFloat = 26 * scale
        let badgeCenter = style.showArtwork
            ? CGPoint(x: card.minX + 68, y: card.minY + 68)
            : CGPoint(x: card.maxX - 36, y: card.midY)
        if let check = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular))?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
            context.setFillColor(palette.card.cgColor)
            let ring = badgeSize + 6
            context.fillEllipse(in: CGRect(x: badgeCenter.x - ring / 2, y: badgeCenter.y - ring / 2, width: ring, height: ring))
            check.draw(in: CGRect(x: badgeCenter.x - badgeSize / 2, y: badgeCenter.y - badgeSize / 2, width: badgeSize, height: badgeSize))
        }

        let textX = card.minX + textInset
        let fade = CGFloat(max(0, min(1, (1.8 - age) / 0.4)))
        drawText(item.title, in: CGRect(x: textX, y: card.minY + 12, width: card.width - textInset - 60, height: 26), font: .systemFont(ofSize: 21, weight: .semibold), color: palette.label.withAlphaComponent(fade))
        drawText(item.artist, in: CGRect(x: textX, y: card.minY + 38, width: card.width - textInset - 60, height: 20), font: .systemFont(ofSize: 16, weight: .regular), color: palette.secondary.withAlphaComponent(fade))
        drawText("Saved", in: CGRect(x: textX, y: card.minY + 60, width: 300, height: 20), font: .systemFont(ofSize: 16, weight: .semibold), color: UIColor.systemGreen.withAlphaComponent(fade))
    }

    private func drawWaitingRow(_ context: CGContext, y: CGFloat, palette: Palette) {
        let card = CGRect(x: 24, y: y, width: 592, height: Self.activeRowHeight)
        fillRoundedRect(context, rect: card, radius: 14, color: palette.card)
        if let clock = UIImage(systemName: "clock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular))?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal) {
            clock.draw(in: CGRect(x: card.minX + 22, y: card.midY - 17, width: 34, height: 34))
        }
        drawText("Getting the next song ready", in: CGRect(x: card.minX + 74, y: card.midY - 13, width: 480, height: 26), font: .systemFont(ofSize: 20, weight: .medium), color: palette.secondary)
    }

    private func drawQueuedRow(_ item: PictureInPictureItem, _ context: CGContext, y: CGFloat, style: PictureInPictureStyle, palette: Palette) {
        let card = CGRect(x: 24, y: y, width: 592, height: Self.queuedRowHeight)
        fillRoundedRect(context, rect: card, radius: 12, color: palette.card)
        let textInset: CGFloat = style.showArtwork ? 66 : 16
        if style.showArtwork {
            drawArtwork(item, context, rect: CGRect(x: card.minX + 12, y: card.minY + 8, width: 40, height: 40), palette: palette, radius: 8)
        }
        let textX = card.minX + textInset
        let textWidth = card.width - textInset - 130
        drawText(item.title, in: CGRect(x: textX, y: card.minY + 7, width: textWidth, height: 24), font: .systemFont(ofSize: 19, weight: .semibold), color: palette.label)
        drawText(item.artist, in: CGRect(x: textX, y: card.minY + 31, width: textWidth, height: 20), font: .systemFont(ofSize: 15, weight: .regular), color: palette.secondary)
        drawText("Up Next", in: CGRect(x: card.maxX - 126, y: card.midY - 10, width: 80, height: 20), font: .systemFont(ofSize: 15, weight: .medium), color: palette.secondary, alignment: .right)
        if let clock = UIImage(systemName: "clock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal) {
            clock.draw(in: CGRect(x: card.maxX - 36, y: card.midY - 11, width: 22, height: 22))
        }
    }

    private func drawArtwork(_ item: PictureInPictureItem, _ context: CGContext, rect: CGRect, palette: Palette, radius: CGFloat = 12) {
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        if let url = item.artworkURL, let image = artwork[url] {
            image.draw(in: rect)
        } else {
            context.setFillColor(palette.fill.cgColor)
            context.fill(rect)
            if let note = UIImage(systemName: "music.note", withConfiguration: UIImage.SymbolConfiguration(pointSize: rect.width * 0.4, weight: .regular))?.withTintColor(palette.secondary, renderingMode: .alwaysOriginal) {
                let side = rect.width * 0.4
                note.draw(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            }
        }
        context.restoreGState()
    }

    private func drawProgressBar(_ context: CGContext, rect: CGRect, progress: Double, now: CFTimeInterval, indeterminate: Bool, palette: Palette) {
        fillRoundedRect(context, rect: rect, radius: rect.height / 2, color: palette.fill)

        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        if indeterminate {
            let segment = rect.width * 0.3
            let position = CGFloat((now * 0.7).truncatingRemainder(dividingBy: 1))
            let x = rect.minX - segment + (rect.width + segment) * position
            context.setFillColor(palette.accent.cgColor)
            context.fill(CGRect(x: x, y: rect.minY, width: segment, height: rect.height))
        } else {
            let fraction = CGFloat(min(max(progress, 0), 1))
            context.setFillColor(palette.accent.cgColor)
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height))
        }
        context.restoreGState()
    }

    private func fillRoundedRect(_ context: CGContext, rect: CGRect, radius: CGFloat, color: UIColor) {
        context.setFillColor(color.cgColor)
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        context.fillPath()
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_048_576
        if megabytes >= 1 { return String(format: "%.1f MB/s", megabytes) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
    }

    private static func sampleBuffer(from pixelBuffer: CVPixelBuffer, timebase: CMTimebase?) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        let time = timebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }
}
