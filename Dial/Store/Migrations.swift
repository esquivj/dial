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
    return m
  }
}
