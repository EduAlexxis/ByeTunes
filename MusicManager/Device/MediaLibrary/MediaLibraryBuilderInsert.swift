import Foundation
import SQLite3
import CommonCrypto
import UIKit

// MARK: - Insert
extension MediaLibraryBuilder {
    @discardableResult
    static func insertSongsWithExisting(
        db: OpaquePointer?,
        songs: [SongMetadata],
        existingArtists: [String: Int64],
        existingAlbums: [String: (pid: Int64, year: Int)],
        existingGenres: [String: Int64],
        existingAlbumArtists: [String: Int64],
        version: DatabaseVersion,
        reorderSortMap: Bool
    ) throws -> (pids: [Int64], artworkInfo: [ArtworkInfo]) {
        let now = Int(Date().timeIntervalSince1970)
        
        
        var maxTrackNum = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM item", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxTrackNum = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        var trackNum = maxTrackNum + 1
        
        
        var artists = existingArtists
        var albums = existingAlbums
        var genres = existingGenres
        var albumArtists = existingAlbumArtists
        
        
        var newArtists: [String: Int64] = [:]
        var newAlbums: [String: Int64] = [:]
        var updateAlbums: [String: Int64] = [:]
        var newGenres: [String: Int64] = [:]
        var newAlbumArtists: [String: Int64] = [:]
        var updateArtists: [String: Int64] = [:]
        var updateAlbumArtists: [String: Int64] = [:]
        
        var artistStoreIds: [String: Int64] = [:]
        var albumArtistStoreIds: [String: Int64] = [:]
        var albumStoreIds: [String: Int64] = [:]
        
        var artistRepItem: [String: Int64] = [:]
        var albumRepItem: [String: Int64] = [:]
        var genreRepItem: [String: Int64] = [:]
        var albumArtistRepItem: [String: Int64] = [:]
        
        var processedAlbumArtworkPids = Set<Int64>()
        
        var insertedPids: [Int64] = []
        var collectedArtworkInfo: [ArtworkInfo] = []
        let supportsLocalArtworkSource = version.supportsIOS264ArtworkDisplay && columnExists(db: db, tableName: "artwork_token", columnName: "primary_text_color")
        
        
        
        let existingSignatures = getExistingSongSignatures(db: db)
        Logger.shared.log("[MediaLibraryBuilder] Found \(existingSignatures.count) existing song signatures for duplicate checking")
        
        for song in songs {
            
            let signature = "\(song.title)|\(song.artist)|\(song.album)"
            
            let itemPid: Int64
            if let existingPid = existingSignatures[signature] {
                itemPid = existingPid
                Logger.shared.log("[MediaLibraryBuilder] Resurrecting existing song PID \(itemPid): \(song.title)")
            } else {
                itemPid = SongMetadata.generatePersistentId()
            }
            
            insertedPids.append(itemPid)
            
            
            let artistPid: Int64
            if let existing = artists[song.artist] {
                artistPid = existing
                if song.artistId > 0 {
                    artistStoreIds[song.artist] = song.artistId
                    updateArtists[song.artist] = artistPid
                }
            } else {
                let newPid = SongMetadata.generatePersistentId()
                artists[song.artist] = newPid
                newArtists[song.artist] = newPid
                artistRepItem[song.artist] = itemPid  
                artistStoreIds[song.artist] = song.artistId
                artistPid = newPid
            }
            
            
            let effectiveAlbumArtistName = song.albumArtist ?? song.artist
            let albumArtistPid: Int64
            if let existing = albumArtists[effectiveAlbumArtistName] {
                albumArtistPid = existing
                if song.artistId > 0 {
                    albumArtistStoreIds[effectiveAlbumArtistName] = song.artistId
                    updateAlbumArtists[effectiveAlbumArtistName] = albumArtistPid
                }
            } else {
                let newPid = SongMetadata.generatePersistentId()
                albumArtists[effectiveAlbumArtistName] = newPid
                newAlbumArtists[effectiveAlbumArtistName] = newPid
                albumArtistRepItem[effectiveAlbumArtistName] = itemPid  
                albumArtistStoreIds[effectiveAlbumArtistName] = song.artistId
                albumArtistPid = newPid
            }
            
            
            let albumPid: Int64
            if let existing = albums[song.album] {
                albumPid = existing.pid
                if song.playlistId > 0 {
                    albumStoreIds[song.album] = song.playlistId
                    updateAlbums[song.album] = albumPid
                }
                if (existing.year == 0 || existing.year == 2003 || existing.year != song.year) && song.year != 0 {
                    updateAlbums[song.album] = albumPid
                    albums[song.album] = (pid: albumPid, year: song.year)
                }
            } else {
                let newPid = SongMetadata.generatePersistentId()
                albums[song.album] = (pid: newPid, year: song.year)
                newAlbums[song.album] = newPid
                albumRepItem[song.album] = itemPid  
                albumStoreIds[song.album] = song.playlistId
                albumPid = newPid
            }
            
            
            let effectiveGenre = SongMetadata.canonicalGenre(song.genre)
            let genreId: Int64
            if let existing = genres[effectiveGenre] {
                genreId = existing
            } else {
                let newPid = SongMetadata.generatePersistentId()
                genres[effectiveGenre] = newPid
                newGenres[effectiveGenre] = newPid
                genreRepItem[effectiveGenre] = itemPid
                genreId = newPid
            }
            
            
            let titleSort = insertSortMap(db: db, name: song.title)
            let artistSort = insertSortMap(db: db, name: song.artist)
            let albumSort = insertSortMap(db: db, name: song.album)
            let genreSort = insertSortMap(db: db, name: effectiveGenre)
            
             _ = insertSortMap(db: db, name: effectiveAlbumArtistName)
            
            Logger.shared.log("[MediaLibraryBuilder] Merging: \(song.title) -> \(song.remoteFilename)")
            
            
            let dbTrackNum = song.trackNumber ?? trackNum
            let dbTrackCount = song.trackCount ?? 1
            let dbDiscNum = song.discNumber ?? 1
            let dbDiscCount = song.discCount ?? 1

            let dateAdded = fileDateAdded(for: song.localURL) ?? now
            
            
            
            deleteItemRows(db: db, pid: itemPid, tables: ["item", "item_extra", "item_playback", "item_stats", "item_store", "item_search"])
            
            
            try executeSQL(db, """
                INSERT INTO item (
                    item_pid, media_type, title_order, title_order_section,
                    item_artist_pid, item_artist_order, item_artist_order_section,
                    series_name_order, series_name_order_section,
                    album_pid, album_order, album_order_section,
                    album_artist_pid, album_artist_order, album_artist_order_section,
                    composer_pid, composer_order, composer_order_section,
                    genre_id, genre_order, genre_order_section,
                    disc_number, track_number, episode_sort_id,
                    base_location_id, remote_location_id,
                    exclude_from_shuffle, keep_local, keep_local_status, keep_local_status_reason, keep_local_constraints,
                    in_my_library, is_compilation, date_added, show_composer, is_music_show, date_downloaded, download_source_container_pid
                ) VALUES (
                    \(itemPid), 8, \(titleSort.order), \(titleSort.section),
                    \(artistPid), \(artistSort.order), \(artistSort.section),
                    0, 26,
                    \(albumPid), \(albumSort.order), \(albumSort.section),
                    \(albumArtistPid), \(artistSort.order), \(artistSort.section),
                    0, 0, 26,
                    \(genreId), \(genreSort.order), \(genreSort.section),
                    \(dbDiscNum), \(dbTrackNum), 1,
                    3840, 0,
                    0, 1, 2, 0, 0,
                    1, 0, \(dateAdded), 0, 0, \(dateAdded), 0
                )
            """)
            
            
            let escapedTitle = song.title.sqlEscaped
            let escapedFilename = song.remoteFilename.sqlEscaped
            let escapedCopyright = song.copyright?.sqlEscaped ?? ""
            try executeSQL(db, """
                INSERT INTO item_extra (
                    item_pid, title, sort_title, disc_count, track_count, total_time_ms, year,
                    location, file_size, integrity, is_audible_audio_book, date_modified,
                    media_kind, content_rating, content_rating_level, is_user_disabled, bpm, genius_id,
                    location_kind_id, copyright
                ) VALUES (
                    \(itemPid), '\(escapedTitle)', '\(escapedTitle)', \(dbDiscCount), \(dbTrackCount), \(song.durationMs), \(song.year),
                    '\(escapedFilename)', \(song.fileSize), \(MediaLibraryBuilder.generateIntegrityHex(filename: song.remoteFilename)), 0, \(now),
                    1, \(song.explicitRating), 0, 0, 0, 0,
                    42, '\(escapedCopyright)'
                )
            """)
            
            
            let audioFmt = song.playbackAudioFormat != 0
                ? song.playbackAudioFormat
                : audioFormatForExtension(URL(fileURLWithPath: song.remoteFilename).pathExtension)
            let playbackBitRate = song.playbackBitRate > 0 ? song.playbackBitRate : 320
            let playbackSampleRate = song.playbackSampleRate > 0 ? song.playbackSampleRate : 44100.0
            try executeSQL(db, """
                INSERT INTO item_playback (
                    item_pid, audio_format, bit_rate, codec_type, codec_subtype, data_kind,
                    duration, has_video, relative_volume, sample_rate
                ) VALUES (
                    \(itemPid), \(audioFmt), \(playbackBitRate), \(song.playbackCodecType), \(song.playbackCodecSubtype), 0,
                    0, 0, 0, \(playbackSampleRate)
                )
            """)
            
            
            try executeSQL(db, "INSERT OR REPLACE INTO item_stats (item_pid, date_accessed) VALUES (\(itemPid), \(now))")
            
            
            
            let syncId = SongMetadata.generatePersistentId()
            let storeXidEscaped = song.xid?.sqlEscaped ?? ""
            let combinedAudioTraits = Array(Set(
                song.appleMusicAudioTraits +
                (song.localFileHasDolbyAtmos ? ["atmos"] : []) +
                (song.localFileHasSpatialAudio ? ["spatial"] : [])
            ))
            let storeFlavorEscaped = combinedAudioTraits
                .sorted()
                .joined(separator: ",")
                .sqlEscaped
            let hasAppleCatalogMatch = shouldWriteAppleCatalogStoreFields(for: song)
            let hasAppleSubscriptionAudioTrait = song.isDolbyAtmosCapable || song.hasSpatialAudioTrait || song.hasAppleLosslessTrait
            let subscriptionStoreItemId = hasAppleSubscriptionAudioTrait && hasAppleCatalogMatch
                ? song.storeId
                : 0
            let masteredForItunes = (song.isMasteredForItunes || song.isAppleDigitalMaster) ? 1 : 0
            let matchRedownloadParamsEscaped = hasAppleCatalogMatch
                ? "sagaId=\\(song.storeId)".sqlEscaped
                : ""
            let storeSagaId = hasAppleCatalogMatch ? song.storeId : 0
            let cloudStatus = hasAppleCatalogMatch ? 8 : 0
            let cloudAssetAvailable = hasAppleCatalogMatch ? 1 : 0
            let cloudInMyLibrary = hasAppleCatalogMatch ? 1 : 0
            let playbackEndpointType = subscriptionStoreItemId > 0 ? 3 : 0
            let cloudPlaybackEndpointType = hasAppleCatalogMatch ? 3 : 0
            let isSubscription = (version.isSubscription || hasAppleCatalogMatch) ? 1 : 0
            try executeSQL(db, """
                INSERT OR REPLACE INTO item_store (
                    item_pid, sync_id, sync_in_my_library, is_subscription,
                    store_saga_id, match_redownload_params, cloud_status,
                    store_xid, store_item_id, storefront_id,
                    store_composer_id, store_genre_id, store_playlist_id,
                    date_released, subscription_store_item_id,
                    is_mastered_for_itunes, store_flavor,
                    cloud_asset_available, cloud_in_my_library,
                    playback_endpoint_type, cloud_playback_endpoint_type
                ) VALUES (
                    \(itemPid), \(syncId), 1, \(isSubscription),
                    \(storeSagaId), '\(matchRedownloadParamsEscaped)', \(cloudStatus),
                    '\(storeXidEscaped)', \(song.storeId), \(song.storefrontId),
                    \(song.composerId), \(song.genreStoreId), \(song.playlistId),
                    \(song.releaseDate), \(subscriptionStoreItemId),
                    \(masteredForItunes), '\(storeFlavorEscaped)',
                    \(cloudAssetAvailable), \(cloudInMyLibrary),
                    \(playbackEndpointType), \(cloudPlaybackEndpointType))
            """)
            let hlsAssetTraits = song.isDolbyAtmosCapable ? 32 : 0
            try executeSQL(db, """
                INSERT OR REPLACE INTO item_video (item_pid, hls_asset_traits)
                VALUES (\(itemPid), \(hlsAssetTraits))
            """)
            
            
            try executeSQL(db, """
                INSERT OR REPLACE INTO item_search (item_pid, search_title, search_album, search_artist, search_composer, search_album_artist)
                VALUES (\(itemPid), \(titleSort.order), \(albumSort.order), \(artistSort.order), 0, \(artistSort.order))
            """)
            
            
            let appleSubscriptionLyrics = UserDefaults.standard.bool(forKey: "appleSubscriptionLyrics")
            let resolvedLyricsText = appleSubscriptionLyrics ? "" : SongMetadata.cleanLyrics(song.lyrics ?? "", title: song.title, artist: song.artist)
            let lyricsContent = resolvedLyricsText.sqlEscaped

            if columnExists(db: db, tableName: "lyrics", columnName: "downloaded_catalog_lyrics_available") {
                try executeSQL(db, """
                    INSERT OR REPLACE INTO lyrics (item_pid, lyrics, store_lyrics_available, time_synced_lyrics_available, downloaded_catalog_lyrics_available)
                    VALUES (\(itemPid), '\(lyricsContent)', 1, 1, 0)
                """)
            } else {
                try executeSQL(db, """
                    INSERT OR REPLACE INTO lyrics (item_pid, lyrics, store_lyrics_available, time_synced_lyrics_available)
                    VALUES (\(itemPid), '\(lyricsContent)', 1, 1)
                """)
            }
            
            try executeSQL(db, "INSERT OR REPLACE INTO chapter (item_pid) VALUES (\(itemPid))")
            
            
            
            
            
            if let artworkBytes = song.artworkData {
                
                let artToken = "\(itemPid)"
                
                
                var sha1Hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                let tokenData = artToken.data(using: .utf8)!
                tokenData.withUnsafeBytes { bytes in
                    _ = CC_SHA1(bytes.baseAddress, CC_LONG(tokenData.count), &sha1Hash)
                }
                let hashString = sha1Hash.map { String(format: "%02x", $0) }.joined()
                let folderName = String(hashString.prefix(2))
                let fileName = String(hashString.dropFirst(2))
                let relativePath = "\(folderName)/\(fileName)"

                collectedArtworkInfo.append(ArtworkInfo(
                    itemPid: itemPid, 
                    artworkHash: relativePath, 
                    artworkToken: artToken, 
                    fileSize: UInt32(artworkBytes.count)
                ))
                
                
                
                let colorAnalysis = colorAnalysisJSON(for: song, version: version)
                let escapedColorAnalysis = colorAnalysis.sqlEscaped
                let hasVariantColumn = columnExists(db: db, tableName: "artwork", columnName: "artwork_variant_type")
                if hasVariantColumn {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork (
                            artwork_token, artwork_source_type, relative_path, artwork_type, 
                            interest_data, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 1, '\(relativePath)', 1,
                            '\(escapedColorAnalysis)', 0
                        )
                    """)
                } else {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork (
                            artwork_token, artwork_source_type, relative_path, artwork_type, 
                            interest_data
                        ) VALUES (
                            '\(artToken)', 1, '\(relativePath)', 1,
                            '\(escapedColorAnalysis)'
                        )
                    """)
                }
                
                
                let hasTokenVariantColumn = columnExists(db: db, tableName: "artwork_token", columnName: "artwork_variant_type")
                
                if hasTokenVariantColumn {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(itemPid), 0, 0
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(albumPid), 1, 0
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(albumPid), 4, 0
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(artistPid), 2, 0
                        )
                    """)
                } else {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(itemPid), 0
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(albumPid), 1
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(albumPid), 4
                        )
                    """)
                    
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type
                        ) VALUES (
                            '\(artToken)', 1, 1, \(artistPid), 2
                        )
                    """)
                }
                
                
                
                let hasBestTokenVariantColumn = columnExists(db: db, tableName: "best_artwork_token", columnName: "artwork_variant_type")
                
                if hasBestTokenVariantColumn {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(itemPid), 0, 1, '\(artToken)', '', 0, 0
                        )
                    """)
                    if !processedAlbumArtworkPids.contains(albumPid) {
                        try executeSQL(db, """
                            INSERT OR REPLACE INTO best_artwork_token (
                                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                                fetchable_artwork_source_type, artwork_variant_type
                            ) VALUES (
                                \(albumPid), 1, 1, '\(artToken)', '', 0, 0
                            )
                        """)
                        try executeSQL(db, """
                            INSERT OR REPLACE INTO best_artwork_token (
                                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                                fetchable_artwork_source_type, artwork_variant_type
                            ) VALUES (
                                \(albumPid), 4, 1, '\(artToken)', '', 0, 0
                            )
                        """)
                    }
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(artistPid), 2, 1, '\(artToken)', '', 0, 0
                        )
                    """)
                } else {
                     try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type
                        ) VALUES (
                            \(itemPid), 0, 1, '\(artToken)', '', 0
                        )
                    """)
                    if !processedAlbumArtworkPids.contains(albumPid) {
                        try executeSQL(db, """
                            INSERT OR REPLACE INTO best_artwork_token (
                                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                                fetchable_artwork_source_type
                            ) VALUES (
                                \(albumPid), 1, 1, '\(artToken)', '', 0
                            )
                        """)
                        try executeSQL(db, """
                            INSERT OR REPLACE INTO best_artwork_token (
                                entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                                fetchable_artwork_source_type
                            ) VALUES (
                                \(albumPid), 4, 1, '\(artToken)', '', 0
                            )
                        """)
                    }
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token, 
                            fetchable_artwork_source_type
                        ) VALUES (
                            \(artistPid), 2, 1, '\(artToken)', '', 0
                        )
                    """)
                }
                
                if !processedAlbumArtworkPids.contains(albumPid) {
                    processedAlbumArtworkPids.insert(albumPid)
                }

                if supportsLocalArtworkSource {
                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork (
                            artwork_token, artwork_source_type, relative_path, artwork_type,
                            interest_data, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 300, '\(relativePath)', 6,
                            '\(escapedColorAnalysis)', 0
                        )
                    """)

                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 300, 1, \(itemPid), 0, 0
                        )
                    """)

                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(itemPid), 0, 1, '\(artToken)', '', 0, 0
                        )
                    """)

                    try executeSQL(db, """
                        INSERT OR REPLACE INTO artwork_token (
                            artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type
                        ) VALUES (
                            '\(artToken)', 300, 6, \(albumPid), 4, 0
                        )
                    """)

                    try executeSQL(db, """
                        INSERT OR REPLACE INTO best_artwork_token (
                            entity_pid, entity_type, artwork_type, available_artwork_token, fetchable_artwork_token,
                            fetchable_artwork_source_type, artwork_variant_type
                        ) VALUES (
                            \(albumPid), 4, 6, '\(artToken)', '', 0, 0
                        )
                    """)

                    Logger.shared.log("[MediaLibraryBuilder] Added local artwork source 300 bindings for iOS 26 display")
                }
            }
            
            trackNum += 1
        }
        
        
        for (artistName, artistPid) in newArtists {
            let escapedName = artistName.sqlEscaped
            let groupingKey = SongMetadata.generateGroupingKey(artistName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let syncId = SongMetadata.generatePersistentId()
            let repItem = artistRepItem[artistName] ?? 0
            let storeId = artistStoreIds[artistName] ?? 0
            try executeSQL(db, """
                INSERT INTO item_artist (item_artist_pid, item_artist, sort_item_artist, series_name, grouping_key, sync_id, keep_local, representative_item_pid, store_id)
                VALUES (\(artistPid), '\(escapedName)', '\(escapedName)', '', X'\(groupingHex)', \(syncId), 1, \(repItem), \(storeId))
            """)
        }

        for (artistName, artistPid) in updateArtists {
            let storeId = artistStoreIds[artistName] ?? 0
            guard storeId > 0 else { continue }
            try executeSQL(db, "UPDATE item_artist SET store_id = \(storeId) WHERE item_artist_pid = \(artistPid) AND IFNULL(store_id, 0) = 0")
            Logger.shared.log("[MediaLibraryBuilder] Updating existing item_artist store_id to \(storeId) for: \(artistName)")
        }

        
        for (artistName, aaPid) in newAlbumArtists {
            let escapedName = artistName.sqlEscaped
            let groupingKey = SongMetadata.generateGroupingKey(artistName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let syncId = SongMetadata.generatePersistentId()
            let repItem = albumArtistRepItem[artistName] ?? 0
            let storeId = albumArtistStoreIds[artistName] ?? 0
            
            let sortResult = insertSortMap(db: db, name: artistName)
            
            let sortOrderSection = sortResult.section
            
            let hasSortOrder = version.hasAlbumArtistSortColumns && columnExists(db: db, tableName: "album_artist", columnName: "sort_order")
            let hasNameOrder = version.hasAlbumArtistSortColumns && columnExists(db: db, tableName: "album_artist", columnName: "name_order")
            if hasSortOrder && hasNameOrder {
                try executeSQL(db, """
                    INSERT INTO album_artist (album_artist_pid, album_artist, sort_album_artist, grouping_key, sync_id, keep_local, representative_item_pid, sort_order, sort_order_section, name_order, store_id)
                    VALUES (\(aaPid), '\(escapedName)', '\(escapedName)', X'\(groupingHex)', \(syncId), 1, \(repItem), \(sortResult.order), \(sortOrderSection), \(sortResult.order), \(storeId))
                """)
            } else if hasSortOrder {
                try executeSQL(db, """
                    INSERT INTO album_artist (album_artist_pid, album_artist, sort_album_artist, grouping_key, sync_id, keep_local, representative_item_pid, sort_order, sort_order_section, store_id)
                    VALUES (\(aaPid), '\(escapedName)', '\(escapedName)', X'\(groupingHex)', \(syncId), 1, \(repItem), \(sortResult.order), \(sortOrderSection), \(storeId) )
                """)
            } else {
                try executeSQL(db, """
                    INSERT INTO album_artist (album_artist_pid, album_artist, sort_album_artist, grouping_key, sync_id, keep_local, representative_item_pid, store_id)
                    VALUES (\(aaPid), '\(escapedName)', '\(escapedName)', X'\(groupingHex)', \(syncId), 1, \(repItem), \(storeId))
                """)
            }
        }

        for (artistName, aaPid) in updateAlbumArtists {
            let storeId = albumArtistStoreIds[artistName] ?? 0
            guard storeId > 0 else { continue }
            try executeSQL(db, "UPDATE album_artist SET store_id = \(storeId) WHERE album_artist_pid = \(aaPid) AND IFNULL(store_id, 0) = 0")
            Logger.shared.log("[MediaLibraryBuilder] Updating existing album_artist store_id to \(storeId) for: \(artistName)")
        }

        
        let hasAlbumStoreId = version.hasAlbumStoreId && columnExists(db: db, tableName: "album", columnName: "store_id")
        for (albumName, albumPid) in newAlbums {
            let escapedName = albumName.sqlEscaped
            let groupingKey = SongMetadata.generateGroupingKey(albumName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let storeId = albumStoreIds[albumName] ?? 0

            if let song = songs.first(where: { $0.album == albumName }) {
                let effectiveName = song.albumArtist ?? song.artist
                let aaPid = albumArtists[effectiveName] ?? 0

                let syncId = SongMetadata.generatePersistentId()
                let repItem = albumRepItem[albumName] ?? 0
                if hasAlbumStoreId {
                    try executeSQL(db, """
                        INSERT INTO album (album_pid, album, sort_album, album_artist_pid, grouping_key, album_year, keep_local, sync_id, representative_item_pid, store_id)
                        VALUES (\(albumPid), '\(escapedName)', '\(escapedName)', \(aaPid), X'\(groupingHex)', \(song.year), 1, \(syncId), \(repItem), \(storeId))
                    """)
                } else {
                    try executeSQL(db, """
                        INSERT INTO album (album_pid, album, sort_album, album_artist_pid, grouping_key, album_year, keep_local, sync_id, representative_item_pid)
                        VALUES (\(albumPid), '\(escapedName)', '\(escapedName)', \(aaPid), X'\(groupingHex)', \(song.year), 1, \(syncId), \(repItem))
                    """)
                }
            }
        }
        
        for (albumName, albumPid) in updateAlbums {
            if let song = songs.first(where: { $0.album == albumName }) {
                var updateClauses: [String] = []
                if song.year != 0 {
                    updateClauses.append("album_year = \(song.year)")
                }
                if hasAlbumStoreId, let storeId = albumStoreIds[albumName], storeId > 0 {
                    updateClauses.append("store_id = CASE WHEN IFNULL(store_id, 0) = 0 THEN \(storeId) ELSE store_id END")
                }
                if !updateClauses.isEmpty {
                    try executeSQL(db, "UPDATE album SET \(updateClauses.joined(separator: ", ")) WHERE album_pid = \(albumPid)")
                    Logger.shared.log("[MediaLibraryBuilder] Updating existing album metadata for \(albumName): year=\(song.year), store_id=\(albumStoreIds[albumName] ?? 0)")
                }
            }
        }
        
        
        for (genreName, genreId) in newGenres {
            let escapedName = genreName.sqlEscaped
            let groupingKey = SongMetadata.generateGroupingKey(genreName)
            let groupingHex = groupingKey.map { String(format: "%02x", $0) }.joined()
            let repItem = genreRepItem[genreName] ?? 0
            try executeSQL(db, """
                INSERT INTO genre (genre_id, genre, grouping_key, representative_item_pid)
                VALUES (\(genreId), '\(escapedName)', X'\(groupingHex)', \(repItem))
            """)
        }
        
        
        if reorderSortMap {
            try repairAlphabeticalOrdering(db: db)
        } else {
            Logger.shared.log("[MediaLibraryBuilder] Sort reorder skipped for merge path")
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Fixing existing records without sync_id...")
        
        
        try executeSQL(db, """
            UPDATE album SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        
        try executeSQL(db, """
            UPDATE album_artist SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        
        try executeSQL(db, """
            UPDATE item_artist SET sync_id = abs(random()), keep_local = 1 WHERE sync_id = 0
        """)
        
        Logger.shared.log("[MediaLibraryBuilder] Merged \(songs.count) new songs, \(collectedArtworkInfo.count) with artwork")
        return (insertedPids, collectedArtworkInfo)
    }
    
    
    
}
