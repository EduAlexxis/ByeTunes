import SwiftUI
import Combine
import UIKit
import CryptoKit
import AVFoundation
import CommonCrypto
import SafariServices

extension DownloadViewModel {
    func processQueueIfNeeded() async {
        if backgroundDownloadsEnabled && !isAppActive && !PictureInPictureKeepAlive.shared.isPictureInPictureActive {
            startBackgroundQueueIfNeeded()
            return
        }
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
                let isBackgroundHandoff = pendingBackgroundHandoffTrackIDs.remove(track.id) != nil
                log(isBackgroundHandoff ? "Download cancelled for background handoff." : "Download cancelled/paused by user.")
                metadataFetchingTrackIDs.remove(track.id)
                trackStates[track.id] = isPaused ? .queued : .idle
                if isPaused || isBackgroundHandoff {
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

    func startBackgroundQueueIfNeeded() {
        guard backgroundDownloadsEnabled else { return }
        guard !isAppActive else { return }
        guard !isPaused else { return }
        guard !pendingQueue.isEmpty else { return }
        guard canAdvanceBackgroundQueueNow else {
            log("Background queue has pending tracks, but next track will wait until the app is active again.")
            syncQueuePersistence()
            return
        }

        while activeDownloadTrackIDs.count < maxConcurrentDownloads, !pendingQueue.isEmpty {
            let track = pendingQueue.removeFirst()
            log("Starting background-native queue step for \(track.id) (\(track.name)) remaining=\(pendingQueue.count) active=\(activeDownloadTrackIDs.count + 1)/\(maxConcurrentDownloads)")
            errorText = nil
            activeDownloadTrackIDs.insert(track.id)
            trackStates[track.id] = .downloading
            downloadProgressByTrackID[track.id] = 0
            downloadSpeedByTrackID[track.id] = 0
            syncQueuePersistence()
            primeBackgroundPreparation()

            let spacing: Duration = isLosslessDownloadFormat ? .milliseconds(900) : .milliseconds(300)
            Task { [weak self] in
                await self?.downloadStartPacer.waitForNextSlot(minSpacing: spacing)
                await self?.processBackgroundQueuedTrack(track)
            }
        }
    }

    func processBackgroundQueuedTrack(_ track: DownloadTrack) async {
        let taskState = DownloadBackgroundTaskState()
        taskState.id = UIApplication.shared.beginBackgroundTask(withName: "DownloadTrack-\(track.id)") {
            guard taskState.id != .invalid else { return }
            Logger.shared.log("[Download] Background task expired for \(track.id) while queue was active")
            UIApplication.shared.endBackgroundTask(taskState.id)
            taskState.id = .invalid
        }
        defer {
            if taskState.id != .invalid {
                UIApplication.shared.endBackgroundTask(taskState.id)
                taskState.id = .invalid
            }
        }
        if isPaused, pausedBackgroundTrackIDs.remove(track.id) != nil {
            handleBackgroundTrackStopped(track)
            return
        }
        do {
            let outcome: BackendDownloadOutcome
            if let plan = await consumePreparedBackgroundPlan(for: track) {
                log("Using prepared background plan for \(track.id) with \(plan.candidates.count) candidate(s).")
                do {
                    if let preparedOutcome = try await executeCandidatesUntilSuccess(
                        plan.candidates,
                        trackID: track.id,
                        suggestedName: plan.suggestedName,
                        fallbackExtension: plan.fallbackExtension
                    ) {
                        outcome = preparedOutcome
                    } else {
                        outcome = try await downloadWithFallbacks(track: track)
                    }
                } catch {
                    log("Prepared background plan failed for \(track.id): \(error.localizedDescription). Falling back to full resolution.")
                    outcome = try await downloadWithFallbacks(track: track)
                }
            } else {
                outcome = try await downloadWithFallbacks(track: track)
            }
            log("Background-native queue finished via \(outcome.backendLabel): \(outcome.fileURL.lastPathComponent)")
            try await finalizeDownloadedTrack(fileURL: outcome.fileURL, track: track, backendLabel: outcome.backendLabel)
        } catch {
            let pausedByUser = pausedBackgroundTrackIDs.remove(track.id) != nil
            let cancelledByUser = cancelledBackgroundTrackIDs.remove(track.id) != nil
            if Task.isCancelled || pausedByUser || cancelledByUser {
                handleBackgroundTrackStopped(track)
                return
            }

            let message = downloadFailureMessage(for: track, error: error)
            log("Background-native queue failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
        }

        completedQueueCount += 1
        clearActiveBackgroundTrack(track.id)
        syncQueuePersistence()
        continueBackgroundQueueIfAllowed()
    }

    func handleBackgroundTrackStopped(_ track: DownloadTrack) {
        log("Background-native queue cancelled/paused by user.")
        trackStates[track.id] = isPaused ? .queued : .idle
        if isPaused {
            pendingQueue.insert(track, at: 0)
        }
        clearActiveBackgroundTrack(track.id)
        syncQueuePersistence()
    }

    func clearActiveBackgroundTrack(_ trackID: String) {
        activeDownloadTrackIDs.remove(trackID)
        downloadProgressByTrackID[trackID] = nil
        downloadSpeedByTrackID[trackID] = nil
    }

    func primeBackgroundPreparation() {
        guard backgroundDownloadsEnabled else { return }
        for track in pendingQueue.prefix(3) {
            scheduleBackgroundPreparationIfNeeded(for: track)
        }
    }

    func continueBackgroundQueueIfAllowed() {
        guard backgroundDownloadsEnabled else { return }
        guard !pendingQueue.isEmpty else { return }
        guard !isPaused else { return }

        if isAppActive {
            Task { await processQueueIfNeeded() }
        } else if canAdvanceBackgroundQueueNow {
            primeBackgroundPreparation()
            startBackgroundQueueIfNeeded()
        } else {
            log("Current background transfer finished. Remaining queued tracks will resume when the app becomes active.")
            syncQueuePersistence()
        }
    }

    func appDidBecomeActive() {
        isAppActive = true
        Task { await processQueueIfNeeded() }
    }

    func appDidEnterBackground() {
        isAppActive = false
        guard backgroundDownloadsEnabled else { return }
        if PictureInPictureKeepAlive.shared.isEngaged {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if !isAppActive && !PictureInPictureKeepAlive.shared.isPictureInPictureActive {
                    log("Picture in Picture did not start; falling back to background transfer.")
                    performBackgroundHandoff()
                } else if !isAppActive {
                    log("Picture in Picture is active; downloads keep running in the app.")
                }
            }
            return
        }
        performBackgroundHandoff()
    }

    func pictureInPictureStopped() {
        guard !isAppActive, backgroundDownloadsEnabled, hasPendingOrActiveDownloads, !isPaused else { return }
        log("Picture in Picture closed while in the background; falling back to background transfer.")
        PictureInPictureKeepAlive.shared.disengage()
        performBackgroundHandoff()
    }

    func performBackgroundHandoff() {
        guard backgroundDownloadsEnabled else { return }
        guard !foregroundWorkerTasks.isEmpty else {
            startBackgroundQueueIfNeeded()
            return
        }

        log("App entered background with \(foregroundWorkerTasks.count) foreground download(s) in flight — handing off to background transfer.")
        for (trackID, task) in foregroundWorkerTasks {
            pendingBackgroundHandoffTrackIDs.insert(trackID)
            task.cancel()
        }
    }

    func scheduleBackgroundPreparationIfNeeded(for track: DownloadTrack) {
        guard backgroundDownloadsEnabled else { return }
        guard preparedBackgroundPlansByTrackID[track.id] == nil else { return }
        guard backgroundPreparationTasks[track.id] == nil else { return }

        backgroundPreparationTasks[track.id] = Task { [weak self] in
            guard let self else { return nil }
            return await self.prepareBackgroundDownloadPlan(for: track)
        }
    }

    func consumePreparedBackgroundPlan(for track: DownloadTrack) async -> PreparedBackgroundDownloadPlan? {
        if let plan = preparedBackgroundPlansByTrackID.removeValue(forKey: track.id) {
            backgroundPreparationTasks[track.id] = nil
            return plan
        }

        if let task = backgroundPreparationTasks.removeValue(forKey: track.id) {
            let plan = await task.value
            return plan
        }

        return nil
    }

    func prepareBackgroundDownloadPlan(for track: DownloadTrack) async -> PreparedBackgroundDownloadPlan? {
        let suggestedName = "\(track.artistLine) - \(track.name)"
        let fallbackExtension = "flac"

        do {
            let resolvedSource = await resolvedPrimaryDownloadSource(for: track)
            let candidates = try await primaryCandidates(for: resolvedSource, track: track)
            guard !candidates.isEmpty else {
                log("Background preparation produced no candidates for \(track.id).")
                return nil
            }
            log("Prepared background plan for \(track.id) with \(candidates.count) candidate(s).")
            let plan = PreparedBackgroundDownloadPlan(
                candidates: candidates,
                suggestedName: suggestedName,
                fallbackExtension: fallbackExtension
            )
            preparedBackgroundPlansByTrackID[track.id] = plan
            return plan
        } catch {
            log("Background preparation failed for \(track.id): \(error.localizedDescription)")
            return nil
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
            cancelledBackgroundTrackIDs.remove(track.id)
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
            if backgroundDownloadsEnabled && !isAppActive {
                primeBackgroundPreparation()
            }
            Task { await processQueueIfNeeded() }
            if isAppActive {
                ContinuedDownloadTask.shared.startIfNeeded(for: self)
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
        if backgroundDownloadsEnabled && cancelledBackgroundTrackIDs.remove(track.id) != nil {
            trackStates[track.id] = .idle
            log("Ignoring completed background transfer for cancelled track \(track.name) [\(track.id)]")
            return
        }

        if backgroundDownloadsEnabled && hasHandedOffDownloadedFile(trackID: track.id) {
            trackStates[track.id] = .done
            log("Skipping duplicate background handoff for \(track.name) [\(track.id)]")
            return
        }

        var song = try await SongMetadata.fromURL(fileURL)
        if backgroundDownloadsEnabled && !PictureInPictureKeepAlive.shared.isEngaged {
            trackStates[track.id] = .done
            handOffDownloadedFileForMainImport(song.localURL, track: track)
            log("Queued downloaded file for main import pipeline: \(song.title) [\(track.id)]")
        } else {
            metadataFetchingTrackIDs.insert(track.id)
            song = await enrichDownloadedSong(song, sourceTrack: track)
            song = persistDownloadedSongIfNeeded(song)
            emittedSongs.append(song)
            metadataFetchingTrackIDs.remove(track.id)
            trackStates[track.id] = .done
            log("Track finished with immediate metadata enrichment: \(song.title) [\(track.id)]")
        }
    }

    func recoverBackgroundDownloadIfNeeded() async {
        guard backgroundDownloadsEnabled else {
            if !restoredActiveTrackIDs.isEmpty {
                log("Background download recovery skipped because background downloads are disabled.")
            }
            restoredActiveTrackIDs = []
            return
        }
        guard !restoredActiveTrackIDs.isEmpty else { return }

        let idsToRecover = restoredActiveTrackIDs
        restoredActiveTrackIDs = []
        for activeID in idsToRecover {
            await recoverSingleBackgroundDownload(activeID: activeID)
        }
    }

    func recoverSingleBackgroundDownload(activeID: String) async {
        guard let track = knownTracksByID[activeID] else { return }

        let attached = await bindRecoveredBackgroundDownload(activeID: activeID, track: track)

        if attached {
            activeDownloadTrackIDs.insert(activeID)
            trackStates[activeID] = .downloading
            downloadProgressByTrackID[activeID] = 0
            downloadSpeedByTrackID[activeID] = 0
            log("Reattached to active background download for \(track.name).")
            syncQueuePersistence()
            return
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if await bindRecoveredBackgroundDownload(activeID: activeID, track: track) {
            activeDownloadTrackIDs.insert(activeID)
            trackStates[activeID] = .downloading
            downloadProgressByTrackID[activeID] = 0
            downloadSpeedByTrackID[activeID] = 0
            log("Reattached to active background download for \(track.name) after retry.")
            syncQueuePersistence()
            return
        }

        if hasHandedOffDownloadedFile(trackID: activeID) {
            log("Recovered active download for \(track.name) was already handed off. Marking complete.")
            trackStates[activeID] = .done
            completedQueueCount = min(completedQueueCount + 1, totalQueueCount)
            syncQueuePersistence()
            continueBackgroundQueueIfAllowed()
            return
        }

        log("Failed to reattach to background download for \(track.name) after retry. Requeueing.")
        pendingQueue.insert(track, at: 0)
        trackStates[activeID] = .queued
        syncQueuePersistence()

        if !isPaused {
            if backgroundDownloadsEnabled {
                continueBackgroundQueueIfAllowed()
            } else {
                Task { await processQueueIfNeeded() }
            }
        }
    }

    func bindRecoveredBackgroundDownload(activeID: String, track: DownloadTrack) async -> Bool {
        await BackgroundAudioDownloadManager.shared.bindToActiveDownload(
            forTrackID: activeID,
            progress: { [weak self] progress, speedBps in
                self?.updateVisibleDownloadProgress(progress, speedBps: speedBps, trackID: activeID)
            },
            completion: { [weak self] result in
                guard let self else { return }
                Task { await self.handleRecoveredBackgroundDownloadResult(result, for: track) }
            }
        )
    }

    func handleRecoveredBackgroundDownloadResult(
        _ result: Result<BackgroundDownloadResult, Error>,
        for track: DownloadTrack
    ) async {
        guard !cancelledBackgroundTrackIDs.contains(track.id) else {
            log("Ignoring recovered background result for \(track.id) — it was removed from the queue.")
            clearActiveBackgroundTrack(track.id)
            cancelledBackgroundTrackIDs.remove(track.id)
            return
        }
        if pausedBackgroundTrackIDs.remove(track.id) != nil, case .failure = result {
            handleBackgroundTrackStopped(track)
            return
        }
        switch result {
        case .success(let backgroundResult):
            do {
                if recoveredBackgroundResultNeedsRetry(backgroundResult) {
                    log("Recovered background transfer for \(track.name) finished on an intermediate response. Requeueing track.")
                    clearActiveBackgroundTrack(track.id)
                    trackStates[track.id] = .queued
                    pendingQueue.insert(track, at: 0)
                    syncQueuePersistence()
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                    return
                }

                try await finalizeDownloadedTrack(
                    fileURL: backgroundResult.fileURL,
                    track: track,
                    backendLabel: backgroundResult.context.backendLabel
                )
                completedQueueCount += 1
                clearActiveBackgroundTrack(track.id)
                log("Recovered background download finished via \(backgroundResult.context.backendLabel): \(backgroundResult.fileURL.lastPathComponent)")
                syncQueuePersistence()
                if !pendingQueue.isEmpty {
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                }
            } catch {
                let message = downloadFailureMessage(for: track, error: error)
                log("Recovered background download failed validation (\(error.localizedDescription)): \(message)")
                errorText = message
                trackFailureReasons[track.id] = message
                trackStates[track.id] = .failed
                completedQueueCount += 1
                clearActiveBackgroundTrack(track.id)
                syncQueuePersistence()
                if !pendingQueue.isEmpty {
                    if backgroundDownloadsEnabled {
                        continueBackgroundQueueIfAllowed()
                    } else {
                        Task { await processQueueIfNeeded() }
                    }
                }
            }
        case .failure(let error):
            let message = downloadFailureMessage(for: track, error: error)
            log("Recovered background download failed (\(error.localizedDescription)): \(message)")
            errorText = message
            trackFailureReasons[track.id] = message
            trackStates[track.id] = .failed
            completedQueueCount += 1
            clearActiveBackgroundTrack(track.id)
            syncQueuePersistence()
            if !pendingQueue.isEmpty {
                if backgroundDownloadsEnabled {
                    continueBackgroundQueueIfAllowed()
                } else {
                    Task { await processQueueIfNeeded() }
                }
            }
        }
    }

    func recoveredBackgroundResultNeedsRetry(_ result: BackgroundDownloadResult) -> Bool {
        let mimeType = (result.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if mimeType.contains("application/json") || mimeType.contains("text/json") {
            return true
        }
        return !downloadedFileLooksLikeAudio(result.fileURL)
    }
}
