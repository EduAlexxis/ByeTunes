import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func togglePreview(for track: DownloadTrack) {
        Task { @MainActor in
            if activePreviewTrackID == track.id {
                stopPreview()
                return
            }

            previewLoadingTrackIDs.insert(track.id)
            defer { previewLoadingTrackIDs.remove(track.id) }

            guard let url = await previewURL(for: track) else {
                errorText = "No preview available for \(track.name)."
                return
            }

            playPreview(for: track.id, url: url)
        }
    }

    func playPreview(for trackID: String, url: URL) {
        stopPreview()

        guard configurePreviewAudioSession() else {
            errorText = "Could not start audio preview."
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 1.0
        previewPlayer = player
        activePreviewTrackID = trackID

        previewStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if item.status == .failed {
                    self.errorText = "Could not play preview for this song."
                    self.log("Preview item failed: \(item.error?.localizedDescription ?? "unknown error")")
                    self.stopPreview()
                }
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopPreview()
            }
        }

        player.play()
    }

    func configurePreviewAudioSession() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()

        let attempts: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playback, .default, []),
            (.playback, .default, [.mixWithOthers]),
            (.ambient, .default, [])
        ]

        for (category, mode, options) in attempts {
            do {
                try audioSession.setCategory(category, mode: mode, options: options)
                try audioSession.setActive(true)
                return true
            } catch {
                log("Preview audio session setup failed for \(category.rawValue): \(error.localizedDescription)")
            }
        }

        return false
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        activePreviewTrackID = nil

        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }

        previewStatusObserver = nil
    }

    func previewURL(for track: DownloadTrack) async -> URL? {
        if let trackPreviewURL = track.previewURL {
            cachedPreviewURLs[track.id] = trackPreviewURL
            return trackPreviewURL
        }

        if let cached = cachedPreviewURLs[track.id] {
            return cached
        }

        let resolved: URL?
        switch track.provider {
        case .appleMusic, .spotify, .metadata, .itunes, .deezer:
            resolved = await resolveITunesPreviewURL(for: track)
        }

        if let resolved {
            cachedPreviewURLs[track.id] = resolved
        }

        return resolved
    }

    func resolveITunesPreviewURL(for track: DownloadTrack) async -> URL? {
        let query = [track.artistLine, track.name]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let results = await SongMetadata.searchiTunes(query: query, limit: 10)
        let match = results.first { song in
            guard
                let title = song.trackName,
                let artist = song.artistName
            else {
                return false
            }

            let normalizedTrackTitle = DownloadSupport.normalizedSearchValue(track.name)
            let normalizedSongTitle = DownloadSupport.normalizedSearchValue(title)
            guard normalizedTrackTitle == normalizedSongTitle else {
                return false
            }

            return matchesArtistLine(track.artistLine, artistName: artist)
        } ?? results.first

        return match?.previewUrl.flatMap(URL.init(string:))
    }
}
