import Foundation
import SQLite3
import CommonCrypto
import UIKit

extension MediaLibraryBuilder {
    static func createSchema(db: OpaquePointer?, version: DatabaseVersion) throws {
        let albumSchema: String
        if version.hasAlbumStoreId {
            albumSchema = "CREATE TABLE album (album_pid INTEGER PRIMARY KEY, album TEXT NOT NULL DEFAULT '', sort_album TEXT, album_artist_pid INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, user_rating INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, all_compilations INTEGER NOT NULL DEFAULT 0, feed_url TEXT, season_number INTEGER NOT NULL DEFAULT 0, album_year INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, contains_classical_work INTEGER NOT NULL DEFAULT 0, date_played_local INTEGER NOT NULL DEFAULT 0, user_rating_is_derived INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, classical_experience_available INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, cloud_library_id TEXT NOT NULL DEFAULT '', liked_state_changed_date INTEGER NOT NULL DEFAULT 0, editorial_notes TEXT NOT NULL DEFAULT '');"
        } else {
            albumSchema = "CREATE TABLE album (album_pid INTEGER PRIMARY KEY, album TEXT NOT NULL DEFAULT '', sort_album TEXT, album_artist_pid INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, user_rating INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, all_compilations INTEGER NOT NULL DEFAULT 0, feed_url TEXT, season_number INTEGER NOT NULL DEFAULT 0, album_year INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, contains_classical_work INTEGER NOT NULL DEFAULT 0, date_played_local INTEGER NOT NULL DEFAULT 0, user_rating_is_derived INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, classical_experience_available INTEGER NOT NULL DEFAULT 0, cloud_library_id TEXT NOT NULL DEFAULT '', liked_state_changed_date INTEGER NOT NULL DEFAULT 0, editorial_notes TEXT NOT NULL DEFAULT '');"
        }

        var schemaParts: [String] = [
            "CREATE TABLE _MLDatabaseProperties (key TEXT PRIMARY KEY, value TEXT);",
            "CREATE TABLE account (dsid INTEGER PRIMARY KEY, apple_id TEXT NOT NULL DEFAULT '', alt_dsid TEXT NOT NULL DEFAULT '');",
            albumSchema
        ]
        
        if version.hasAlbumArtistSortColumns {
            schemaParts.append("CREATE TABLE album_artist (album_artist_pid INTEGER PRIMARY KEY, album_artist TEXT NOT NULL DEFAULT '', sort_album_artist TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, sync_id INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', classical_experience_available INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0, sort_order_section INTEGER NOT NULL DEFAULT 0, name_order INTEGER NOT NULL DEFAULT 0);")
        } else {
            schemaParts.append("CREATE TABLE album_artist (album_artist_pid INTEGER PRIMARY KEY, album_artist TEXT NOT NULL DEFAULT '', sort_album_artist TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, sync_id INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', classical_experience_available INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0);")
        }
        
        schemaParts.append(contentsOf: [
            "CREATE TABLE artwork (artwork_token TEXT NOT NULL DEFAULT '', artwork_source_type INTEGER NOT NULL DEFAULT 0, relative_path TEXT NOT NULL DEFAULT '', artwork_type INTEGER NOT NULL DEFAULT 0, interest_data BLOB, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (artwork_token, artwork_source_type, artwork_variant_type));",
            "CREATE TABLE artwork_token (artwork_token TEXT NOT NULL DEFAULT '', artwork_source_type INTEGER NOT NULL DEFAULT 0, artwork_type INTEGER NOT NULL DEFAULT 0, entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type));",
            "CREATE TABLE base_location (base_location_id INTEGER PRIMARY KEY, path TEXT NOT NULL);",
            "CREATE TABLE best_artwork_token (entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, artwork_type INTEGER NOT NULL DEFAULT 0, available_artwork_token TEXT NOT NULL DEFAULT '', fetchable_artwork_token TEXT NOT NULL DEFAULT '', fetchable_artwork_source_type INTEGER NOT NULL DEFAULT 0, artwork_variant_type INTEGER NOT NULL DEFAULT 0, UNIQUE (entity_pid, entity_type, artwork_type, artwork_variant_type));",
            "CREATE TABLE booklet (booklet_pid INTEGER PRIMARY KEY, item_pid INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '', store_item_id INTEGER NOT NULL DEFAULT 0, redownload_params TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE category (category_id INTEGER PRIMARY KEY, category TEXT NOT NULL UNIQUE);",
            "CREATE TABLE chapter (item_pid INTEGER PRIMARY KEY, chapter_data BLOB);",
            "CREATE TABLE cloud_kvs (key TEXT PRIMARY KEY, play_count_user INTEGER NOT NULL DEFAULT 0, has_been_played INTEGER NOT NULL DEFAULT 0, bookmark_time_ms REAL NOT NULL DEFAULT 0, bookmark_sync_timestamp INTEGER NOT NULL DEFAULT 0, bookmark_sync_revision INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE composer (composer_pid INTEGER PRIMARY KEY, composer TEXT NOT NULL DEFAULT '', sort_composer TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE container (container_pid INTEGER PRIMARY KEY, distinguished_kind INTEGER NOT NULL DEFAULT 0, date_created INTEGER NOT NULL DEFAULT 0, date_modified INTEGER NOT NULL DEFAULT 0, date_played INTEGER NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '', name_order INTEGER NOT NULL DEFAULT 0, is_owner INTEGER NOT NULL DEFAULT 1, is_editable INTEGER NOT NULL DEFAULT 0, parent_pid INTEGER NOT NULL DEFAULT 0, contained_media_type INTEGER NOT NULL DEFAULT 0, workout_template_id INTEGER NOT NULL DEFAULT 0, is_hidden INTEGER NOT NULL DEFAULT 0, is_ignorable_itunes_playlist INTEGER NOT NULL DEFAULT 0, description TEXT, play_count_user INTEGER NOT NULL DEFAULT 0, play_count_recent INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, smart_evaluation_order INTEGER NOT NULL DEFAULT 0, smart_is_folder INTEGER NOT NULL DEFAULT 0, smart_is_dynamic INTEGER NOT NULL DEFAULT 0, smart_is_filtered INTEGER NOT NULL DEFAULT 0, smart_is_genius INTEGER NOT NULL DEFAULT 0, smart_enabled_only INTEGER NOT NULL DEFAULT 0, smart_is_limited INTEGER NOT NULL DEFAULT 0, smart_limit_kind INTEGER NOT NULL DEFAULT 0, smart_limit_order INTEGER NOT NULL DEFAULT 0, smart_limit_value INTEGER NOT NULL DEFAULT 0, smart_reverse_limit_order INTEGER NOT NULL DEFAULT 0, smart_criteria BLOB, play_order INTEGER NOT NULL DEFAULT 0, is_reversed INTEGER NOT NULL DEFAULT 0, album_field_order INTEGER NOT NULL DEFAULT 0, repeat_mode INTEGER NOT NULL DEFAULT 0, shuffle_items INTEGER NOT NULL DEFAULT 0, has_been_shuffled INTEGER NOT NULL DEFAULT 0, filepath TEXT NOT NULL DEFAULT '', is_saveable INTEGER NOT NULL DEFAULT 0, is_src_remote INTEGER NOT NULL DEFAULT 0, is_ignored_syncing INTEGER NOT NULL DEFAULT 0, container_type INTEGER NOT NULL DEFAULT 0, is_container_type_active_target INTEGER NOT NULL DEFAULT 0, orig_date_modified INTEGER NOT NULL DEFAULT 0, store_cloud_id INTEGER NOT NULL DEFAULT 0, has_cloud_play_order INTEGER NOT NULL DEFAULT 0, cloud_global_id TEXT NOT NULL DEFAULT '', cloud_share_url TEXT NOT NULL DEFAULT '', cloud_is_public INTEGER NOT NULL DEFAULT 0, cloud_is_visible INTEGER NOT NULL DEFAULT 0, cloud_is_subscribed INTEGER NOT NULL DEFAULT 0, cloud_is_curator_playlist INTEGER NOT NULL DEFAULT 0, cloud_author_store_id INTEGER NOT NULL DEFAULT 0, cloud_author_display_name TEXT NOT NULL DEFAULT '', cloud_author_store_url TEXT NOT NULL DEFAULT '', cloud_min_refresh_interval INTEGER NOT NULL DEFAULT 0, cloud_last_update_time INTEGER NOT NULL DEFAULT 0, cloud_user_count INTEGER NOT NULL DEFAULT 0, cloud_global_play_count INTEGER NOT NULL DEFAULT 0, cloud_global_like_count INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, external_vendor_identifier TEXT NOT NULL DEFAULT '', external_vendor_display_name TEXT NOT NULL DEFAULT '', external_vendor_container_tag TEXT NOT NULL DEFAULT '', is_external_vendor_playlist INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, cloud_is_sharing_disabled INTEGER NOT NULL DEFAULT 0, cloud_version_hash TEXT NOT NULL DEFAULT '', date_played_local INTEGER NOT NULL DEFAULT 0, cloud_author_handle TEXT NOT NULL DEFAULT '', cloud_universal_library_id TEXT NOT NULL DEFAULT '', should_display_index INTEGER NOT NULL DEFAULT 0, date_downloaded INTEGER NOT NULL DEFAULT 0, category_type_mask INTEGER NOT NULL DEFAULT 0, grouping_sort_key TEXT NOT NULL DEFAULT '', traits INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0, is_collaborative INTEGER NOT NULL DEFAULT 0, collaborator_invite_options INTEGER NOT NULL DEFAULT 0, collaborator_permissions INTEGER NOT NULL DEFAULT 0, collaboration_invitation_link TEXT NOT NULL DEFAULT '', cover_artwork_recipe TEXT NOT NULL DEFAULT '', collaboration_invitation_url_expiration_date INTEGER NOT NULL DEFAULT 0, collaboration_join_request_pending INTEGER NOT NULL DEFAULT 0, collaborator_status INTEGER NOT NULL DEFAULT 0, edit_session_id TEXT NOT NULL DEFAULT '');",
            "CREATE TABLE container_author (container_author_pid INTEGER PRIMARY KEY, container_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, role INTEGER NOT NULL DEFAULT 0, is_pending INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, UNIQUE (container_pid, person_pid));",
            "CREATE TABLE container_item (container_item_pid INTEGER PRIMARY KEY, container_pid INTEGER NOT NULL DEFAULT 0, item_pid INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, uuid TEXT NOT NULL DEFAULT '', position_uuid TEXT NOT NULL DEFAULT '', occurrence_id TEXT NOT NULL DEFAULT '');",
            "CREATE TABLE container_item_media_type (container_pid INTEGER PRIMARY KEY, media_type INTEGER NOT NULL DEFAULT 0, count INTEGER NOT NULL DEFAULT 0, UNIQUE (container_pid, media_type));",
            "CREATE TABLE container_item_person (container_item_person_pid INTEGER PRIMARY KEY, container_item_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, UNIQUE (container_item_pid, person_pid));",
            "CREATE TABLE container_item_reaction (container_item_reaction_pid INTEGER PRIMARY KEY, container_item_pid INTEGER NOT NULL DEFAULT 0, person_pid INTEGER NOT NULL DEFAULT 0, reaction TEXT NOT NULL DEFAULT '', date INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE container_seed (container_pid INTEGER PRIMARY KEY, item_pid INTEGER NOT NULL DEFAULT 0, seed_order INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE db_info (db_pid INTEGER PRIMARY KEY, primary_container_pid INTEGER, media_folder_url TEXT, audio_language INTEGER, subtitle_language INTEGER, genius_cuid TEXT, bib BLOB, rib BLOB);",
            "CREATE TABLE entity_changes (class INTEGER NOT NULL, entity_pid INTEGER NOT NULL, source_pid INTEGER NOT NULL, change_type INTEGER NOT NULL, changes TEXT NOT NULL DEFAULT '', UNIQUE (class, entity_pid, source_pid, change_type));",
            "CREATE TABLE entity_revision (revision INTEGER PRIMARY KEY, entity_pid INTEGER NOT NULL DEFAULT 0, deleted INTEGER NOT NULL DEFAULT 0, class INTEGER NOT NULL DEFAULT 0, revision_type INTEGER NOT NULL DEFAULT 0, UNIQUE (entity_pid, class, revision_type));",
            "CREATE TABLE genius_config (id INTEGER PRIMARY KEY, version INTEGER UNIQUE, default_num_results INTEGER NOT NULL DEFAULT 0, min_num_results INTEGER NOT NULL DEFAULT 0, data BLOB);",
            "CREATE TABLE genius_metadata (genius_id INTEGER PRIMARY KEY, revision_level INTEGER NOT NULL DEFAULT 0, version INTEGER NOT NULL DEFAULT 0, checksum INTEGER NOT NULL DEFAULT 0, data BLOB);",
            "CREATE TABLE genius_similarities (genius_id INTEGER PRIMARY KEY, data BLOB);",
            "CREATE TABLE genre (genre_id INTEGER PRIMARY KEY, genre TEXT NOT NULL DEFAULT '', grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item (item_pid INTEGER PRIMARY KEY, media_type INTEGER NOT NULL DEFAULT 0, title_order INTEGER NOT NULL DEFAULT 0, title_order_section INTEGER NOT NULL DEFAULT 0, item_artist_pid INTEGER NOT NULL DEFAULT 0, item_artist_order INTEGER NOT NULL DEFAULT 0, item_artist_order_section INTEGER NOT NULL DEFAULT 0, series_name_order INTEGER NOT NULL DEFAULT 0, series_name_order_section INTEGER NOT NULL DEFAULT 0, album_pid INTEGER NOT NULL DEFAULT 0, album_order INTEGER NOT NULL DEFAULT 0, album_order_section INTEGER NOT NULL DEFAULT 0, album_artist_pid INTEGER NOT NULL DEFAULT 0, album_artist_order INTEGER NOT NULL DEFAULT 0, album_artist_order_section INTEGER NOT NULL DEFAULT 0, composer_pid INTEGER NOT NULL DEFAULT 0, composer_order INTEGER NOT NULL DEFAULT 0, composer_order_section INTEGER NOT NULL DEFAULT 0, genre_id INTEGER NOT NULL DEFAULT 0, genre_order INTEGER NOT NULL DEFAULT 0, genre_order_section INTEGER NOT NULL DEFAULT 0, disc_number INTEGER NOT NULL DEFAULT 0, track_number INTEGER NOT NULL DEFAULT 0, episode_sort_id INTEGER NOT NULL DEFAULT 0, base_location_id INTEGER NOT NULL DEFAULT 0, remote_location_id INTEGER NOT NULL DEFAULT 0, exclude_from_shuffle INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, in_my_library INTEGER NOT NULL DEFAULT 0, is_compilation INTEGER NOT NULL DEFAULT 0, date_added INTEGER NOT NULL DEFAULT 0, show_composer INTEGER NOT NULL DEFAULT 0, is_music_show INTEGER NOT NULL DEFAULT 0, date_downloaded INTEGER NOT NULL DEFAULT 0, download_source_container_pid INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item_artist (item_artist_pid INTEGER PRIMARY KEY, item_artist TEXT NOT NULL DEFAULT '', sort_item_artist TEXT, series_name TEXT NOT NULL DEFAULT '', sort_series_name TEXT, grouping_key BLOB, cloud_status INTEGER NOT NULL DEFAULT 0, store_id INTEGER NOT NULL DEFAULT 0, representative_item_pid INTEGER NOT NULL DEFAULT 0, keep_local INTEGER NOT NULL DEFAULT 0, keep_local_status INTEGER NOT NULL DEFAULT 0, keep_local_status_reason INTEGER NOT NULL DEFAULT 0, keep_local_constraints INTEGER NOT NULL DEFAULT 0, app_data BLOB, sync_id INTEGER NOT NULL DEFAULT 0, classical_experience_available INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item_extra (item_pid INTEGER PRIMARY KEY, title TEXT NOT NULL DEFAULT '', sort_title TEXT, disc_count INTEGER NOT NULL DEFAULT 0, track_count INTEGER NOT NULL DEFAULT 0, total_time_ms REAL NOT NULL DEFAULT 0, year INTEGER NOT NULL DEFAULT 0, location TEXT NOT NULL DEFAULT '', file_size INTEGER NOT NULL DEFAULT 0, integrity BLOB, is_audible_audio_book INTEGER NOT NULL DEFAULT 0, date_modified INTEGER NOT NULL DEFAULT 0, media_kind INTEGER NOT NULL DEFAULT 0, content_rating INTEGER NOT NULL DEFAULT 0, content_rating_level INTEGER NOT NULL DEFAULT 0, is_user_disabled INTEGER NOT NULL DEFAULT 0, bpm INTEGER NOT NULL DEFAULT 0, genius_id INTEGER NOT NULL DEFAULT 0, comment TEXT, grouping TEXT, description TEXT, description_long TEXT, collection_description TEXT, copyright TEXT, pending_genius_checksum INTEGER NOT NULL DEFAULT 0, category_id INTEGER NOT NULL DEFAULT 0, location_kind_id INTEGER NOT NULL DEFAULT 0, version TEXT NOT NULL DEFAULT '', display_version TEXT NOT NULL DEFAULT '', classical_work TEXT NOT NULL DEFAULT '', classical_movement TEXT NOT NULL DEFAULT '', classical_movement_count INTEGER NOT NULL DEFAULT 0, classical_movement_number INTEGER NOT NULL DEFAULT 0, is_preorder INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item_kvs (item_pid INTEGER PRIMARY KEY, key TEXT NOT NULL DEFAULT '');",
            "CREATE TABLE item_playback (item_pid INTEGER PRIMARY KEY, audio_format INTEGER NOT NULL DEFAULT 0, bit_rate INTEGER NOT NULL DEFAULT 0, codec_type INTEGER NOT NULL DEFAULT 0, codec_subtype INTEGER NOT NULL DEFAULT 0, data_kind INTEGER NOT NULL DEFAULT 0, data_url TEXT, duration INTEGER NOT NULL DEFAULT 0, eq_preset TEXT, format TEXT, gapless_heuristic_info INTEGER NOT NULL DEFAULT 0, gapless_encoding_delay INTEGER NOT NULL DEFAULT 0, gapless_encoding_drain INTEGER NOT NULL DEFAULT 0, gapless_last_frame_resynch INTEGER NOT NULL DEFAULT 0, has_video INTEGER NOT NULL DEFAULT 0, relative_volume INTEGER, sample_rate REAL NOT NULL DEFAULT 0, start_time_ms REAL NOT NULL DEFAULT 0, stop_time_ms REAL NOT NULL DEFAULT 0, volume_normalization_energy INTEGER NOT NULL DEFAULT 0, progression_direction INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item_search (item_pid INTEGER PRIMARY KEY, search_title INTEGER NOT NULL DEFAULT 0, search_album INTEGER NOT NULL DEFAULT 0, search_artist INTEGER NOT NULL DEFAULT 0, search_composer INTEGER NOT NULL DEFAULT 0, search_album_artist INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE item_stats (item_pid INTEGER PRIMARY KEY, user_rating INTEGER NOT NULL DEFAULT 0, needs_restore INTEGER NOT NULL DEFAULT 0, download_identifier TEXT, play_count_user INTEGER NOT NULL DEFAULT 0, play_count_recent INTEGER NOT NULL DEFAULT 0, has_been_played INTEGER NOT NULL DEFAULT 0, date_played INTEGER NOT NULL DEFAULT 0, date_skipped INTEGER NOT NULL DEFAULT 0, date_accessed INTEGER NOT NULL DEFAULT 0, is_alarm INTEGER NOT NULL DEFAULT 0, skip_count_user INTEGER NOT NULL DEFAULT 0, skip_count_recent INTEGER NOT NULL DEFAULT 0, remember_bookmark INTEGER NOT NULL DEFAULT 0, bookmark_time_ms REAL NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0, chosen_by_auto_fill INTEGER NOT NULL DEFAULT 0, liked_state INTEGER NOT NULL DEFAULT 0, liked_state_changed INTEGER NOT NULL DEFAULT 0, user_rating_is_derived INTEGER NOT NULL DEFAULT 0, liked_state_changed_date INTEGER NOT NULL DEFAULT 0);"
        ])
        
        if version.hasCanonicalIDs {
            schemaParts.append("CREATE TABLE item_store (item_pid INTEGER PRIMARY KEY, store_item_id INTEGER NOT NULL DEFAULT 0, store_composer_id INTEGER NOT NULL DEFAULT 0, store_genre_id INTEGER NOT NULL DEFAULT 0, store_playlist_id INTEGER NOT NULL DEFAULT 0, storefront_id INTEGER NOT NULL DEFAULT 0, purchase_history_id INTEGER NOT NULL DEFAULT 0, purchase_history_token INTEGER NOT NULL DEFAULT 0, purchase_history_redownload_params TEXT, store_saga_id INTEGER NOT NULL DEFAULT 0, match_redownload_params TEXT, cloud_status INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, home_sharing_id INTEGER NOT NULL DEFAULT 0, is_ota_purchased INTEGER NOT NULL DEFAULT 0, store_kind INTEGER NOT NULL DEFAULT 0, account_id INTEGER NOT NULL DEFAULT 0, downloader_account_id INTEGER NOT NULL DEFAULT 0, family_account_id INTEGER NOT NULL DEFAULT 0, is_protected INTEGER NOT NULL DEFAULT 0, key_versions INTEGER NOT NULL DEFAULT 0, key_platform_id INTEGER NOT NULL DEFAULT 0, key_id INTEGER NOT NULL DEFAULT 0, key_id_2 INTEGER NOT NULL DEFAULT 0, date_purchased INTEGER NOT NULL DEFAULT 0, date_released INTEGER NOT NULL DEFAULT 0, external_guid TEXT, feed_url TEXT, artwork_url TEXT, store_xid TEXT, store_flavor TEXT, store_matched_status INTEGER NOT NULL DEFAULT 0, store_redownloaded_status INTEGER NOT NULL DEFAULT 0, extras_url TEXT NOT NULL DEFAULT '', vpp_is_licensed INTEGER NOT NULL DEFAULT 0, vpp_org_id INTEGER NOT NULL DEFAULT 0, vpp_org_name TEXT NOT NULL DEFAULT '', sync_redownload_params TEXT NOT NULL DEFAULT '', needs_reporting INTEGER NOT NULL DEFAULT 0, subscription_store_item_id INTEGER NOT NULL DEFAULT 0, playback_endpoint_type INTEGER NOT NULL DEFAULT 0, is_mastered_for_itunes INTEGER NOT NULL DEFAULT 0, radio_station_id TEXT NOT NULL DEFAULT '', advertisement_unique_id TEXT NOT NULL DEFAULT '', advertisement_type INTEGER NOT NULL DEFAULT 0, is_artist_uploaded_content INTEGER NOT NULL DEFAULT 0, cloud_asset_available INTEGER NOT NULL DEFAULT 0, is_subscription INTEGER NOT NULL DEFAULT 0, sync_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_album_id TEXT NOT NULL DEFAULT '', cloud_playback_endpoint_type INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', reporting_store_item_id INTEGER NOT NULL DEFAULT 0, asset_store_item_id INTEGER NOT NULL DEFAULT 0, extended_playback_attribute INTEGER NOT NULL DEFAULT 0, extended_lyrics_attribute INTEGER NOT NULL DEFAULT 0, store_canonical_id TEXT NOT NULL DEFAULT '', tv_show_canonical_id TEXT NOT NULL DEFAULT '', tv_season_canonical_id TEXT NOT NULL DEFAULT '', immersive_deep_link_url TEXT NOT NULL DEFAULT '');")
        } else {
            schemaParts.append("CREATE TABLE item_store (item_pid INTEGER PRIMARY KEY, store_item_id INTEGER NOT NULL DEFAULT 0, store_composer_id INTEGER NOT NULL DEFAULT 0, store_genre_id INTEGER NOT NULL DEFAULT 0, store_playlist_id INTEGER NOT NULL DEFAULT 0, storefront_id INTEGER NOT NULL DEFAULT 0, purchase_history_id INTEGER NOT NULL DEFAULT 0, purchase_history_token INTEGER NOT NULL DEFAULT 0, purchase_history_redownload_params TEXT, store_saga_id INTEGER NOT NULL DEFAULT 0, match_redownload_params TEXT, cloud_status INTEGER NOT NULL DEFAULT 0, sync_id INTEGER NOT NULL DEFAULT 0, home_sharing_id INTEGER NOT NULL DEFAULT 0, is_ota_purchased INTEGER NOT NULL DEFAULT 0, store_kind INTEGER NOT NULL DEFAULT 0, account_id INTEGER NOT NULL DEFAULT 0, downloader_account_id INTEGER NOT NULL DEFAULT 0, family_account_id INTEGER NOT NULL DEFAULT 0, is_protected INTEGER NOT NULL DEFAULT 0, key_versions INTEGER NOT NULL DEFAULT 0, key_platform_id INTEGER NOT NULL DEFAULT 0, key_id INTEGER NOT NULL DEFAULT 0, key_id_2 INTEGER NOT NULL DEFAULT 0, date_purchased INTEGER NOT NULL DEFAULT 0, date_released INTEGER NOT NULL DEFAULT 0, external_guid TEXT, feed_url TEXT, artwork_url TEXT, store_xid TEXT, store_flavor TEXT, store_matched_status INTEGER NOT NULL DEFAULT 0, store_redownloaded_status INTEGER NOT NULL DEFAULT 0, extras_url TEXT NOT NULL DEFAULT '', vpp_is_licensed INTEGER NOT NULL DEFAULT 0, vpp_org_id INTEGER NOT NULL DEFAULT 0, vpp_org_name TEXT NOT NULL DEFAULT '', sync_redownload_params TEXT NOT NULL DEFAULT '', needs_reporting INTEGER NOT NULL DEFAULT 0, subscription_store_item_id INTEGER NOT NULL DEFAULT 0, playback_endpoint_type INTEGER NOT NULL DEFAULT 0, is_mastered_for_itunes INTEGER NOT NULL DEFAULT 0, radio_station_id TEXT NOT NULL DEFAULT '', advertisement_unique_id TEXT NOT NULL DEFAULT '', advertisement_type INTEGER NOT NULL DEFAULT 0, is_artist_uploaded_content INTEGER NOT NULL DEFAULT 0, cloud_asset_available INTEGER NOT NULL DEFAULT 0, is_subscription INTEGER NOT NULL DEFAULT 0, sync_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_in_my_library INTEGER NOT NULL DEFAULT 0, cloud_album_id TEXT NOT NULL DEFAULT '', cloud_playback_endpoint_type INTEGER NOT NULL DEFAULT 0, cloud_universal_library_id TEXT NOT NULL DEFAULT '', reporting_store_item_id INTEGER NOT NULL DEFAULT 0, asset_store_item_id INTEGER NOT NULL DEFAULT 0, extended_playback_attribute INTEGER NOT NULL DEFAULT 0, extended_lyrics_attribute INTEGER NOT NULL DEFAULT 0);")
        }
        
        schemaParts.append(contentsOf: [
            "CREATE TABLE item_video (item_pid INTEGER PRIMARY KEY, video_quality INTEGER NOT NULL DEFAULT 0, is_rental INTEGER NOT NULL DEFAULT 0, has_chapter_data INTEGER NOT NULL DEFAULT 0, season_number INTEGER NOT NULL DEFAULT 0, episode_id TEXT NOT NULL DEFAULT '', network_name TEXT NOT NULL DEFAULT '', extended_content_rating TEXT NOT NULL DEFAULT '', movie_info TEXT NOT NULL DEFAULT '', has_alternate_audio INTEGER NOT NULL DEFAULT 0, has_subtitles INTEGER NOT NULL DEFAULT 0, audio_language INTEGER NOT NULL DEFAULT 0, audio_track_index INTEGER NOT NULL DEFAULT 0, audio_track_id INTEGER NOT NULL DEFAULT 0, subtitle_language INTEGER NOT NULL DEFAULT 0, subtitle_track_index INTEGER NOT NULL DEFAULT 0, rental_duration INTEGER NOT NULL DEFAULT 0, rental_playback_duration INTEGER NOT NULL DEFAULT 0, rental_playback_date_started INTEGER NOT NULL DEFAULT 0, rental_date_started INTEGER NOT NULL DEFAULT 0, is_demo INTEGER NOT NULL DEFAULT 0, has_hls INTEGER NOT NULL DEFAULT 0, audio_track_locale TEXT NOT NULL DEFAULT '', show_sort_type INTEGER NOT NULL DEFAULT 0, episode_type INTEGER NOT NULL DEFAULT 0, episode_type_display_name TEXT NOT NULL DEFAULT '', episode_sub_sort_order INTEGER NOT NULL DEFAULT 0, hls_offline_playback_keys BLOB, is_premium INTEGER NOT NULL DEFAULT 0, color_capability INTEGER NOT NULL DEFAULT 0, hls_color_capability INTEGER NOT NULL DEFAULT 0, hls_video_quality INTEGER NOT NULL DEFAULT 0, hls_playlist_url TEXT NOT NULL DEFAULT '', audio_capability INTEGER NOT NULL DEFAULT 0, hls_audio_capability INTEGER NOT NULL DEFAULT 0, hls_asset_traits INTEGER NOT NULL DEFAULT 0, hls_key_server_url TEXT NOT NULL DEFAULT '', hls_key_cert_url TEXT NOT NULL DEFAULT '', hls_key_server_protocol TEXT NOT NULL DEFAULT '');",
            "CREATE TABLE library_pins (pin_pid INTEGER PRIMARY KEY, entity_pid INTEGER NOT NULL DEFAULT 0, entity_type INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL DEFAULT 0, default_action INTEGER NOT NULL DEFAULT 1, position_uuid TEXT, UNIQUE (entity_pid, entity_type));",
            "CREATE TABLE library_property (property_pid INTEGER PRIMARY KEY, source_id INTEGER, key TEXT, value TEXT, UNIQUE (source_id, key));",
            "CREATE TABLE lyrics (item_pid INTEGER PRIMARY KEY, checksum INTEGER NOT NULL DEFAULT 0, pending_checksum INTEGER NOT NULL DEFAULT 0, lyrics TEXT NOT NULL DEFAULT '', store_lyrics_available INTEGER NOT NULL DEFAULT 0, time_synced_lyrics_available INTEGER NOT NULL DEFAULT 0, downloaded_catalog_lyrics_available INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE person (person_pid INTEGER PRIMARY KEY, cloud_id TEXT NOT NULL DEFAULT '', handle TEXT NOT NULL DEFAULT '', name TEXT NOT NULL DEFAULT '', image_url TEXT NOT NULL DEFAULT '', image_token TEXT NOT NULL DEFAULT '', lightweight_profile INTEGER NOT NULL DEFAULT 0);",
            "CREATE TABLE sort_map (name TEXT NOT NULL UNIQUE, name_order INTEGER UNIQUE, name_section INTEGER, sort_key BLOB NOT NULL DEFAULT x'');",
            "CREATE TABLE sort_map_no_uniques (name TEXT, name_order INTEGER, name_section INTEGER, sort_key BLOB);",
            "CREATE TABLE source (source_pid INTEGER PRIMARY KEY, source_name TEXT, last_sync_date INTEGER NOT NULL DEFAULT 0, last_sync_revision INTEGER NOT NULL DEFAULT 0);"
        ])
        
        for statement in schemaParts {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement, nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                Logger.shared.log("[MediaLibraryBuilder] Schema error: \(error)")
                Logger.shared.log("[MediaLibraryBuilder] Statement: \(statement)")
                throw MediaLibraryError.schemaCreationFailed(error)
            }
        }
        
        try createIndexes(db: db, version: version)
    }
    
    
    
    static func createIndexes(db: OpaquePointer?, version: DatabaseVersion) throws {
        let indexes = """
        -- CRITICAL: Composite indexes from documentation required for browsing
        -- IMPORTANTE: Indexes compuestos que pide la docu pa poder navegar
        CREATE INDEX IF NOT EXISTS ItemArtist ON item (item_artist_order ASC, item_artist_pid ASC);
        CREATE INDEX IF NOT EXISTS ItemAlbum ON item (album_order ASC, album_pid ASC, disc_number ASC, track_number ASC);
        CREATE INDEX IF NOT EXISTS ItemTitle ON item (title_order ASC, item_artist_order ASC);
        CREATE INDEX IF NOT EXISTS ItemKeepLocal ON item (keep_local ASC);
        
        -- sort_map indexes for fast lookups
        -- Indexes pal sort_map pa buscar en fa
        CREATE INDEX IF NOT EXISTS SortMapSortName ON sort_map (name ASC);
        CREATE INDEX IF NOT EXISTS SortMapSortNameOrder ON sort_map (name_order ASC);
        
        -- Additional indexes on foreign keys and common lookups
        -- Mas indexes pa foreign keys y lookups comunes
        CREATE INDEX IF NOT EXISTS idx_item_album_pid ON item (album_pid);
        CREATE INDEX IF NOT EXISTS idx_item_artist_pid ON item (item_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_item_album_artist_pid ON item (album_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_item_genre_id ON item (genre_id);
        CREATE INDEX IF NOT EXISTS idx_item_base_location ON item (base_location_id);
        CREATE INDEX IF NOT EXISTS idx_item_media_type ON item (media_type);
        CREATE INDEX IF NOT EXISTS idx_item_title_order ON item (title_order);
        CREATE INDEX IF NOT EXISTS idx_item_date_added ON item (date_added);
        CREATE INDEX IF NOT EXISTS idx_item_in_my_library ON item (in_my_library);
        
        CREATE INDEX IF NOT EXISTS idx_item_extra_item_pid ON item_extra (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_playback_item_pid ON item_playback (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_store_item_pid ON item_store (item_pid);
        CREATE INDEX IF NOT EXISTS idx_item_store_sync_id ON item_store (sync_id);
        
        CREATE INDEX IF NOT EXISTS idx_item_stats_item_pid ON item_stats (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_item_search_item_pid ON item_search (item_pid);
        CREATE INDEX IF NOT EXISTS idx_item_search_title ON item_search (search_title);
        CREATE INDEX IF NOT EXISTS idx_item_search_artist ON item_search (search_artist);
        CREATE INDEX IF NOT EXISTS idx_item_search_album ON item_search (search_album);
        
        CREATE INDEX IF NOT EXISTS idx_album_album_artist_pid ON album (album_artist_pid);
        CREATE INDEX IF NOT EXISTS idx_album_grouping_key ON album (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_item_artist_grouping_key ON item_artist (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_album_artist_grouping_key ON album_artist (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_genre_grouping_key ON genre (grouping_key);
        
        CREATE INDEX IF NOT EXISTS idx_container_item_container_pid ON container_item (container_pid);
        CREATE INDEX IF NOT EXISTS idx_container_item_item_pid ON container_item (item_pid);
        
        CREATE INDEX IF NOT EXISTS idx_artwork_token_entity ON artwork_token (entity_pid, entity_type);
        
        CREATE INDEX IF NOT EXISTS idx_best_artwork_entity ON best_artwork_token (entity_pid, entity_type);
        """
        
        let statements = indexes.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        for statement in statements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement + ";", nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                Logger.shared.log("[MediaLibraryBuilder] Index warning: \(error)")
                
            }
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Indexes created")
        
        
        try createTriggers(db: db, version: version)
    }
    
    
    
    static func createTriggers(db: OpaquePointer?, version: DatabaseVersion) throws {
        
        let triggerSQL = """
        CREATE TRIGGER IF NOT EXISTS on_insert_item_setInMyLibraryColumn 
        AFTER INSERT ON item_store 
        BEGIN 
          UPDATE item SET in_my_library = (
            CASE WHEN 
              new.home_sharing_id OR 
              (new.store_saga_id AND new.cloud_in_my_library) OR 
              new.purchase_history_id OR 
              (new.sync_id AND new.sync_in_my_library) OR
              new.is_ota_purchased 
            THEN 1 ELSE 0 END
          ) WHERE item_pid = new.item_pid; 
        END;
        """
        
        var glassTriggers = ""
        if version.hasCanonicalIDs {
            glassTriggers = """
            CREATE TRIGGER IF NOT EXISTS on_remove_source_setPlaybackEndpointType AFTER UPDATE OF playback_endpoint_type ON item_store BEGIN UPDATE item_store SET playback_endpoint_type = (CASE WHEN new.playback_endpoint_type >= 0 THEN new.playback_endpoint_type ELSE (CASE WHEN store_saga_id THEN cloud_playback_endpoint_type WHEN sync_id THEN 0 WHEN purchase_history_id THEN 1 WHEN is_ota_purchased THEN 0 WHEN is_subscription THEN 3 ELSE 0 END) END) WHERE item_pid = new.item_pid; END;
            
            CREATE TRIGGER IF NOT EXISTS on_insert_item_setRemoteLocationColumn AFTER INSERT ON item_store BEGIN UPDATE item SET remote_location_id = ( CASE WHEN new.home_sharing_id != 0 THEN 300 ELSE ( CASE WHEN IFNULL(new.match_redownload_params, '') != '' THEN 200 ELSE ( CASE WHEN IFNULL(new.purchase_history_redownload_params, '') != '' AND new.purchase_history_id != 0 THEN 100 ELSE ( CASE WHEN new.subscription_store_item_id != 0 AND new.is_subscription AND new.cloud_asset_available THEN 50 ELSE ( CASE WHEN new.sync_redownload_params == 'redownload' AND new.sync_id != 0 THEN 20 ELSE ( CASE WHEN new.sync_redownload_params == 'local' AND new.sync_id != 0 THEN 10 ELSE 0 END) END) END) END) END) END) WHERE item_pid = new.item_pid; END;
            
            CREATE TRIGGER IF NOT EXISTS on_update_item_setRemoteLocationColumn AFTER UPDATE OF match_redownload_params, purchase_history_redownload_params, purchase_history_id, home_sharing_id, sync_redownload_params, subscription_store_item_id, store_saga_id, is_subscription, cloud_asset_available ON item_store BEGIN UPDATE item SET remote_location_id = ( CASE WHEN new.home_sharing_id != 0 THEN 300 ELSE ( CASE WHEN IFNULL(new.match_redownload_params, '') != '' THEN 200 ELSE ( CASE WHEN IFNULL(new.purchase_history_redownload_params, '') != '' AND new.purchase_history_id != 0 THEN 100 ELSE ( CASE WHEN new.subscription_store_item_id != 0 AND new.is_subscription AND new.cloud_asset_available THEN 50 ELSE ( CASE WHEN new.sync_redownload_params == 'redownload' AND new.sync_id != 0 THEN 20 ELSE ( CASE WHEN new.sync_redownload_params == 'local' AND new.sync_id != 0 THEN 10 ELSE 0 END) END) END) END) END) END) WHERE item_pid = new.item_pid; END;
            
            CREATE TRIGGER IF NOT EXISTS on_update_item_setInMyLibraryColumn AFTER UPDATE OF purchase_history_id, home_sharing_id, sync_id, subscription_store_item_id, store_saga_id, is_ota_purchased, sync_in_my_library, cloud_in_my_library ON item_store BEGIN UPDATE item SET in_my_library = ( CASE WHEN new.home_sharing_id OR (new.store_saga_id AND new.cloud_in_my_library) OR new.purchase_history_id OR (new.sync_id AND new.sync_in_my_library) OR new.is_ota_purchased THEN 1 ELSE 0 END) WHERE item_pid = new.item_pid; END;
            """
        }
        
        let allTriggers = triggerSQL + glassTriggers
        let triggerStatements = allTriggers.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        for statement in triggerStatements {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement + ";", nil, nil, &errMsg) != SQLITE_OK {
                let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                Logger.shared.log("[MediaLibraryBuilder] Trigger warning: \(error)")
            }
        }
    }
    
    
    
    static func insertBaseData(db: OpaquePointer?) throws {
        
        let baseDataSQL = """
        INSERT INTO base_location (base_location_id, path) VALUES (0, '');
        INSERT INTO base_location (base_location_id, path) VALUES (3840, 'iTunes_Control/Music/F00');
        INSERT INTO base_location (base_location_id, path) VALUES (3900, 'iTunes_Control/Ringtones');
        INSERT INTO db_info (db_pid) VALUES (1);
        INSERT INTO genius_config (id, version, default_num_results, min_num_results) VALUES (1, 1, 25, 10);
        INSERT INTO container_seed (container_pid, item_pid, seed_order) VALUES (0, 0, 0);
        INSERT INTO _MLDatabaseProperties (key, value) VALUES ('OrderingLanguage', 'en-US');
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, baseDataSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            throw MediaLibraryError.insertFailed(error)
        }
        
        Logger.shared.log("[MediaLibraryBuilder] Base data inserted")
    }
    
        
}
