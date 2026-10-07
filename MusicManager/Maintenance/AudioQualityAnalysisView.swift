import SwiftUI
import AVFoundation
import AudioToolbox
import CoreMedia

struct AudioQualityAnalysisView: View {
    @ObservedObject var manager: DeviceManager
    let song: DeviceManager.ExportableSongInfo
    var artwork: UIImage? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var codec: String = "—"
    @State private var sampleRate: String = "—"
    @State private var bitDepth: String = "—"
    @State private var bitrate: String = "—"
    @State private var verdict: QualityVerdict?

    private enum VerdictLevel {
        case good, caution, warning

        var iconName: String {
            switch self {
            case .good: return "checkmark.seal.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .warning: return "xmark.seal.fill"
            }
        }

        var tint: Color {
            switch self {
            case .good: return .green
            case .caution: return .orange
            case .warning: return .red
            }
        }
    }

    private struct QualityVerdict {
        let level: VerdictLevel
        let title: String
        let detail: String
    }

    private let tileColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(.systemGray2))
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 12) {
                artworkView
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("\(song.artist) · \(song.album)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 2)

            LazyVGrid(columns: tileColumns, spacing: 12) {
                specTile("Codec", isLoading ? "…" : codec, icon: "waveform")
                specTile("Sample Rate", isLoading ? "…" : sampleRate, icon: "dot.radiowaves.left.and.right")
                specTile("Bit Depth", isLoading ? "…" : bitDepth, icon: "square.stack.3d.up")
                specTile("Bitrate", isLoading ? "…" : bitrate, icon: "gauge.with.dots.needle.67percent")
                specTile("Duration", formattedDuration, icon: "clock")
                specTile("File Size", formattedFileSize, icon: "doc")
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)

            if let verdict {
                verdictBanner(verdict)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            } else {
                Text("Codec, sample rate, and bit depth are read directly from the file on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            }

            Spacer(minLength: 12)
        }
        .presentationDetents([.height(580)])
        .presentationDragIndicator(.visible)
        .task {
            await analyze()
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.systemGray5)
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(Color(.systemGray3))
            }
        }
    }

    private var formattedDuration: String {
        let totalSeconds = max(0, song.durationMs) / 1000
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(song.fileSize), countStyle: .file)
    }

    private func specTile(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func verdictBanner(_ verdict: QualityVerdict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict.level.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(verdict.level.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(verdict.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(verdict.level.tint.opacity(0.12))
        .cornerRadius(14)
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func analyze() async {
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            manager.downloadSongFileForAnalysis(song) { data in
                continuation.resume(returning: data)
            }
        }

        guard let data else {
            isLoading = false
            errorMessage = "Couldn't download this song from your device to analyze it. Check your connection and try again."
            return
        }

        let ext = song.fileExtension.isEmpty ? "m4a" : song.fileExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            try data.write(to: tempURL)
        } catch {
            isLoading = false
            errorMessage = "Couldn't analyze this song's audio data."
            return
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        var resolvedCodec = "Unknown"
        var resolvedSampleRate: Double = 0
        var resolvedBitDepth: Int = 0
        var resolvedBitRate: Int = 0
        var resolvedChannels: Int = 0

        for track in tracks {
            if resolvedBitRate == 0 {
                let estimatedDataRate = Int(((try? await track.load(.estimatedDataRate)) ?? 0).rounded())
                if estimatedDataRate > 0 {
                    resolvedBitRate = estimatedDataRate
                }
            }

            let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
            for desc in formatDescriptions {
                if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    let asbd = asbdPtr.pointee
                    resolvedCodec = Self.codecName(forFormatID: asbd.mFormatID, fileExtension: song.fileExtension)
                    if resolvedSampleRate == 0, asbd.mSampleRate > 0 {
                        resolvedSampleRate = asbd.mSampleRate
                    }
                    if resolvedBitDepth == 0, asbd.mBitsPerChannel > 0 {
                        resolvedBitDepth = Int(asbd.mBitsPerChannel)
                    }
                    if resolvedChannels == 0, asbd.mChannelsPerFrame > 0 {
                        resolvedChannels = Int(asbd.mChannelsPerFrame)
                    }
                }
            }
        }

        if resolvedCodec == "FLAC", resolvedBitDepth == 0, let flacDepth = Self.flacBitDepth(from: data) {
            resolvedBitDepth = flacDepth
        }

        if resolvedBitRate == 0, song.fileSize > 0, song.durationMs > 0 {
            let durationSeconds = Double(song.durationMs) / 1000.0
            resolvedBitRate = Int((Double(song.fileSize) * 8) / durationSeconds)
        }

        codec = resolvedCodec
        sampleRate = resolvedSampleRate > 0 ? String(format: "%.1f kHz", resolvedSampleRate / 1000) : "Unknown"
        bitDepth = resolvedBitDepth > 0 ? "\(resolvedBitDepth)-bit" : "N/A (lossy)"
        bitrate = resolvedBitRate > 0 ? "\(resolvedBitRate / 1000) kbps" : "Unknown"
        verdict = Self.evaluateQuality(
            declaredExtension: song.fileExtension,
            resolvedCodec: resolvedCodec,
            sampleRate: resolvedSampleRate,
            bitDepth: resolvedBitDepth,
            channels: resolvedChannels,
            bitRateBps: resolvedBitRate
        )
        isLoading = false
    }

    private static func evaluateQuality(
        declaredExtension: String,
        resolvedCodec: String,
        sampleRate: Double,
        bitDepth: Int,
        channels: Int,
        bitRateBps: Int
    ) -> QualityVerdict? {
        let ext = declaredExtension.lowercased()

        if ext == "flac", resolvedCodec != "FLAC" {
            return QualityVerdict(
                level: .warning,
                title: "Mislabeled File",
                detail: "This file has a .flac extension, but its actual audio stream is \(resolvedCodec), not FLAC. It was likely renamed rather than genuinely encoded as lossless."
            )
        }

        if ext == "wav" || ext == "aiff" || ext == "aif" {
            if !resolvedCodec.contains("PCM") {
                return QualityVerdict(
                    level: .warning,
                    title: "Mislabeled File",
                    detail: "This file claims to be uncompressed \(ext.uppercased()) audio, but its actual stream is \(resolvedCodec)."
                )
            }
        }

        if resolvedCodec == "FLAC" || resolvedCodec == "ALAC" {
            guard sampleRate > 0, bitDepth > 0, channels > 0, bitRateBps > 0 else { return nil }
            let rawPcmBitRate = sampleRate * Double(bitDepth) * Double(channels)
            let compressionRatio = Double(bitRateBps) / rawPcmBitRate

            if compressionRatio < 0.25 {
                return QualityVerdict(
                    level: .caution,
                    title: "Unusually High Compression",
                    detail: "This \(resolvedCodec) file compresses to only \(Int(compressionRatio * 100))% of its raw PCM size. Genuine lossless recordings rarely compress this far — it may have been upscaled from a lossy source instead of the original recording."
                )
            }

            return QualityVerdict(
                level: .good,
                title: "Looks Genuinely Lossless",
                detail: "The bitrate is consistent with real lossless \(resolvedCodec) encoding for this sample rate and bit depth."
            )
        }

        if resolvedCodec == "AAC" || resolvedCodec == "MP3" || resolvedCodec == "Opus", bitRateBps > 0, bitRateBps < 128_000 {
            return QualityVerdict(
                level: .caution,
                title: "Low Bitrate",
                detail: "At \(bitRateBps / 1000) kbps, this \(resolvedCodec) file is encoded well below typical streaming quality — you may notice compression artifacts."
            )
        }

        return nil
    }

    private static func codecName(forFormatID formatID: AudioFormatID, fileExtension: String) -> String {
        switch formatID {
        case kAudioFormatAppleLossless:
            return "ALAC"
        case kAudioFormatFLAC:
            return "FLAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD:
            return "AAC"
        case kAudioFormatMPEGLayer3:
            return "MP3"
        case kAudioFormatOpus:
            return "Opus"
        case kAudioFormatLinearPCM:
            return fileExtension.lowercased() == "aiff" || fileExtension.lowercased() == "aif" ? "AIFF (PCM)" : "WAV (PCM)"
        default:
            return fileExtension.isEmpty ? "Unknown" : fileExtension.uppercased()
        }
    }

    private static func flacBitDepth(from data: Data) -> Int? {
        let magic = Array("fLaC".utf8)
        guard data.count >= 8 + 18, data.prefix(4).elementsEqual(magic) else { return nil }

        let blockType = data[4] & 0x7F
        guard blockType == 0 else { return nil }

        let streamInfoStart = data.startIndex + 8
        let b10 = UInt32(data[streamInfoStart + 10])
        let b11 = UInt32(data[streamInfoStart + 11])
        let b12 = UInt32(data[streamInfoStart + 12])
        let b13 = UInt32(data[streamInfoStart + 13])
        let packed = (b10 << 24) | (b11 << 16) | (b12 << 8) | b13

        let bitsPerSample = Int((packed >> 4) & 0x1F) + 1
        return bitsPerSample
    }
}
