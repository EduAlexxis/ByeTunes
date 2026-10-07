import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

extension DeviceManager {
    func repairIOS26ArtworkColors(progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        guard supportsIOS26ArtworkRepair else {
            completion(false, "This repair is only needed on iOS 26.4 or newer.")
            return
        }

        guard hasValidExpectedPairingFile else {
            completion(false, "Import your RP Pairing File first.")
            return
        }

        let token = beginRepairOperation()
        let startRepair = {
            self.runIOS26ArtworkRepair(token: token, progress: progress, completion: completion)
        }

        if heartbeatReady && hasActiveTransport {
            startRepair()
        } else {
            startHeartbeat { connected in
                if self.isRepairOperationCancelled(token) {
                    completion(false, "Repair cancelled.")
                    return
                }
                guard connected else {
                    completion(false, "Could not connect to the device.")
                    return
                }
                startRepair()
            }
        }
    }

    func repairExperimentalAlbumArtworkPointers(progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        guard hasValidExpectedPairingFile else {
            completion(false, "Import your RP Pairing File first.")
            return
        }

        let token = beginRepairOperation()

        let startRepair = {
            self.runExperimentalAlbumArtworkPointerRepair(token: token, progress: progress, completion: completion)
        }

        if heartbeatReady && hasActiveTransport {
            startRepair()
        } else {
            startHeartbeat { connected in
                if self.isRepairOperationCancelled(token) {
                    completion(false, "Repair cancelled.")
                    return
                }
                guard connected else {
                    completion(false, "Could not connect to the device.")
                    return
                }
                startRepair()
            }
        }
    }

    func runIOS26ArtworkRepair(token: UUID, progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.killMusicBeforeInjectEnabled {
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[ArtworkRepair] Music pre-kill \(killed ? "completed" : "skipped/failed")")
            }

            progress("Downloading MediaLibrary...")

            let semDb = DispatchSemaphore(value: 0)
            var dbData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                dbData = data
                semDb.signal()
            }
            semDb.waitForTransfer()

            guard let dbData, dbData.count > 10000 else {
                completion(false, "MediaLibrary.sqlitedb unavailable.")
                return
            }

            let semWal = DispatchSemaphore(value: 0)
            var walData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.waitForTransfer()

            let semShm = DispatchSemaphore(value: 0)
            var shmData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.waitForTransfer()

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("artwork_repair_\(UUID().uuidString)", isDirectory: true)
            let dbURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")

            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try dbData.write(to: dbURL)
                if let walData {
                    try walData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
                }
                if let shmData {
                    try shmData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
                }
            } catch {
                Logger.shared.log("[ArtworkRepair] Staging failed: \(error)")
                completion(false, "Could not stage the database.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not open the database.")
                return
            }

            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            let candidates = self.ios26ArtworkRepairCandidates(db: db)
            sqlite3_close(db)

            guard !candidates.isEmpty else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "No Apple Music matched artwork found.")
                return
            }

            Logger.shared.log("[ArtworkRepair] Found \(candidates.count) artwork candidates")

            if self.isRepairOperationCancelled(token) {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Repair cancelled.")
                return
            }

            Task { @MainActor in
                var repairs: [(ArtworkRepairCandidate, String)] = []
                var colorCache: [Int64: String] = [:]

                for (index, candidate) in candidates.enumerated() {
                    if self.isRepairOperationCancelled(token) {
                        try? FileManager.default.removeItem(at: tempDir)
                        completion(false, "Repair cancelled.")
                        return
                    }

                    progress("Fetching artwork colors \(index + 1)/\(candidates.count)...")

                    if candidate.storeItemId > 0, let cached = colorCache[candidate.storeItemId] {
                        repairs.append((candidate, cached))
                        continue
                    }

                    let matchedSong: AppleMusicAPI.AppleMusicSong?
                    if candidate.storeItemId > 0 {
                        matchedSong = await AppleMusicAPI.shared.fetchSong(id: String(candidate.storeItemId))
                    } else {
                        matchedSong = await self.bestAppleMusicArtworkFallbackMatch(for: candidate)
                    }

                    guard let song = matchedSong,
                          let colors = song.attributes.artwork?.colors else {
                        if candidate.storeItemId > 0 {
                            Logger.shared.log("[ArtworkRepair] No Apple colors for store_item_id=\(candidate.storeItemId)")
                        } else {
                            Logger.shared.log("[ArtworkRepair] No Apple Music artwork colors available for fallback candidate \(candidate.artist) - \(candidate.title)")
                        }
                        continue
                    }

                    let colorAnalysis = MediaLibraryBuilder.colorAnalysisJSON(for: colors)
                    if let matchedStoreId = Int64(song.id), matchedStoreId > 0 {
                        colorCache[matchedStoreId] = colorAnalysis
                    }
                    repairs.append((candidate, colorAnalysis))
                }

                guard !repairs.isEmpty else {
                    try? FileManager.default.removeItem(at: tempDir)
                    completion(false, "No artwork colors were available from Apple Music.")
                    return
                }

                self.finishIOS26ArtworkRepair(
                    dbURL: dbURL,
                    tempDir: tempDir,
                    repairs: repairs,
                    progress: progress,
                    completion: completion
                )
            }
        }
    }

    func runExperimentalAlbumArtworkPointerRepair(token: UUID, progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.killMusicBeforeInjectEnabled {
                let killed = self.terminateMusicAppIfRunning()
                Logger.shared.log("[AlbumArtworkRepair] Music pre-kill \(killed ? "completed" : "skipped/failed")")
            }

            progress("Downloading MediaLibrary...")

            let semDb = DispatchSemaphore(value: 0)
            var dbData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb") { data in
                dbData = data
                semDb.signal()
            }
            semDb.waitForTransfer()

            guard let dbData, dbData.count > 10000 else {
                completion(false, "MediaLibrary.sqlitedb unavailable.")
                return
            }

            let semWal = DispatchSemaphore(value: 0)
            var walData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal") { data in
                walData = data
                semWal.signal()
            }
            semWal.waitForTransfer()

            let semShm = DispatchSemaphore(value: 0)
            var shmData: Data?
            self.downloadFileFromDevice(remotePath: "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm") { data in
                shmData = data
                semShm.signal()
            }
            semShm.waitForTransfer()

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("album_artwork_repair_\(UUID().uuidString)", isDirectory: true)
            let dbURL = tempDir.appendingPathComponent("MediaLibrary.sqlitedb")

            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try dbData.write(to: dbURL)
                if let walData {
                    try walData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-wal"))
                }
                if let shmData {
                    try shmData.write(to: tempDir.appendingPathComponent("MediaLibrary.sqlitedb-shm"))
                }
            } catch {
                Logger.shared.log("[AlbumArtworkRepair] Staging failed: \(error)")
                completion(false, "Could not stage the database.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not open the database.")
                return
            }

            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            let candidates = self.ios26ArtworkRepairCandidates(db: db)
            sqlite3_close(db)

            guard !candidates.isEmpty else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "No songs were available for experimental metadata refresh.")
                return
            }

            Logger.shared.log("[AlbumArtworkRepair] Found \(candidates.count) song candidates for metadata refresh")

            if self.isRepairOperationCancelled(token) {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Repair cancelled.")
                return
            }

            Task {
                var repairs: [ExperimentalAppleMetadataRepair] = []

                for (index, candidate) in candidates.enumerated() {
                    if self.isRepairOperationCancelled(token) {
                        completion(false, "Repair cancelled.")
                        return
                    }

                    progress("Refreshing Apple metadata \(index + 1)/\(candidates.count)...")

                    let matchedSong: AppleMusicAPI.AppleMusicSong?
                    if candidate.storeItemId > 0 {
                        matchedSong = await AppleMusicAPI.shared.fetchSong(id: String(candidate.storeItemId))
                    } else {
                        matchedSong = await self.bestAppleMusicArtworkFallbackMatch(for: candidate)
                    }

                    guard let matchedSong,
                          let repair = await self.experimentalAppleMetadataRepair(for: candidate, matchedSong: matchedSong) else {
                        continue
                    }

                    repairs.append(repair)
                }

                guard !repairs.isEmpty else {
                    try? FileManager.default.removeItem(at: tempDir)
                    completion(false, "No confident Apple Music metadata matches were found.")
                    return
                }

                let finalizedRepairs = repairs

                await MainActor.run {
                    self.finishExperimentalAlbumArtworkPointerRepair(
                        dbURL: dbURL,
                        tempDir: tempDir,
                        repairs: finalizedRepairs,
                        progress: progress,
                        completion: completion
                    )
                }
            }
        }
    }

    func finishExperimentalAlbumArtworkPointerRepair(
        dbURL: URL,
        tempDir: URL,
        repairs: [ExperimentalAppleMetadataRepair],
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            progress("Refreshing metadata and artwork...")

            var repairDb: OpaquePointer?
            guard sqlite3_open(dbURL.path, &repairDb) == SQLITE_OK else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not reopen the database.")
                return
            }

            let repairedCount = self.applyExperimentalAppleMetadataRepairs(db: repairDb, repairs: repairs, progress: progress)
            _ = self.sqliteExec(repairDb, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(repairDb, "PRAGMA journal_mode=DELETE")
            sqlite3_close(repairDb)

            guard repairedCount > 0 else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Advanced artwork and metadata fix failed.")
                return
            }

            let uploadedArtworkCount = self.uploadExperimentalArtworkFiles(repairs: repairs, progress: progress)
            progress("Uploading repaired database...")

            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"

            let semUpload = DispatchSemaphore(value: 0)
            var uploaded = false
            self.uploadFileToDevice(localURL: dbURL, remotePath: tempDBPath) { ok in
                uploaded = ok
                semUpload.signal()
            }
            semUpload.waitForTransfer()

            guard uploaded else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not upload the repaired database.")
                return
            }

            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            guard let afc else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "AFC unavailable for database swap.")
                return
            }

            if !self.replaceRemoteMediaLibrary(
                tempDBPath: tempDBPath,
                finalDBPath: finalDBPath,
                shmPath: shmPath,
                walPath: walPath,
                afc: afc,
                logContext: "[AlbumArtworkRepair]"
            ) {
                afc_client_free(afc)
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not swap the repaired database.")
                return
            }

            afc_client_free(afc)
            try? FileManager.default.removeItem(at: tempDir)

            self.sendSyncFinishedNotification()
            Logger.shared.log("[AlbumArtworkRepair] Refreshed \(repairedCount) songs and uploaded \(uploadedArtworkCount) artwork files")
            completion(true, "Advanced artwork and metadata fix refreshed \(repairedCount) songs and \(uploadedArtworkCount) artwork files. Restart Music if it is still cached.")
        }
    }

    func finishIOS26ArtworkRepair(
        dbURL: URL,
        tempDir: URL,
        repairs: [(ArtworkRepairCandidate, String)],
        progress: @escaping (String) -> Void,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            progress("Updating artwork database...")

            var repairDb: OpaquePointer?
            guard sqlite3_open(dbURL.path, &repairDb) == SQLITE_OK else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not reopen the database.")
                return
            }

            let repairedCount = self.applyIOS26ArtworkRepairs(db: repairDb, repairs: repairs)
            _ = self.sqliteExec(repairDb, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(repairDb, "PRAGMA journal_mode=DELETE")
            sqlite3_close(repairDb)

            guard repairedCount > 0 else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Artwork database update failed.")
                return
            }

            progress("Uploading repaired database...")

            let tempDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb.temp"
            let finalDBPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb"
            let shmPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-shm"
            let walPath = "/iTunes_Control/iTunes/MediaLibrary.sqlitedb-wal"

            let semUpload = DispatchSemaphore(value: 0)
            var uploaded = false
            self.uploadFileToDevice(localURL: dbURL, remotePath: tempDBPath) { ok in
                uploaded = ok
                semUpload.signal()
            }
            semUpload.waitForTransfer()

            guard uploaded else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not upload the repaired database.")
                return
            }

            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            guard let afc else {
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "AFC unavailable for database swap.")
                return
            }

            if !self.replaceRemoteMediaLibrary(
                tempDBPath: tempDBPath,
                finalDBPath: finalDBPath,
                shmPath: shmPath,
                walPath: walPath,
                afc: afc,
                logContext: "[ArtworkRepair]"
            ) {
                afc_client_free(afc)
                try? FileManager.default.removeItem(at: tempDir)
                completion(false, "Could not swap the repaired database.")
                return
            }

            afc_client_free(afc)
            try? FileManager.default.removeItem(at: tempDir)

            self.sendSyncFinishedNotification()
            Logger.shared.log("[ArtworkRepair] Repaired \(repairedCount) artwork rows")
            completion(true, "Fixed artwork for \(repairedCount) songs. Restart Music if it is still cached.")
        }
    }

    func normalizedArtworkRepairValue(_ value: String) -> String {
        let lowered = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bestAppleMusicArtworkFallbackMatch(for candidate: ArtworkRepairCandidate) async -> AppleMusicAPI.AppleMusicSong? {
        let query = "\(candidate.artist) \(candidate.title)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        let results = await AppleMusicAPI.shared.searchSongs(query: query, limit: 5)
        guard !results.isEmpty else {
            Logger.shared.log("[ArtworkRepair] No Apple Music search results for fallback query: \(query)")
            return nil
        }

        let normalizedTitle = normalizedArtworkRepairValue(candidate.title)
        let normalizedArtist = normalizedArtworkRepairValue(candidate.artist)
        let normalizedAlbum = normalizedArtworkRepairValue(candidate.album)

        var bestSong: AppleMusicAPI.AppleMusicSong?
        var bestScore = Int.min

        for song in results {
            let songTitle = normalizedArtworkRepairValue(song.attributes.name)
            let songArtist = normalizedArtworkRepairValue(song.attributes.artistName)
            let songAlbum = normalizedArtworkRepairValue(song.attributes.albumName ?? "")

            var score = 0

            if !normalizedTitle.isEmpty {
                if songTitle == normalizedTitle {
                    score += 6
                } else if songTitle.contains(normalizedTitle) || normalizedTitle.contains(songTitle) {
                    score += 3
                }
            }

            if !normalizedArtist.isEmpty, normalizedArtist != "unknown artist" {
                if songArtist == normalizedArtist {
                    score += 5
                } else if songArtist.contains(normalizedArtist) || normalizedArtist.contains(songArtist) {
                    score += 2
                }
            }

            if !normalizedAlbum.isEmpty, normalizedAlbum != "unknown album" {
                if songAlbum == normalizedAlbum {
                    score += 2
                } else if songAlbum.contains(normalizedAlbum) || normalizedAlbum.contains(songAlbum) {
                    score += 1
                }
            }

            if bestSong == nil || score > bestScore {
                bestSong = song
                bestScore = score
            }
        }

        guard let bestSong, bestScore >= 7 else {
            Logger.shared.log("[ArtworkRepair] Fallback search did not find a confident Apple Music match for \(candidate.artist) - \(candidate.title)")
            return nil
        }

        Logger.shared.log("[ArtworkRepair] Fallback matched \(candidate.artist) - \(candidate.title) to Apple Music id=\(bestSong.id) with score=\(bestScore)")
        return bestSong
    }

    func experimentalAppleMetadataRepair(
        for candidate: ArtworkRepairCandidate,
        matchedSong: AppleMusicAPI.AppleMusicSong
    ) async -> ExperimentalAppleMetadataRepair? {
        guard let storeItemId = Int64(matchedSong.id), storeItemId > 0 else {
            return nil
        }

        let title = matchedSong.attributes.name
        let artist = matchedSong.attributes.artistName
        let album = matchedSong.attributes.albumName ?? candidate.album
        let audioTraits = matchedSong.attributes.audioTraits ?? []
        let storeFlavor = Array(Set(audioTraits))
            .sorted()
            .joined(separator: ",")

        let artistId = matchedSong.relationships?.artists?.data.first.flatMap { Int64($0.id) } ?? 0
        let composerId = matchedSong.relationships?.composers?.data.first.flatMap { Int64($0.id) } ?? 0
        let genreStoreId = matchedSong.relationships?.genres?.data.first.flatMap { Int64($0.id) } ?? 0
        let albumStoreId = matchedSong.relationships?.albums?.data.first.flatMap { Int64($0.id) } ?? 0
        let releaseDateString = matchedSong.attributes.releaseDate ?? matchedSong.relationships?.albums?.data.first?.attributes.releaseDate
        let year = releaseDateString.flatMap { Int($0.prefix(4)) } ?? 0
        let releaseDate = releaseDateString.flatMap { SongMetadata.parseDateToEpoch($0) } ?? 0
        let explicitRating: Int
        if let rating = matchedSong.attributes.contentRating {
            explicitRating = (rating == "explicit") ? 1 : (rating == "clean" ? 2 : 0)
        } else {
            explicitRating = 0
        }

        let storefrontId = self.storefrontIDForCurrentRegion()
        let copyright = matchedSong.relationships?.albums?.data.first?.attributes.copyright ?? ""
        let storeXid = matchedSong.attributes.isrc ?? ""
        let subscriptionStoreItemId = audioTraits.contains { trait in
            trait.caseInsensitiveCompare("atmos") == .orderedSame || trait.caseInsensitiveCompare("spatial") == .orderedSame
        } ? storeItemId : 0
        let masteredForItunes = ((matchedSong.attributes.isMasteredForItunes ?? false) || (matchedSong.attributes.isAppleDigitalMaster ?? false)) ? 1 : 0
        let hlsAssetTraits = audioTraits.contains { $0.caseInsensitiveCompare("atmos") == .orderedSame } ? 32 : 0
        let colorAnalysis = matchedSong.attributes.artwork?.colors.map { MediaLibraryBuilder.colorAnalysisJSON(for: $0) } ?? ""

        var artworkData: Data?
        if let artworkURL = matchedSong.attributes.artwork?.artworkURL() {
            artworkData = try? await URLSession.shared.data(from: artworkURL).0
        }

        return ExperimentalAppleMetadataRepair(
            itemPid: candidate.itemPid,
            albumPid: candidate.albumPid,
            artworkToken: candidate.artworkToken,
            relativePath: candidate.relativePath,
            title: title,
            artist: artist,
            album: album,
            year: year,
            trackNumber: matchedSong.attributes.trackNumber ?? 0,
            trackCount: 0,
            discNumber: matchedSong.attributes.discNumber ?? 0,
            discCount: 0,
            durationMs: matchedSong.attributes.durationInMillis ?? 0,
            explicitRating: explicitRating,
            copyright: copyright,
            storeItemId: storeItemId,
            artistId: artistId,
            composerId: composerId,
            genreStoreId: genreStoreId,
            albumStoreId: albumStoreId,
            storefrontId: storefrontId,
            storeXid: storeXid,
            storeFlavor: storeFlavor,
            releaseDate: releaseDate,
            subscriptionStoreItemId: subscriptionStoreItemId,
            masteredForItunes: masteredForItunes,
            hlsAssetTraits: hlsAssetTraits,
            colorAnalysis: colorAnalysis,
            artworkData: artworkData
        )
    }

    func storefrontIDForCurrentRegion() -> Int64 {
        let region = UserDefaults.standard.string(forKey: "storeRegion")?.lowercased() ?? "us"
        return SongMetadata.storefrontMap[region] ?? 143441
    }

    func applyExperimentalAppleMetadataRepairs(
        db: OpaquePointer?,
        repairs: [ExperimentalAppleMetadataRepair],
        progress: @escaping (String) -> Void
    ) -> Int {
        _ = sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")

        var repaired = 0
        for (index, repair) in repairs.enumerated() {
            progress("Applying refreshed metadata \(index + 1)/\(repairs.count)...")

            let escapedTitle = repair.title.sqlEscaped
            let escapedArtist = repair.artist.sqlEscaped
            let escapedAlbum = repair.album.sqlEscaped
            let escapedCopyright = repair.copyright.sqlEscaped
            let escapedStoreXid = repair.storeXid.sqlEscaped
            let escapedStoreFlavor = repair.storeFlavor.sqlEscaped
            let escapedColorAnalysis = repair.colorAnalysis.sqlEscaped
            let escapedToken = repair.artworkToken.sqlEscaped
            let escapedRelativePath = repair.relativePath.sqlEscaped

            let ok1 = sqliteExec(db, """
            UPDATE item
            SET disc_number = CASE WHEN \(repair.discNumber) > 0 THEN \(repair.discNumber) ELSE disc_number END,
                track_number = CASE WHEN \(repair.trackNumber) > 0 THEN \(repair.trackNumber) ELSE track_number END
            WHERE item_pid = \(repair.itemPid)
            """)

            let ok2 = sqliteExec(db, """
            UPDATE item_extra
            SET title = '\(escapedTitle)',
                sort_title = '\(escapedTitle)',
                disc_count = CASE WHEN \(repair.discCount) > 0 THEN \(repair.discCount) ELSE disc_count END,
                track_count = CASE WHEN \(repair.trackCount) > 0 THEN \(repair.trackCount) ELSE track_count END,
                total_time_ms = CASE WHEN \(repair.durationMs) > 0 THEN \(repair.durationMs) ELSE total_time_ms END,
                year = CASE WHEN \(repair.year) > 0 THEN \(repair.year) ELSE year END,
                content_rating = \(repair.explicitRating),
                copyright = '\(escapedCopyright)'
            WHERE item_pid = \(repair.itemPid)
            """)

            let ok3 = sqliteExec(db, """
            UPDATE item_artist
            SET item_artist = '\(escapedArtist)',
                sort_item_artist = '\(escapedArtist)',
                store_id = CASE WHEN \(repair.artistId) > 0 THEN \(repair.artistId) ELSE store_id END
            WHERE item_artist_pid = (SELECT item_artist_pid FROM item WHERE item_pid = \(repair.itemPid))
            """)

            let ok4 = sqliteExec(db, """
            UPDATE album_artist
            SET album_artist = '\(escapedArtist)',
                sort_album_artist = '\(escapedArtist)',
                store_id = CASE WHEN \(repair.artistId) > 0 THEN \(repair.artistId) ELSE store_id END
            WHERE album_artist_pid = (SELECT album_artist_pid FROM item WHERE item_pid = \(repair.itemPid))
            """)

            let ok5 = sqliteExec(db, """
            UPDATE album
            SET album = '\(escapedAlbum)',
                sort_album = '\(escapedAlbum)',
                album_year = CASE WHEN \(repair.year) > 0 THEN \(repair.year) ELSE album_year END,
                store_id = CASE WHEN \(repair.albumStoreId) > 0 THEN \(repair.albumStoreId) ELSE store_id END
            WHERE album_pid = \(repair.albumPid)
            """)

            let ok6 = sqliteExec(db, """
            UPDATE item_store
            SET store_xid = '\(escapedStoreXid)',
                store_item_id = \(repair.storeItemId),
                storefront_id = \(repair.storefrontId),
                store_composer_id = CASE WHEN \(repair.composerId) > 0 THEN \(repair.composerId) ELSE store_composer_id END,
                store_genre_id = CASE WHEN \(repair.genreStoreId) > 0 THEN \(repair.genreStoreId) ELSE store_genre_id END,
                store_playlist_id = CASE WHEN \(repair.albumStoreId) > 0 THEN \(repair.albumStoreId) ELSE store_playlist_id END,
                date_released = CASE WHEN \(repair.releaseDate) > 0 THEN \(repair.releaseDate) ELSE date_released END,
                subscription_store_item_id = \(repair.subscriptionStoreItemId),
                is_mastered_for_itunes = \(repair.masteredForItunes),
                store_flavor = '\(escapedStoreFlavor)'
            WHERE item_pid = \(repair.itemPid)
            """)

            let ok7 = sqliteExec(db, """
            INSERT OR REPLACE INTO item_video (item_pid, hls_asset_traits)
            VALUES (\(repair.itemPid), \(repair.hlsAssetTraits))
            """)

            let ok8 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork (
                artwork_token, artwork_source_type, relative_path, artwork_type, interest_data, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 1, '\(escapedRelativePath)', 1, '\(escapedColorAnalysis)', 0
            )
            """)

            let ok9 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork (
                artwork_token, artwork_source_type, relative_path, artwork_type, interest_data, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 300, '\(escapedRelativePath)', 6, '\(escapedColorAnalysis)', 0
            )
            """)

            let ok10 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 1, 1, \(repair.itemPid), 0, 0
            )
            """)

            let ok11 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 1, 1, \(repair.albumPid), 1, 0
            )
            """)

            let ok12 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 1, 1, \(repair.albumPid), 4, 0
            )
            """)

            let ok13 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 1, 1, (SELECT item_artist_pid FROM item WHERE item_pid = \(repair.itemPid)), 2, 0
            )
            """)

            let ok14 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 300, 1, \(repair.itemPid), 0, 0
            )
            """)

            let ok15 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(escapedToken)', 300, 6, \(repair.albumPid), 4, 0
            )
            """)

            let ok16 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(repair.itemPid), 0, 1, '\(escapedToken)', '', 0, 0
            )
            """)

            let ok17 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(repair.albumPid), 1, 1, '\(escapedToken)', '', 0, 0
            )
            """)

            let ok18 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(repair.albumPid), 4, 1, '\(escapedToken)', '', 0, 0
            )
            """)

            let ok19 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(repair.albumPid), 4, 6, '\(escapedToken)', '', 0, 0
            )
            """)

            let ok20 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                (SELECT item_artist_pid FROM item WHERE item_pid = \(repair.itemPid)), 2, 1, '\(escapedToken)', '', 0, 0
            )
            """)

            if ok1 || ok2 || ok3 || ok4 || ok5 || ok6 || ok7 || ok8 || ok9 || ok10 || ok11 || ok12 || ok13 || ok14 || ok15 || ok16 || ok17 || ok18 || ok19 || ok20 {
                repaired += 1
            }
        }

        _ = sqliteExec(db, repaired > 0 ? "COMMIT" : "ROLLBACK")
        return repaired
    }

    func uploadExperimentalArtworkFiles(
        repairs: [ExperimentalAppleMetadataRepair],
        progress: @escaping (String) -> Void
    ) -> Int {
        let uploads = repairs
            .filter { $0.artworkData != nil && !$0.relativePath.isEmpty }
            .reduce(into: [String: ExperimentalAppleMetadataRepair]()) { partial, repair in
                partial[repair.relativePath] = repair
            }
            .values
            .sorted { $0.relativePath < $1.relativePath }

        guard !uploads.isEmpty else { return 0 }

        var afc: AfcClientHandle?
        connectAfcClient(&afc)
        guard afc != nil else {
            Logger.shared.log("[AlbumArtworkRepair] AFC unavailable for artwork upload")
            return 0
        }
        defer { afc_client_free(afc) }

        var uploadedCount = 0
        for (index, repair) in uploads.enumerated() {
            guard let artworkData = repair.artworkData else { continue }

            progress("Uploading refreshed artwork \(index + 1)/\(uploads.count)...")
            let folderName = (repair.relativePath as NSString).deletingLastPathComponent
            let artworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(repair.relativePath)"

            _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals")
            if !folderName.isEmpty && folderName != "." {
                _ = afc_make_directory(afc, "/iTunes_Control/iTunes/Artwork/Originals/\(folderName)")
            }

            if uploadDataToDeviceWithReconnect(artworkData, remotePath: artworkPath, afc: &afc, verify: false) {
                uploadedCount += 1
            }
        }

        return uploadedCount
    }

    func ios26ArtworkRepairCandidates(db: OpaquePointer?) -> [ArtworkRepairCandidate] {
        let sql = """
        SELECT DISTINCT
            i.item_pid,
            i.album_pid,
            IFNULL(s.store_item_id, 0),
            IFNULL(ie.title, ''),
            IFNULL(ia.item_artist, ''),
            IFNULL(al.album, ''),
            at.artwork_token,
            aw.relative_path
        FROM item i
        LEFT JOIN item_store s ON s.item_pid = i.item_pid
        LEFT JOIN item_extra ie ON ie.item_pid = i.item_pid
        LEFT JOIN item_artist ia ON ia.item_artist_pid = i.item_artist_pid
        LEFT JOIN album al ON al.album_pid = i.album_pid
        JOIN artwork_token at
          ON at.entity_pid = i.item_pid
         AND at.entity_type = 0
         AND at.artwork_type = 1
         AND at.artwork_source_type = 1
        JOIN artwork aw
          ON aw.artwork_token = at.artwork_token
         AND aw.artwork_source_type = at.artwork_source_type
         AND aw.artwork_variant_type = at.artwork_variant_type
        WHERE at.artwork_token != ''
          AND aw.relative_path != ''
        """

        var stmt: OpaquePointer?
        var candidates: [ArtworkRepairCandidate] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return candidates
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let tokenPtr = sqlite3_column_text(stmt, 6),
                  let pathPtr = sqlite3_column_text(stmt, 7) else {
                continue
            }

            let title = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let artist = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let album = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

            candidates.append(ArtworkRepairCandidate(
                itemPid: sqlite3_column_int64(stmt, 0),
                albumPid: sqlite3_column_int64(stmt, 1),
                storeItemId: sqlite3_column_int64(stmt, 2),
                title: title,
                artist: artist,
                album: album,
                artworkToken: String(cString: tokenPtr),
                relativePath: String(cString: pathPtr)
            ))
        }

        return candidates
    }

    func applyIOS26ArtworkRepairs(db: OpaquePointer?, repairs: [(ArtworkRepairCandidate, String)]) -> Int {
        _ = sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")
        var repaired = 0

        for (candidate, colorAnalysis) in repairs {
            let token = candidate.artworkToken.sqlEscaped
            let relativePath = candidate.relativePath.sqlEscaped
            let escapedColorAnalysis = colorAnalysis.sqlEscaped

            let ok1 = sqliteExec(db, """
            UPDATE artwork
            SET interest_data = '\(escapedColorAnalysis)'
            WHERE artwork_token = '\(token)'
              AND artwork_source_type IN (1, 300)
            """)

            let ok2 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork (
                artwork_token, artwork_source_type, relative_path, artwork_type, interest_data, artwork_variant_type
            ) VALUES (
                '\(token)', 300, '\(relativePath)', 6, '\(escapedColorAnalysis)', 0
            )
            """)

            let ok3 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(token)', 300, 1, \(candidate.itemPid), 0, 0
            )
            """)

            let ok4 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(candidate.itemPid), 0, 1, '\(token)', '', 0, 0
            )
            """)

            let ok5 = sqliteExec(db, """
            INSERT OR REPLACE INTO artwork_token (
                artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
            ) VALUES (
                '\(token)', 300, 6, \(candidate.albumPid), 4, 0
            )
            """)

            let ok6 = sqliteExec(db, """
            INSERT OR REPLACE INTO best_artwork_token (
                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                fetchable_artwork_source_type, artwork_variant_type
            ) VALUES (
                \(candidate.albumPid), 4, 6, '\(token)', '', 0, 0
            )
            """)

            if ok1 && ok2 && ok3 && ok4 && ok5 && ok6 {
                repaired += 1
            }
        }

        _ = sqliteExec(db, "COMMIT")
        return repaired
    }
    
    
}
