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
    return m
  }
}
