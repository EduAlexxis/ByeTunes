import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func processQueueIfNeeded() async {
        guard !isPaused else { return }

        while activeDownloadTrackIDs.count < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            log("Dequeued track \(track.id) (\(track.name)) remaining=\(pendingQueue.count) active=\(activeDownloadTrackIDs.count + 1)/\(maxConcurrentDownloads)")
            startForegroundWorker(for: track)
        }
    }

    func startForegroundWorker(for track: DownloadTrack) {
        errorText = nil
        activeDownloadTrackIDs.insert(track.id)
        trackStates[track.id] = .downloading
        downloadProgressByTrackID[track.id] = 0
        downloadSpeedByTrackID[track.id] = 0
        beginBackgroundTaskIfNeeded()
        syncQueuePersistence()

        let spacing: Duration = isLosslessDownloadFormat ? .milliseconds(900) : .milliseconds(300)
        foregroundWorkerTasks[track.id] = Task { [weak self] in
            await self?.downloadStartPacer.waitForNextSlot(minSpacing: spacing)
            await self?.runForegroundWorker(track)
        }
    }

    func runForegroundWorker(_ track: DownloadTrack) async {
        do {
            let outcome = try await downloadWithFallbacks(track: track)
            log("Download finished via \(outcome.backendLabel): \(outcome.fileURL.lastPathComponent)")
            try await finalizeDownloadedTrack(fileURL: outcome.fileURL, track: track, backendLabel: outcome.backendLabel)
        } catch {
            if Task.isCancelled {
                log("Download cancelled/paused by user.")
                metadataFetchingTrackIDs.remove(track.id)
                trackStates[track.id] = isPaused ? .queued : .idle
                if isPaused {
                    pendingQueue.insert(track, at: 0)
                }
                finishForegroundWorker(for: track.id, incrementCompleted: false)
                return
            }
            let message = downloadFailureMessage(for: track, error: error)
            log("Download failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
            finishForegroundWorker(for: track.id, incrementCompleted: true)
            return
        }

        finishForegroundWorker(for: track.id, incrementCompleted: true)
    }

    func finishForegroundWorker(for trackID: String, incrementCompleted: Bool) {
        foregroundWorkerTasks[trackID] = nil
        activeDownloadTrackIDs.remove(trackID)
        downloadProgressByTrackID[trackID] = nil
        downloadSpeedByTrackID[trackID] = nil
        if incrementCompleted {
            completedQueueCount += 1
        }
        if activeDownloadTrackIDs.isEmpty && pendingQueue.isEmpty {
            endBackgroundTaskIfNeeded()
        }
        syncQueuePersistence()
        if !isPaused {
            Task { await processQueueIfNeeded() }
        }
    }

    func appDidBecomeActive() {
        isAppActive = true
        Task { await processQueueIfNeeded() }
    }

    func appDidEnterBackground() {
        isAppActive = false
        guard PictureInPictureKeepAlive.shared.isEngaged else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !isAppActive && !PictureInPictureKeepAlive.shared.isPictureInPictureActive {
                log("Picture in Picture is not showing; downloads pause when iOS suspends the app.")
            }
        }
    }

    @discardableResult
    func enqueueMany(_ tracks: [DownloadTrack]) -> Int {
        let validTracks = tracks.filter { canEnqueue(trackID: $0.id) }
        guard !validTracks.isEmpty else { return 0 }

        if totalQueueCount == completedQueueCount && activeDownloadTrackIDs.isEmpty && pendingQueue.isEmpty {
            totalQueueCount = 0
            completedQueueCount = 0
        }

        for track in validTracks {
            knownTracksByID[track.id] = track
            if !queueOrder.contains(track.id) {
                queueOrder.append(track.id)
            }
            pendingQueue.append(track)
            trackStates[track.id] = .queued
            totalQueueCount += 1
        }

        syncQueuePersistence()
        if !isPaused {
            Task { await processQueueIfNeeded() }
            if isAppActive {
                PictureInPictureKeepAlive.shared.engage(for: self)
            }
        }
        return validTracks.count
    }

    func enrichDownloadedSong(_ initialSong: SongMetadata, sourceTrack: DownloadTrack) async -> SongMetadata {
        await SongMetadata.enrichDownloadedSong(initialSong, sourceTrack: sourceTrack)
    }

    func downloadedFileLooksLikeAudio(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 32)) ?? Data()
        guard !header.isEmpty else { return false }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "opus":
            guard header.count >= 36 else { return false }
            return String(data: header.prefix(4), encoding: .ascii) == "OggS" &&
                String(data: header[28..<36], encoding: .ascii) == "OpusHead"
        case "flac":
            return header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "fLaC"
        case "mp3":
            if header.count >= 3 && String(data: header.prefix(3), encoding: .ascii) == "ID3" {
                return true
            }
            guard header.count >= 2 else { return false }
            return header[0] == 0xFF && (header[1] & 0xE0) == 0xE0
        case "m4a", "mp4", "aac", "alac":
            guard header.count >= 12 else { return false }
            return String(data: header[4..<8], encoding: .ascii) == "ftyp"
        case "wav", "wave":
            guard header.count >= 12 else { return false }
            return String(data: header.prefix(4), encoding: .ascii) == "RIFF" &&
                String(data: header[8..<12], encoding: .ascii) == "WAVE"
        default:
            if header.count >= 4 && String(data: header.prefix(4), encoding: .ascii) == "fLaC" {
                return true
            }
            if header.count >= 3 && String(data: header.prefix(3), encoding: .ascii) == "ID3" {
                return true
            }
            if header.count >= 12 &&
                String(data: header[4..<8], encoding: .ascii) == "ftyp" {
                return true
            }
            if header.count >= 12 &&
                String(data: header.prefix(4), encoding: .ascii) == "RIFF" &&
                String(data: header[8..<12], encoding: .ascii) == "WAVE" {
                return true
            }
            if header.count >= 36 &&
                String(data: header.prefix(4), encoding: .ascii) == "OggS" &&
                String(data: header[28..<36], encoding: .ascii) == "OpusHead" {
                return true
            }
            if header.count >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0 {
                return true
            }
            return false
        }
    }

    func beginBackgroundTaskIfNeeded() {
        guard backgroundDownloadsEnabled else { return }
        guard backgroundTaskID == .invalid else { return }
        let taskState = DownloadBackgroundTaskState()
        taskState.id = UIApplication.shared.beginBackgroundTask(withName: "DownloadQueue") {
            guard taskState.id != .invalid else { return }
            Logger.shared.log("[Download] Background task expired while queue was active")
            let expiredID = taskState.id
            UIApplication.shared.endBackgroundTask(expiredID)
            taskState.id = .invalid
            Task { @MainActor [weak self] in
                self?.clearBackgroundTaskID(expiredID)
            }
        }
        backgroundTaskID = taskState.id
    }

    func clearBackgroundTaskID(_ id: UIBackgroundTaskIdentifier) {
        if backgroundTaskID == id {
            backgroundTaskID = .invalid
        }
    }

    func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func finalizeDownloadedTrack(
        fileURL: URL,
        track: DownloadTrack,
        backendLabel: String
    ) async throws {
        log("Finalizing \(track.id) via \(backendLabel) from \(fileURL.lastPathComponent)")
        var song = try await SongMetadata.fromURL(fileURL)
        metadataFetchingTrackIDs.insert(track.id)
        song = await enrichDownloadedSong(song, sourceTrack: track)
        song = persistDownloadedSongIfNeeded(song)
        emittedSongs.append(song)
        metadataFetchingTrackIDs.remove(track.id)
        trackStates[track.id] = .done
        log("Track finished with metadata enrichment: \(song.title) [\(track.id)]")
    }
}
