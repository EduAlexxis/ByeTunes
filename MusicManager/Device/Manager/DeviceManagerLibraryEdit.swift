import Foundation
import Darwin
import Combine
import UIKit
import CommonCrypto
import SQLite3

// MARK: - Library Edit
extension DeviceManager {
    func deleteExportableSong(_ song: ExportableSongInfo, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "deleting a song from the device library") else {
                completion(false, "Device connection unavailable.")
                return
            }

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "delete_song") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            let remotePath = "\(context.musicDir)/\(song.remoteFilename)"
            let deleteSem = DispatchSemaphore(value: 0)
            var remoteDeleted = false
            self.removeFileFromDevice(remotePath: remotePath) { ok in
                remoteDeleted = ok
                deleteSem.signal()
            }
            deleteSem.waitForTransfer()

            guard remoteDeleted else {
                completion(false, "Failed to remove the song file from the device.")
                return
            }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            let itemPid = song.itemPid > 0 ? song.itemPid : (self.itemPid(forRemoteFilename: song.remoteFilename, db: db) ?? 0)
            guard itemPid > 0 else {
                sqlite3_close(db)
                completion(false, "Could not find that song in MediaLibrary.sqlitedb.")
                return
            }

            _ = self.sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")
            let success = self.removeLibraryRowsAndResidue(db: db, itemPids: [itemPid])
            _ = self.sqliteExec(db, success ? "COMMIT" : "ROLLBACK")
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)

            guard success else {
                completion(false, "Could not update MediaLibrary.sqlitedb.")
                return
            }

            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the updated device library.")
                return
            }

            completion(true, "Deleted \(song.title).")
        }
    }

    func removeLibraryRowsAndResidue(db: OpaquePointer?, itemPids: [Int64]) -> Bool {
        let tempTables = ["_del", "_touched_album", "_touched_iartist", "_touched_aartist", "_touched_genre", "_gone", "_tok"]
        func dropTempTables() {
            for table in tempTables {
                _ = sqliteExec(db, "DROP TABLE IF EXISTS temp.\(table)")
            }
        }
        dropTempTables()
        defer { dropTempTables() }

        guard sqliteExec(db, "CREATE TEMP TABLE _del(item_pid INTEGER PRIMARY KEY)") else { return false }
        for pid in itemPids {
            guard sqliteExec(db, "INSERT OR IGNORE INTO _del VALUES (\(pid))") else { return false }
        }

        let statements: [String] = [
            "CREATE TEMP TABLE _touched_album AS SELECT DISTINCT album_pid p FROM item WHERE item_pid IN (SELECT item_pid FROM _del);",
            "CREATE TEMP TABLE _touched_iartist AS SELECT DISTINCT item_artist_pid p FROM item WHERE item_pid IN (SELECT item_pid FROM _del);",
            "CREATE TEMP TABLE _touched_aartist AS SELECT DISTINCT album_artist_pid p FROM item WHERE item_pid IN (SELECT item_pid FROM _del);",
            "CREATE TEMP TABLE _touched_genre AS SELECT DISTINCT genre_id p FROM item WHERE item_pid IN (SELECT item_pid FROM _del);",
            "INSERT OR IGNORE INTO _del SELECT i.item_pid FROM item i LEFT JOIN item_extra e ON e.item_pid=i.item_pid WHERE i.album_pid IN (SELECT p FROM _touched_album) AND i.in_my_library=0 AND IFNULL(e.location,'')='';",
            "DELETE FROM item WHERE item_pid IN (SELECT item_pid FROM _del);",
            "CREATE TEMP TABLE _gone(p INTEGER PRIMARY KEY);",
            "INSERT OR IGNORE INTO _gone SELECT item_pid FROM _del;",
            "INSERT OR IGNORE INTO _gone SELECT album_pid FROM album WHERE (album_pid IN (SELECT p FROM _touched_album) OR album_artist_pid IN (SELECT p FROM _touched_aartist)) AND NOT EXISTS (SELECT 1 FROM item WHERE item.album_pid=album.album_pid);",
            "INSERT OR IGNORE INTO _gone SELECT item_artist_pid FROM item_artist WHERE item_artist_pid IN (SELECT p FROM _touched_iartist) AND NOT EXISTS (SELECT 1 FROM item WHERE item.item_artist_pid=item_artist.item_artist_pid);",
            "INSERT OR IGNORE INTO _gone SELECT album_artist_pid FROM album_artist WHERE album_artist_pid IN (SELECT p FROM _touched_aartist) AND NOT EXISTS (SELECT 1 FROM item WHERE item.album_artist_pid=album_artist.album_artist_pid) AND NOT EXISTS (SELECT 1 FROM album WHERE album.album_artist_pid=album_artist.album_artist_pid AND album.album_pid NOT IN (SELECT p FROM _gone));",
            "CREATE TEMP TABLE _tok(t TEXT PRIMARY KEY);",
            "INSERT OR IGNORE INTO _tok SELECT artwork_token FROM artwork_token WHERE entity_pid IN (SELECT p FROM _gone) AND artwork_token!='';",
            "INSERT OR IGNORE INTO _tok SELECT available_artwork_token FROM best_artwork_token WHERE entity_pid IN (SELECT p FROM _gone) AND available_artwork_token!='';",
            "INSERT OR IGNORE INTO _tok SELECT fetchable_artwork_token FROM best_artwork_token WHERE entity_pid IN (SELECT p FROM _gone) AND fetchable_artwork_token!='';",
        ] + MediaLibraryBuilder.itemRowTables.filter { $0 != "item" }.map {
            "DELETE FROM \($0) WHERE item_pid IN (SELECT item_pid FROM _del);"
        } + [
            "DELETE FROM artwork_token WHERE entity_pid IN (SELECT p FROM _gone);",
            "DELETE FROM best_artwork_token WHERE entity_pid IN (SELECT p FROM _gone);",
            "DELETE FROM album WHERE album_pid IN (SELECT p FROM _gone);",
            "DELETE FROM item_artist WHERE item_artist_pid IN (SELECT p FROM _gone);",
            "DELETE FROM album_artist WHERE album_artist_pid IN (SELECT p FROM _gone);",
            "DELETE FROM genre WHERE genre_id IN (SELECT p FROM _touched_genre) AND NOT EXISTS (SELECT 1 FROM item WHERE item.genre_id=genre.genre_id);",
            "DELETE FROM artwork WHERE artwork_token IN (SELECT t FROM _tok) AND artwork_token NOT IN (SELECT artwork_token FROM artwork_token) AND artwork_token NOT IN (SELECT available_artwork_token FROM best_artwork_token) AND artwork_token NOT IN (SELECT fetchable_artwork_token FROM best_artwork_token WHERE fetchable_artwork_token!='');"
        ]
        return statements.allSatisfy { sqliteExec(db, $0) }
    }

    func deleteExportableSongs(_ songsToDelete: [ExportableSongInfo], completion: @escaping (Bool, String) -> Void) {
        guard !songsToDelete.isEmpty else {
            completion(false, "No songs to delete.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "deleting songs from the device library") else {
                completion(false, "Device connection unavailable.")
                return
            }

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "delete_songs") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            var deletedCount = 0
            var deletedPids: [Int64] = []
            var success = true

            _ = self.sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")

            for song in songsToDelete {
                let remotePath = "\(context.musicDir)/\(song.remoteFilename)"
                let deleteSem = DispatchSemaphore(value: 0)
                var remoteDeleted = false
                self.removeFileFromDevice(remotePath: remotePath) { ok in
                    remoteDeleted = ok
                    deleteSem.signal()
                }
                deleteSem.waitForTransfer()

                guard remoteDeleted else { continue }

                let itemPid = song.itemPid > 0 ? song.itemPid : (self.itemPid(forRemoteFilename: song.remoteFilename, db: db) ?? 0)
                guard itemPid > 0 else { continue }

                deletedPids.append(itemPid)
                deletedCount += 1
            }

            if !deletedPids.isEmpty && !self.removeLibraryRowsAndResidue(db: db, itemPids: deletedPids) {
                success = false
            }

            _ = self.sqliteExec(db, success ? "COMMIT" : "ROLLBACK")
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)

            guard success, deletedCount > 0 else {
                completion(false, "Could not delete the selected songs.")
                return
            }

            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the updated device library.")
                return
            }

            completion(true, deletedCount == songsToDelete.count
                ? "Deleted \(deletedCount) song\(deletedCount == 1 ? "" : "s")."
                : "Deleted \(deletedCount) of \(songsToDelete.count) song(s).")
        }
    }

    func updateExportableSongMetadata(
        original: ExportableSongInfo,
        updatedSong: SongMetadata,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "editing song metadata on the device") else {
                completion(false, "Device connection unavailable.")
                return
            }

            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "edit_song") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            let itemPid = original.itemPid > 0 ? original.itemPid : (self.itemPid(forRemoteFilename: original.remoteFilename, db: db) ?? 0)
            guard itemPid > 0 else {
                sqlite3_close(db)
                completion(false, "Could not find that song in MediaLibrary.sqlitedb.")
                return
            }

            let safeTitle = updatedSong.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original.title : updatedSong.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeArtist = updatedSong.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original.artist : updatedSong.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeAlbum = updatedSong.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original.album : updatedSong.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeGenre = updatedSong.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? original.genre : updatedSong.genre.trimmingCharacters(in: .whitespacesAndNewlines)

            let newArtistPid = self.ensureNamedArtist(
                db: db,
                tableName: "item_artist",
                idColumn: "item_artist_pid",
                nameColumn: "item_artist",
                sortColumn: "sort_item_artist",
                name: safeArtist,
                representativeItemPid: itemPid
            )
            let newAlbumArtistPid = self.ensureNamedArtist(
                db: db,
                tableName: "album_artist",
                idColumn: "album_artist_pid",
                nameColumn: "album_artist",
                sortColumn: "sort_album_artist",
                name: safeArtist,
                representativeItemPid: itemPid
            )
            let newAlbumPid = self.ensureAlbum(
                db: db,
                name: safeAlbum,
                albumArtistPid: newAlbumArtistPid,
                representativeItemPid: itemPid,
                year: updatedSong.year > 0 ? updatedSong.year : original.year
            )
            let newGenreId = self.ensureGenre(
                db: db,
                name: safeGenre,
                representativeItemPid: itemPid
            )

            _ = self.sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")

            let escapedTitle = self.escapeSQLString(safeTitle)
            let escapedArtist = self.escapeSQLString(safeArtist)
            let escapedAlbum = self.escapeSQLString(safeAlbum)
            let escapedGenre = self.escapeSQLString(safeGenre)
            let escapedLyrics = self.escapeSQLString((updatedSong.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            let trackNumber = max(0, updatedSong.trackNumber ?? original.trackNumber ?? 0)
            let year = max(0, updatedSong.year)
            let explicitRating = max(0, updatedSong.explicitRating)

            let success = [
                """
                UPDATE item
                SET item_artist_pid = \(newArtistPid),
                    album_pid = \(newAlbumPid),
                    album_artist_pid = \(newAlbumArtistPid),
                    genre_id = \(newGenreId),
                    track_number = \(trackNumber)
                WHERE item_pid = \(itemPid)
                """,
                """
                UPDATE item_extra
                SET title = '\(escapedTitle)',
                    sort_title = '\(escapedTitle)',
                    year = \(year),
                    content_rating = \(explicitRating)
                WHERE item_pid = \(itemPid)
                """,
                """
                UPDATE album
                SET album = '\(escapedAlbum)',
                    sort_album = '\(escapedAlbum)',
                    album_year = CASE WHEN \(year) > 0 THEN \(year) ELSE album_year END
                WHERE album_pid = \(newAlbumPid)
                """,
                """
                UPDATE item_artist
                SET item_artist = '\(escapedArtist)',
                    sort_item_artist = '\(escapedArtist)'
                WHERE item_artist_pid = \(newArtistPid)
                """,
                """
                UPDATE album_artist
                SET album_artist = '\(escapedArtist)',
                    sort_album_artist = '\(escapedArtist)'
                WHERE album_artist_pid = \(newAlbumArtistPid)
                """,
                """
                UPDATE genre
                SET genre = '\(escapedGenre)'
                WHERE genre_id = \(newGenreId)
                """,
                """
                INSERT OR REPLACE INTO lyrics (item_pid, lyrics, store_lyrics_available, time_synced_lyrics_available)
                VALUES (\(itemPid), '\(escapedLyrics)', 1, 1)
                """
            ].allSatisfy { self.sqliteExec(db, $0) }

            _ = self.sqliteExec(db, success ? "COMMIT" : "ROLLBACK")
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)

            guard success else {
                completion(false, "Could not update MediaLibrary.sqlitedb.")
                return
            }

            var artworkUploadFailed = false
            if let artworkData = updatedSong.artworkData,
               !artworkData.isEmpty,
               let relativePath = original.artworkRelativePath,
               !relativePath.isEmpty {
                var afc: AfcClientHandle?
                self.connectAfcClient(&afc)
                if let afc {
                    let remoteArtworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
                    artworkUploadFailed = !self.replaceRemoteFileAtomically(artworkData, remotePath: remoteArtworkPath, afc: afc)
                    afc_client_free(afc)
                } else {
                    artworkUploadFailed = true
                }
            }

            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the updated device library.")
                return
            }

            if artworkUploadFailed {
                completion(true, "Updated metadata for \(safeTitle), but artwork failed to upload.")
            } else {
                completion(true, "Updated metadata for \(safeTitle).")
            }
        }
    }

    func replaceExportableSongAudioFile(
        original: ExportableSongInfo,
        newLocalURL: URL,
        completion: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "replacing this song's audio file") else {
                completion(false, "Device connection unavailable.")
                return
            }

            let metadataSem = DispatchSemaphore(value: 0)
            var newMetadata: SongMetadata?
            Task {
                newMetadata = try? await SongMetadata.fromURL(newLocalURL, includeArtwork: false)
                metadataSem.signal()
            }
            metadataSem.waitForTransfer()

            guard let newMetadata, newMetadata.durationMs > 0 else {
                completion(false, "Could not read that file as audio.")
                return
            }

            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill \(killed ? "completed" : "skipped/failed") for replace_audio")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "replace_audio") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            let itemPid = original.itemPid > 0 ? original.itemPid : (self.itemPid(forRemoteFilename: original.remoteFilename, db: db) ?? 0)
            guard itemPid > 0 else {
                sqlite3_close(db)
                completion(false, "Could not find that song in MediaLibrary.sqlitedb.")
                return
            }

            let newRemoteFilename = SongMetadata.generateRemoteFilename(withExtension: newLocalURL.pathExtension)

            var afc: AfcClientHandle?
            self.connectAfcClient(&afc)
            guard let afcHandle = afc else {
                sqlite3_close(db)
                completion(false, "Could not open device file transfer session.")
                return
            }

            let uploaded = self.uploadFileToDevice(
                localURL: newLocalURL,
                remotePath: "\(context.musicDir)/\(newRemoteFilename)",
                afc: afcHandle,
                verify: true
            )
            afc_client_free(afcHandle)

            guard uploaded else {
                sqlite3_close(db)
                completion(false, "Failed to upload the replacement audio file.")
                return
            }

            _ = self.sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")
            let escapedLocation = self.escapeSQLString(newRemoteFilename)
            let success = [
                """
                UPDATE item_extra
                SET total_time_ms = \(newMetadata.durationMs),
                    file_size = \(newMetadata.fileSize),
                    location = '\(escapedLocation)',
                    date_modified = \(Int(Date().timeIntervalSince1970))
                WHERE item_pid = \(itemPid)
                """,
                """
                UPDATE item_playback
                SET audio_format = \(newMetadata.playbackAudioFormat),
                    bit_rate = \(newMetadata.playbackBitRate),
                    codec_type = \(newMetadata.playbackCodecType),
                    codec_subtype = \(newMetadata.playbackCodecSubtype),
                    sample_rate = \(newMetadata.playbackSampleRate)
                WHERE item_pid = \(itemPid)
                """
            ].allSatisfy { self.sqliteExec(db, $0) }

            _ = self.sqliteExec(db, success ? "COMMIT" : "ROLLBACK")
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)

            guard success else {
                completion(false, "Could not update MediaLibrary.sqlitedb.")
                return
            }

            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the updated device library.")
                return
            }

            let oldPath = "\(context.musicDir)/\(original.remoteFilename)"
            let removeSem = DispatchSemaphore(value: 0)
            self.removeFileFromDevice(remotePath: oldPath) { _ in removeSem.signal() }
            removeSem.waitForTransfer()

            completion(true, "Replaced the audio file for \(original.title).")
        }
    }

    func updateExportableSongsMetadata(
        originals: [ExportableSongInfo],
        artist: String,
        album: String,
        genre: String,
        year: Int,
        artworkData: Data?,
        explicitRating: Int?,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard !originals.isEmpty else {
            completion(false, "No songs to update.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard self.ensureActiveTransport(reason: "editing album metadata on the device") else {
                completion(false, "Device connection unavailable.")
                return
            }

            let killed = self.terminateMusicAppIfRunning()
            Logger.shared.log("[SyncLifecycle] Music pre-kill \(killed ? "completed" : "skipped/failed")")

            guard let context = self.stageCurrentMediaLibraryForMutation(label: "edit_album") else {
                completion(false, "Could not stage MediaLibrary.sqlitedb.")
                return
            }
            defer { try? FileManager.default.removeItem(at: context.tempDir) }

            var db: OpaquePointer?
            guard sqlite3_open(context.dbURL.path, &db) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                completion(false, "Could not open MediaLibrary.sqlitedb.")
                return
            }

            let safeArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
            let escapedArtist = self.escapeSQLString(safeArtist)
            let escapedAlbum = self.escapeSQLString(safeAlbum)
            let escapedGenre = self.escapeSQLString(safeGenre)
            let safeYear = max(0, year)

            _ = self.sqliteExec(db, "BEGIN IMMEDIATE TRANSACTION")

            var success = true
            for original in originals {
                let itemPid = original.itemPid > 0 ? original.itemPid : (self.itemPid(forRemoteFilename: original.remoteFilename, db: db) ?? 0)
                guard itemPid > 0 else {
                    success = false
                    break
                }

                let newArtistPid = self.ensureNamedArtist(
                    db: db,
                    tableName: "item_artist",
                    idColumn: "item_artist_pid",
                    nameColumn: "item_artist",
                    sortColumn: "sort_item_artist",
                    name: safeArtist.isEmpty ? original.artist : safeArtist,
                    representativeItemPid: itemPid
                )
                let newAlbumArtistPid = self.ensureNamedArtist(
                    db: db,
                    tableName: "album_artist",
                    idColumn: "album_artist_pid",
                    nameColumn: "album_artist",
                    sortColumn: "sort_album_artist",
                    name: safeArtist.isEmpty ? original.artist : safeArtist,
                    representativeItemPid: itemPid
                )
                let newAlbumPid = self.ensureAlbum(
                    db: db,
                    name: safeAlbum.isEmpty ? original.album : safeAlbum,
                    albumArtistPid: newAlbumArtistPid,
                    representativeItemPid: itemPid,
                    year: safeYear > 0 ? safeYear : original.year
                )
                let newGenreId = self.ensureGenre(
                    db: db,
                    name: safeGenre.isEmpty ? original.genre : safeGenre,
                    representativeItemPid: itemPid
                )

                let trackNumber = max(0, original.trackNumber ?? 0)
                let itemYear = safeYear > 0 ? safeYear : original.year
                let itemExplicitRating = max(0, explicitRating ?? original.explicitRating)

                let statements = [
                    """
                    UPDATE item
                    SET item_artist_pid = \(newArtistPid),
                        album_pid = \(newAlbumPid),
                        album_artist_pid = \(newAlbumArtistPid),
                        genre_id = \(newGenreId),
                        track_number = \(trackNumber)
                    WHERE item_pid = \(itemPid)
                    """,
                    """
                    UPDATE item_extra
                    SET year = \(itemYear),
                        content_rating = \(itemExplicitRating)
                    WHERE item_pid = \(itemPid)
                    """,
                    """
                    UPDATE album
                    SET album = '\(escapedAlbum.isEmpty ? self.escapeSQLString(original.album) : escapedAlbum)',
                        sort_album = '\(escapedAlbum.isEmpty ? self.escapeSQLString(original.album) : escapedAlbum)',
                        album_year = CASE WHEN \(itemYear) > 0 THEN \(itemYear) ELSE album_year END
                    WHERE album_pid = \(newAlbumPid)
                    """,
                    """
                    UPDATE item_artist
                    SET item_artist = '\(escapedArtist.isEmpty ? self.escapeSQLString(original.artist) : escapedArtist)',
                        sort_item_artist = '\(escapedArtist.isEmpty ? self.escapeSQLString(original.artist) : escapedArtist)'
                    WHERE item_artist_pid = \(newArtistPid)
                    """,
                    """
                    UPDATE album_artist
                    SET album_artist = '\(escapedArtist.isEmpty ? self.escapeSQLString(original.artist) : escapedArtist)',
                        sort_album_artist = '\(escapedArtist.isEmpty ? self.escapeSQLString(original.artist) : escapedArtist)'
                    WHERE album_artist_pid = \(newAlbumArtistPid)
                    """,
                    """
                    UPDATE genre
                    SET genre = '\(escapedGenre.isEmpty ? self.escapeSQLString(original.genre) : escapedGenre)'
                    WHERE genre_id = \(newGenreId)
                    """
                ]

                if !statements.allSatisfy({ self.sqliteExec(db, $0) }) {
                    success = false
                    break
                }
            }

            _ = self.sqliteExec(db, success ? "COMMIT" : "ROLLBACK")
            _ = self.sqliteExec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
            _ = self.sqliteExec(db, "PRAGMA journal_mode=DELETE")
            sqlite3_close(db)

            guard success else {
                completion(false, "Could not update MediaLibrary.sqlitedb.")
                return
            }

            var artworkUploadAttempted = false
            var artworkUploadFailureCount = 0
            if let artworkData, !artworkData.isEmpty {
                artworkUploadAttempted = true
                var afc: AfcClientHandle?
                self.connectAfcClient(&afc)
                if let afc {
                    for original in originals {
                        guard let relativePath = original.artworkRelativePath, !relativePath.isEmpty else { continue }
                        let remoteArtworkPath = "/iTunes_Control/iTunes/Artwork/Originals/\(relativePath)"
                        if !self.replaceRemoteFileAtomically(artworkData, remotePath: remoteArtworkPath, afc: afc) {
                            artworkUploadFailureCount += 1
                        }
                    }
                    afc_client_free(afc)
                } else {
                    Logger.shared.log("[DeviceManager] updateExportableSongsMetadata: could not open AFC session to upload artwork")
                    artworkUploadFailureCount = originals.count
                }
                if artworkUploadFailureCount > 0 {
                    Logger.shared.log("[DeviceManager] updateExportableSongsMetadata: artwork upload failed for \(artworkUploadFailureCount) of \(originals.count) song(s)")
                }
            }

            guard self.commitStagedMediaLibrary(localDbURL: context.dbURL) else {
                completion(false, "Failed to upload the updated device library.")
                return
            }

            let songCountText = "\(originals.count) song\(originals.count == 1 ? "" : "s")"
            if artworkUploadAttempted && artworkUploadFailureCount > 0 {
                completion(true, "Updated metadata for \(songCountText), but artwork failed to upload for \(artworkUploadFailureCount) of them.")
            } else {
                completion(true, "Updated metadata for \(songCountText).")
            }
        }
    }
}
