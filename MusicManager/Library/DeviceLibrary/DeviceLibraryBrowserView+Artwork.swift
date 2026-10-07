import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Artwork
extension DeviceLibraryBrowserView {
    @ViewBuilder
    func artworkView(for song: DeviceManager.ExportableSongInfo) -> some View {
        if let image = artworkImages[song.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            panelBackground.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(mutedTextColor)
                )
        }
    }

    @ViewBuilder
    func artistArtworkView(_ artist: ArtistEntry) -> some View {
        if let firstSong = artist.songs.first {
            artworkView(for: firstSong)
        }
    }

    @ViewBuilder
    func albumArtworkView(_ album: AlbumEntry) -> some View {
        if let firstSong = album.songs.first {
            artworkView(for: firstSong)
        }
    }

    func loadArtworkIfNeeded(for song: DeviceManager.ExportableSongInfo) {
        guard artworkImages[song.id] == nil else { return }
        guard !artworkLoadingIDs.contains(song.id) else { return }
        guard !queuedArtworkIDs.contains(song.id) else { return }
        guard let relativePath = song.artworkRelativePath, !relativePath.isEmpty else { return }

        queuedArtworkSongs.append(song)
        queuedArtworkIDs.insert(song.id)
        processArtworkQueueIfNeeded()
    }

    func processArtworkQueueIfNeeded() {
        while artworkLoadingIDs.count < maxConcurrentArtworkLoads, !queuedArtworkSongs.isEmpty {
            let song = queuedArtworkSongs.removeFirst()
            queuedArtworkIDs.remove(song.id)

            guard artworkImages[song.id] == nil else { continue }
            guard let relativePath = song.artworkRelativePath, !relativePath.isEmpty else { continue }

            artworkLoadingIDs.insert(song.id)
            let remotePath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
            manager.downloadFileFromDevice(remotePath: remotePath) { data in
                let image = data.flatMap { Self.downsampledArtworkImage(from: $0, maxPixelSize: 120) }
                DispatchQueue.main.async {
                    if let image {
                        artworkImages[song.id] = image
                    }
                    if let data {
                        artworkDataCache[song.id] = data
                    }
                    artworkLoadingIDs.remove(song.id)
                    processArtworkQueueIfNeeded()
                }
            }
        }
    }

    func prefetchArtworkForCurrentMode() {
        let seeds: [DeviceManager.ExportableSongInfo]
        switch libraryMode {
        case .songs:
            seeds = Array(filteredSongs.prefix(18))
        case .artists:
            seeds = cachedArtistEntries.prefix(18).compactMap { $0.songs.first }
        case .albums:
            seeds = cachedAlbumEntries.prefix(18).compactMap { $0.songs.first }
        case .playlists:
            seeds = playlists.prefix(18).compactMap { $0.songs.first }
        }

        for song in seeds {
            loadArtworkIfNeeded(for: song)
        }
    }

    static func downsampledArtworkImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
