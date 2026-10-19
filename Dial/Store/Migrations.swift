// Dial/Store/Migrations.swift
import GRDB
import Foundation

enum Migrations {
  static func register() -> DatabaseMigrator {
    var m = DatabaseMigrator()
    m.registerMigration("v1_initial") { db in
      try db.create(table: "plays") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("played_at", .integer).notNull()
        t.column("track_uri", .text).notNull()
        t.column("ms_played", .integer).notNull()
        t.column("source",    .text).notNull()
        t.uniqueKey(["played_at", "track_uri", "ms_played"])
      }
      try db.create(index: "plays_by_track", on: "plays", columns: ["track_uri", "played_at"])
      try db.create(index: "plays_by_time",  on: "plays", columns: ["played_at"])

      try db.create(table: "tracks") { t in
        t.column("uri", .text).primaryKey()
        t.column("name", .text)
        t.column("album_name", .text)
        t.column("album_art_url", .text)
        t.column("duration_ms", .integer)
        t.column("artists_json", .text)
      }
      try db.create(table: "artists") { t in
        t.column("uri", .text).primaryKey()
        t.column("name", .text)
        t.column("genres_json", .text)
        t.column("image_url", .text)
      }
      try db.create(table: "imports_log") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("imported_at", .integer).notNull()
        t.column("source_path", .text)
        t.column("rows_inserted", .integer)
        t.column("notes", .text)
      }
      try db.create(table: "pet_state") { t in
        t.column("id", .integer).primaryKey().check { $0 == 1 }
        t.column("xp", .integer).notNull().defaults(to: 0)
        t.column("stage", .text).notNull().defaults(to: "egg")
        t.column("hatched_at", .integer)
        t.column("last_play_at", .integer)
        t.column("streak_days", .integer).notNull().defaults(to: 0)
        t.column("streak_anchor_date", .text)
        t.column("elder_unlocked_at", .integer)
        t.column("installed_at", .integer).notNull()
      }
      try db.execute(sql: """
        INSERT INTO pet_state (id, xp, stage, streak_days, installed_at)
        VALUES (1, 0, 'egg', 0, \(Int(Date().timeIntervalSince1970)))
      """)
    }

    // One-time cleanup of duplicate live plays caused by the
    // restart-mid-track bug (PollingService.counted is in-memory and
    // reset to false on every app launch, so quitting + reopening
    // mid-track recorded the same playback session twice). The
    // PetEngine.recordPlay path now dedups going forward; this
    // migration cleans up any duplicates that landed before the fix.
    //
    // A play is a duplicate if another live play of the same track
    // exists within the track's duration (or 600s fallback) BEFORE it.
    // We delete the LATER ones, preserving the earliest count of each
    // playback session as the canonical record. Pet XP that was awarded
    // for the deleted plays stays in pet_state — too risky to unwind
    // streak/XP retroactively for a small accounting drift, and the
    // user's lifetime totals don't meaningfully shift.
    m.registerMigration("v2_dedup_live_plays") { db in
      try db.execute(sql: """
        DELETE FROM plays
        WHERE source = 'live'
          AND id IN (
            SELECT p1.id
            FROM plays p1
            JOIN plays p2 ON p2.track_uri = p1.track_uri AND p2.source = 'live'
            LEFT JOIN tracks t ON t.uri = p1.track_uri
            WHERE p1.source = 'live'
              AND p2.played_at < p1.played_at
              AND p2.played_at > p1.played_at - COALESCE(t.duration_ms / 1000, 600)
          )
      """)
    }

    m.registerMigration("v3_badge_events") { db in
      try db.create(table: "badge_events") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("kind", .text).notNull()
        t.column("category", .text).notNull()
        t.column("track_uri", .text)
        t.column("artist_uri", .text)
        t.column("album_name", .text)
        t.column("earned_at", .integer).notNull()
        t.column("payload_json", .text)
        t.column("scope_key", .text).notNull().unique()
      }
      try db.create(index: "badge_events_by_time", on: "badge_events", columns: ["earned_at"])
      try db.create(index: "badge_events_by_category", on: "badge_events", columns: ["category", "earned_at"])
      try db.create(index: "badge_events_by_kind", on: "badge_events", columns: ["kind", "earned_at"])
    }

    m.registerMigration("v4_pet_trick_unlocks") { db in
      try db.create(table: "pet_trick_unlocks") { t in
        t.column("trick", .text).primaryKey()
        t.column("unlocked_at", .integer).notNull()
        t.column("source_badge", .text)
      }
      try db.create(index: "pet_trick_unlocks_by_time", on: "pet_trick_unlocks", columns: ["unlocked_at"])
    }

    m.registerMigration("v5_tag_intelligence") { db in
      try db.create(table: "raw_tags") { t in
        t.column("entity_uri", .text).notNull()
        t.column("entity_type", .text).notNull()
        t.column("provider", .text).notNull()
        t.column("raw_tag", .text).notNull()
        t.column("score", .double).notNull().defaults(to: 0)
        t.column("rank", .integer).notNull().defaults(to: 0)
        t.column("source_url", .text)
        t.column("fetched_at", .integer).notNull()
        t.primaryKey(["entity_uri", "entity_type", "provider", "raw_tag"])
      }
      try db.create(index: "raw_tags_by_provider", on: "raw_tags", columns: ["provider", "entity_type"])
      try db.create(index: "raw_tags_by_tag", on: "raw_tags", columns: ["raw_tag"])

      try db.create(table: "normalized_tags") { t in
        t.column("entity_uri", .text).notNull()
        t.column("entity_type", .text).notNull()
        t.column("provider", .text).notNull()
        t.column("family", .text).notNull()
        t.column("raw_tag", .text).notNull()
        t.column("score", .double).notNull().defaults(to: 0)
        t.column("updated_at", .integer).notNull()
        t.primaryKey(["entity_uri", "entity_type", "provider", "family", "raw_tag"])
      }
      try db.create(index: "normalized_tags_by_family", on: "normalized_tags", columns: ["family"])
      try db.create(index: "normalized_tags_by_entity", on: "normalized_tags", columns: ["entity_uri", "entity_type"])

      try db.create(table: "tag_enrichment_state") { t in
        t.column("entity_uri", .text).notNull()
        t.column("entity_type", .text).notNull()
        t.column("provider", .text).notNull()
        t.column("status", .text).notNull()
        t.column("fetched_at", .integer).notNull()
        t.column("error", .text)
        t.primaryKey(["entity_uri", "entity_type", "provider"])
      }
      try db.create(index: "tag_state_by_status", on: "tag_enrichment_state", columns: ["provider", "status"])
    }

    m.registerMigration("v6_artifacts") { db in
      try db.create(table: "artifacts") { t in
        t.column("kind", .text).primaryKey()
        t.column("source", .text).notNull()
        t.column("unlocked_at", .integer).notNull()
        t.column("source_badge_event_id", .integer)
        t.column("track_uri", .text)
        t.column("artist_uri", .text)
        t.column("detail", .text)
      }
      try db.create(index: "artifacts_by_time", on: "artifacts", columns: ["unlocked_at"])
      try db.create(index: "artifacts_by_source", on: "artifacts", columns: ["source", "unlocked_at"])
    }

    m.registerMigration("v7_metadata_enrichment_state") { db in
      try db.create(table: "metadata_enrichment_state") { t in
        t.column("entity_uri", .text).notNull()
        t.column("entity_type", .text).notNull()
        t.column("provider", .text).notNull()
        t.column("status", .text).notNull()
        t.column("fetched_at", .integer).notNull()
        t.column("error", .text)
        t.primaryKey(["entity_uri", "entity_type", "provider"])
      }
      try db.create(index: "metadata_state_by_status", on: "metadata_enrichment_state", columns: ["provider", "status"])
    }

    // Imported Spotify history originally used synthetic artist identifiers
    // like `artist:KETTAMA`. Live Spotify playback later supplies canonical
    // IDs like `spotify:artist:...`. Older badge logic compared only exact
    // artist URI, so the first canonical live play could falsely earn
    // "New Artist" even when the normalized artist name already existed in
    // imported history. Clean those false memories once; XP is intentionally
    // not unwound, same as the duplicate-play cleanup above.
    m.registerMigration("v8_cleanup_false_new_artist_badges") { db in
      try db.execute(sql: """
        DELETE FROM badge_events
        WHERE id IN (
          SELECT e.id
          FROM badge_events e
          JOIN tracks event_track ON event_track.uri = e.track_uri
          WHERE e.kind = 'new_artist'
            AND json_valid(event_track.artists_json) = 1
            AND TRIM(json_extract(event_track.artists_json, '$[0].name')) <> ''
            AND EXISTS (
              SELECT 1
              FROM plays prior_play
              JOIN tracks prior_track ON prior_track.uri = prior_play.track_uri
              WHERE prior_play.played_at < e.earned_at
                AND json_valid(prior_track.artists_json) = 1
                AND LOWER(TRIM(json_extract(prior_track.artists_json, '$[0].name'))) =
                    LOWER(TRIM(json_extract(event_track.artists_json, '$[0].name')))
            )
        )
      """)

      if try db.tableExists("artifacts") {
        try db.execute(sql: """
          UPDATE artifacts
          SET source_badge_event_id = NULL
          WHERE source_badge_event_id IS NOT NULL
            AND source_badge_event_id NOT IN (SELECT id FROM badge_events)
        """)
      }
    }

    m.registerMigration("v9_weekly_memories") { db in
      try db.create(table: "weekly_memories") { t in
        t.column("week_start", .integer).primaryKey()
        t.column("week_end", .integer).notNull()
        t.column("trait", .text).notNull()
        t.column("memento", .text).notNull()
        t.column("recap_line", .text).notNull()
        t.column("room_object_name", .text).notNull()
        t.column("dominant_genre", .text)
        t.column("theme", .text).notNull()
        t.column("play_count", .integer).notNull()
        t.column("listening_ms", .integer).notNull()
        t.column("unique_artists", .integer).notNull()
        t.column("new_artists", .integer).notNull()
        t.column("created_at", .integer).notNull()
        t.column("updated_at", .integer).notNull()
      }
      try db.create(index: "weekly_memories_by_week_end", on: "weekly_memories", columns: ["week_end"])

      try db.alter(table: "artifacts") { t in
        t.add(column: "source_week_start", .integer)
      }
      try db.create(index: "artifacts_by_week", on: "artifacts", columns: ["source_week_start"])
    }

    m.registerMigration("v10_recent_play_sync_state") { db in
      try db.create(table: "recent_play_sync_state") { t in
        t.column("id", .integer).primaryKey().check { $0 == 1 }
        t.column("last_played_at_ms", .integer).notNull().defaults(to: 0)
        t.column("last_synced_at", .integer).notNull()
      }
    }

    m.registerMigration("v11_recent_play_sync_health") { db in
      try db.alter(table: "recent_play_sync_state") { t in
        t.add(column: "last_response_count", .integer).notNull().defaults(to: 0)
        t.add(column: "last_response_saturated", .integer).notNull().defaults(to: 0)
        t.add(column: "consecutive_saturated", .integer).notNull().defaults(to: 0)
        t.add(column: "last_inserted_count", .integer).notNull().defaults(to: 0)
      }
    }

    m.registerMigration("v12_reclassify_rock_hybrid_tags") { db in
      try db.execute(sql: """
        UPDATE normalized_tags
        SET family = CASE
          WHEN LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%dance punk%' THEN 'punk/emo'
          WHEN LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%garage rock%' THEN 'rock'
          WHEN LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%dance rock%' THEN 'rock'
          WHEN LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%new wave%' THEN 'rock'
          ELSE family
        END
        WHERE family = 'electronic'
          AND (
            LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%dance punk%'
            OR LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%garage rock%'
            OR LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%dance rock%'
            OR LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%new wave%'
          )
      """)
    }

    m.registerMigration("v13_reclassify_new_wave_tags") { db in
      try db.execute(sql: """
        UPDATE normalized_tags
        SET family = 'rock'
        WHERE family NOT IN ('metal', 'punk/emo')
          AND LOWER(REPLACE(raw_tag, '-', ' ')) LIKE '%new wave%'
      """)
    }

    // First Listen should be high-confidence. If the exact track was missing
    // from the export but the artist or album is already clearly present, the
    // app should not preserve a "No plays in your history" memory. Leave XP
    // alone, same as the earlier cleanup migrations.
    m.registerMigration("v14_cleanup_false_first_listen_badges_for_known_catalog") { db in
      try db.execute(sql: """
        CREATE TEMP TABLE track_catalog_identity AS
        SELECT uri,
               LOWER(TRIM(json_extract(artists_json, '$[0].name'))) AS artist_name,
               LOWER(TRIM(album_name)) AS album_name
        FROM tracks
        WHERE artists_json IS NOT NULL
          AND json_valid(artists_json) = 1
          AND TRIM(json_extract(artists_json, '$[0].name')) <> '';

        CREATE INDEX temp.track_catalog_identity_by_uri ON track_catalog_identity(uri);
        CREATE INDEX temp.track_catalog_identity_by_artist ON track_catalog_identity(artist_name);
        CREATE INDEX temp.track_catalog_identity_by_album ON track_catalog_identity(artist_name, album_name);

        CREATE TEMP TABLE first_listen_candidates AS
        SELECT e.id,
               e.earned_at,
               i.artist_name,
               i.album_name
        FROM badge_events e
        JOIN track_catalog_identity i ON i.uri = e.track_uri
        WHERE e.kind = 'first_listen';

        CREATE INDEX temp.first_listen_candidates_by_artist ON first_listen_candidates(artist_name);
        CREATE INDEX temp.first_listen_candidates_by_album ON first_listen_candidates(artist_name, album_name);

        CREATE TEMP TABLE false_first_listen_badge_ids (id INTEGER PRIMARY KEY);

        INSERT OR IGNORE INTO false_first_listen_badge_ids (id)
        SELECT c.id
        FROM first_listen_candidates c
        JOIN track_catalog_identity i ON i.artist_name = c.artist_name
        JOIN plays prior_play ON prior_play.track_uri = i.uri
        WHERE prior_play.played_at < c.earned_at
        GROUP BY c.id
        HAVING COUNT(*) >= 20;

        INSERT OR IGNORE INTO false_first_listen_badge_ids (id)
        SELECT c.id
        FROM first_listen_candidates c
        JOIN track_catalog_identity i
          ON i.artist_name = c.artist_name
         AND i.album_name = c.album_name
        JOIN plays prior_play ON prior_play.track_uri = i.uri
        WHERE c.album_name IS NOT NULL
          AND c.album_name <> ''
          AND prior_play.played_at < c.earned_at
        GROUP BY c.id
        HAVING COUNT(*) >= 3;

        DELETE FROM badge_events
        WHERE id IN (SELECT id FROM false_first_listen_badge_ids);

        DROP TABLE false_first_listen_badge_ids;
        DROP TABLE first_listen_candidates;
        DROP TABLE track_catalog_identity;
      """)

      if try db.tableExists("artifacts") {
        try db.execute(sql: """
          UPDATE artifacts
          SET source_badge_event_id = NULL
          WHERE source_badge_event_id IS NOT NULL
            AND source_badge_event_id NOT IN (SELECT id FROM badge_events)
        """)
      }
    }

    m.registerMigration("v15_artist_identity_aliases") { db in
      try ArtistIdentityRepair.rebuildAliases(in: db)
    }

    // Stats, ranks and badges read `counted_plays`, which applies the live
    // DedupRule (>=30s or >=50% of a known duration) to imported streaming
    // history. Skips stay in `plays` untouched; only what counts changes.
    m.registerMigration("v16_counted_plays_view") { db in
      try db.execute(sql: """
        CREATE VIEW counted_plays AS
        SELECT p.*
        FROM plays p
        WHERE p.source != 'import'
           OR p.ms_played >= 30000
           OR EXISTS (
             SELECT 1 FROM tracks t
             WHERE t.uri = p.track_uri
               AND t.duration_ms > 0
               AND p.ms_played * 2 >= t.duration_ms)
        """)
    }

    // Last.fm scrobble queue. One row per live play (`play_id` is unique),
    // so a play can't be queued or sent twice, even across relaunches.
    // Rows stay after sending as the "last scrobbled" record.
    m.registerMigration("v17_lastfm_scrobble_queue") { db in
      try db.create(table: "lastfm_scrobbles") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("play_id", .integer).notNull().unique()
          .references("plays", onDelete: .cascade)
        t.column("track_uri", .text).notNull()
        t.column("artist", .text).notNull()
        t.column("track", .text).notNull()
        t.column("album", .text)
        t.column("duration_ms", .integer)
        t.column("played_at", .integer).notNull()
        t.column("queued_at", .integer).notNull()
        // pending | sent | ignored
        t.column("state", .text).notNull().defaults(to: "pending")
        t.column("attempts", .integer).notNull().defaults(to: 0)
        t.column("next_attempt_at", .integer).notNull().defaults(to: 0)
        t.column("last_error", .text)
        t.column("sent_at", .integer)
      }
      try db.create(
        index: "lastfm_scrobbles_by_state",
        on: "lastfm_scrobbles",
        columns: ["state", "next_attempt_at", "played_at"])
    }

    // Before the inclusive window in `PetEngine.duplicateRecentSyncPlayExists`,
    // a recently-played row whose live twin started exactly one duration
    // (or a few seconds more) before it was inserted as a second play.
    // Those rows stay in `plays`; this hides them from `counted_plays` using
    // the same window as the engine (duration, min 30 s, 600 s if unknown,
    // plus `PetEngine.recentTwinToleranceSec` = 5 s on the early side).
    m.registerMigration("v18_counted_plays_hide_recent_twins") { db in
      try db.execute(sql: """
        DROP VIEW counted_plays;
        CREATE VIEW counted_plays AS
        SELECT p.*
        FROM plays p
        WHERE (p.source != 'import'
           OR p.ms_played >= 30000
           OR EXISTS (
             SELECT 1 FROM tracks t
             WHERE t.uri = p.track_uri
               AND t.duration_ms > 0
               AND p.ms_played * 2 >= t.duration_ms))
          AND (p.source != 'recent'
           OR NOT EXISTS (
             SELECT 1 FROM plays l
             LEFT JOIN tracks tw ON tw.uri = p.track_uri
             WHERE l.track_uri = p.track_uri
               AND l.source != 'recent'
               AND l.played_at >= p.played_at - 5 - (
                 CASE WHEN tw.duration_ms > 0 THEN max(30, tw.duration_ms / 1000) ELSE 600 END)
               AND l.played_at < p.played_at + (
                 CASE WHEN tw.duration_ms > 0 THEN max(30, tw.duration_ms / 1000) ELSE 600 END)))
        """)
    }
    return m
  }
}
