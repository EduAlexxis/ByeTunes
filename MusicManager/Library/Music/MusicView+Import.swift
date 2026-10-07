import SwiftUI
import UniformTypeIdentifiers

extension MusicView {
    func handleMusicImport(urls: [URL]?) {
        guard let urls, !urls.isEmpty else { return }
        Task {
            await importSongs(urls: urls, stageInputFiles: true, preserveDownloadedFiles: false)
        }
    }

    func importSongs(urls: [URL], stageInputFiles: Bool, preserveDownloadedFiles: Bool) async {
        guard !urls.isEmpty else { return }

        let stagingDirectory = importStagingDirectory
        var stagedURLs: [URL] = []
        var skippedCount = 0
        var shouldExtractArtworkDuringImport = true

        func isSupportedAudio(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ["mp3", "wav", "aiff", "m4a", "flac", "opus"].contains(ext)
        }

        func cleanedFallbackImportName(from url: URL) -> String {
            let raw = url.deletingPathExtension().lastPathComponent
            let patterns = [
                #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[ _-]+"#,
                #"^[0-9A-Fa-f]{8,}(?:-[0-9A-Fa-f]{2,})+[ _-]+"#,
                #"^[0-9]{6,}[ _-]+"#,
                #"^[0-9A-Fa-f]{10,}[ _-]+"#
            ]

            var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var didStrip = true
            while didStrip {
                didStrip = false
                for pattern in patterns {
                    let updated = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                    if updated != cleaned {
                        cleaned = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                        didStrip = true
                    }
                }
            }

            return cleaned.isEmpty ? raw : cleaned
        }

        func persistDownloadedSongIfNeeded(_ song: SongMetadata) -> SongMetadata {
            guard preserveDownloadedFiles, UserDefaults.standard.bool(forKey: "keepDownloadedSongs") else {
                return song
            }

            let directory = SongMetadata.persistentDownloadsDirectory()
            let needsSecurityScope = directory.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope {
                    directory.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[MusicView] Failed to create persistent download folder: \(error)")
                return song
            }

            let ext = song.localURL.pathExtension.isEmpty ? "flac" : song.localURL.pathExtension
            let baseName = "\(song.artist) - \(song.title)"
            let safeBaseName = baseName
                .components(separatedBy: CharacterSet(charactersIn: "/:"))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var destination = directory.appendingPathComponent("\(safeBaseName.isEmpty ? song.localURL.deletingPathExtension().lastPathComponent : safeBaseName).\(ext)")
            var suffix = 1
            while FileManager.default.fileExists(atPath: destination.path) && destination.path != song.localURL.path {
                destination = directory.appendingPathComponent("\(safeBaseName.isEmpty ? song.localURL.deletingPathExtension().lastPathComponent : safeBaseName)-\(suffix).\(ext)")
                suffix += 1
            }

            if destination.path == song.localURL.path {
                return song
            }

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try AudioTagWriter.copyKeptSong(song, to: destination)
                if !stageInputFiles {
                    try? FileManager.default.removeItem(at: song.localURL)
                }
                var updatedSong = song
                updatedSong.localURL = destination
                return updatedSong
            } catch {
                Logger.shared.log("[MusicView] Failed to persist downloaded song \(song.title): \(error)")
                return song
            }
        }

        func stageFile(_ sourceURL: URL) {
            guard isSupportedAudio(sourceURL) else { return }

            if !stageInputFiles {
                stagedURLs.append(sourceURL)
                return
            }

            let safeName = sourceURL.lastPathComponent
            let ext = sourceURL.pathExtension.lowercased()
            let stagedName = "\(UUID().uuidString)_\(safeName)"
            let destURL = stagingDirectory.appendingPathComponent(stagedName)

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                stagedURLs.append(destURL)
            } catch {
                skippedCount += 1
                Task { @MainActor in
                    Logger.shared.log("[MusicView] Copy failed for \(safeName): \(error)")
                }
                let fallbackURL = stagingDirectory.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.deletingPathExtension().lastPathComponent).\(ext)")
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    do {
                        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                        try data.write(to: fallbackURL, options: .atomic)
                        stagedURLs.append(fallbackURL)
                        Task { @MainActor in
                            Logger.shared.log("[MusicView] Data fallback copy succeeded for \(safeName)")
                        }
                    } catch {
                        Task { @MainActor in
                            Logger.shared.log("[MusicView] Data fallback copy failed for \(safeName): \(error)")
                        }
                    }
                }
            }
        }

        func enrichSong(from localURL: URL) async -> SongMetadata {
            let ext = localURL.pathExtension.lowercased()
            var song: SongMetadata

            if let parsed = try? await SongMetadata.fromURL(localURL, includeArtwork: shouldExtractArtworkDuringImport) {
                song = parsed
            } else {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int) ?? 0
                let cleanedName = cleanedFallbackImportName(from: localURL)
                song = SongMetadata(
                    localURL: localURL,
                    title: cleanedName.isEmpty ? localURL.deletingPathExtension().lastPathComponent : cleanedName,
                    artist: "Unknown Artist",
                    album: "Unknown Album",
                    albumArtist: nil,
                    genre: "Unknown Genre",
                    year: Calendar.current.component(.year, from: Date()),
                    durationMs: 0,
                    fileSize: fileSize,
                    remoteFilename: SongMetadata.generateRemoteFilename(withExtension: ext),
                    artworkData: nil,
                    trackNumber: nil,
                    trackCount: nil,
                    discNumber: nil,
                    discCount: nil,
                    lyrics: nil
                )
                Logger.shared.log("[MusicView] Fallback metadata used for \(localURL.lastPathComponent)")
            }

            if !UserDefaults.standard.bool(forKey: "keepLocalMetadataForLocalFiles") {
                song = await SongMetadata.enrichDownloadedSong(song)
            }

            return persistDownloadedSongIfNeeded(song)
        }

        if stageInputFiles {
            do {
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.shared.log("[MusicView] Failed to create staging directory: \(error)")
            }
        }

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let fileURL = enumerator?.nextObject() as? URL {
                    stageFile(fileURL)
                }
            } else {
                let accessGranted = stageInputFiles ? url.startAccessingSecurityScopedResource() : false
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                stageFile(url)
            }
        }

        await MainActor.run {
            self.isImporting = true
            self.totalImportCount = stagedURLs.count
            self.currentImportIndex = 0
            self.importPhaseTitle = preserveDownloadedFiles ? "Importing Downloads" : "Importing Songs"
        }

        let enrichmentConcurrency: Int
        switch stagedURLs.count {
        case 251...:
            enrichmentConcurrency = 1
        case Self.largeBatchThreshold...250:
            enrichmentConcurrency = 2
        default:
            enrichmentConcurrency = 4
        }
        shouldExtractArtworkDuringImport = stagedURLs.count < Self.largeBatchThreshold
        Logger.shared.log("[MusicView] Import preparation completed. Staged \(stagedURLs.count) file(s), skipped \(skippedCount). stageInputFiles=\(stageInputFiles)")
        Logger.shared.log("[MusicView] Using enrichment concurrency: \(enrichmentConcurrency)")
        let importChunkSize = stagedURLs.count > 200 ? 100 : max(stagedURLs.count, 1)
        Logger.shared.log("[MusicView] Using import chunk size: \(importChunkSize)")
        if !shouldExtractArtworkDuringImport {
            Logger.shared.log("[MusicView] Large import detected. Queue will use lightweight artwork previews; full artwork loads during injection.")
        }

        var foundDuplicates: [DuplicateCandidate] = []
        var seenBySignature: [String: SongMetadata] = [:]
        songs.forEach { seenBySignature[duplicateSignature(for: $0)] = $0 }
        var alreadyImportedCount = 0
        var importedSongIDs: [UUID] = []

        for chunkStart in stride(from: 0, to: stagedURLs.count, by: importChunkSize) {
            let chunkEnd = min(chunkStart + importChunkSize, stagedURLs.count)
            let importChunk = Array(stagedURLs[chunkStart..<chunkEnd])
            var acceptedChunk: [SongMetadata] = []

            for batchStart in stride(from: 0, to: importChunk.count, by: enrichmentConcurrency) {
                let batchEnd = min(batchStart + enrichmentConcurrency, importChunk.count)
                let batch = Array(importChunk[batchStart..<batchEnd])

                await withTaskGroup(of: SongMetadata.self) { group in
                    for stagedURL in batch {
                        group.addTask {
                            await enrichSong(from: stagedURL)
                        }
                    }

                    for await song in group {
                        let sig = duplicateSignature(for: song)
                        if let matched = seenBySignature[sig] {
                            foundDuplicates.append(
                                DuplicateCandidate(
                                    incoming: song,
                                    matched: matched,
                                    reason: "Same title, artist, and album"
                                )
                            )
                        } else {
                            acceptedChunk.append(song)
                            seenBySignature[sig] = song
                        }
                        await MainActor.run {
                            self.currentImportIndex += 1
                        }
                    }
                }
            }

            if !acceptedChunk.isEmpty {
                importedSongIDs.append(contentsOf: acceptedChunk.map(\.id))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.15)) {
                        songs.append(contentsOf: acceptedChunk)
                    }
                }
                alreadyImportedCount += acceptedChunk.count
                acceptedChunk.removeAll(keepingCapacity: false)
            }
        }

        if !shouldExtractArtworkDuringImport, !importedSongIDs.isEmpty {
            await MainActor.run {
                self.importPhaseTitle = "Importing Artwork"
                self.currentImportIndex = 0
                self.totalImportCount = importedSongIDs.count
            }

            for (index, songID) in importedSongIDs.enumerated() {
                guard let currentSong = await MainActor.run(body: {
                    songs.first(where: { $0.id == songID })
                }) else {
                    continue
                }

                let previewData = await SongMetadata.extractEmbeddedArtworkThumbnail(from: currentSong.localURL)
                await MainActor.run {
                    if let songIndex = songs.firstIndex(where: { $0.id == songID }) {
                        songs[songIndex].artworkPreviewData = previewData
                    }
                    self.currentImportIndex = index + 1
                }
            }
        }

        await MainActor.run {
            if foundDuplicates.isEmpty {
                let totalSkipped = skippedCount
                let title: String
                if totalSkipped > 0 {
                    title = "Imported \(alreadyImportedCount), Skipped \(totalSkipped)"
                } else {
                    title = alreadyImportedCount == 1 ? "Imported 1 Song" : "Imported \(alreadyImportedCount) Songs"
                }
                showToast(title: title, icon: "checkmark.circle.fill")
            } else {
                pendingImportedSongs = foundDuplicates.map(\.incoming)
                pendingAlreadyImportedCount = alreadyImportedCount
                pendingImportSkippedCount = skippedCount
                detectedDuplicates = foundDuplicates
                duplicateImportSelection = Dictionary(
                    uniqueKeysWithValues: foundDuplicates.map { ($0.incoming.id, true) }
                )
                showingDuplicateSheet = true
            }

            self.isImporting = false
            self.importPhaseTitle = "Importing Songs"
        }
    }
}
