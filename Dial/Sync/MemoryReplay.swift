// Dial/Sync/MemoryReplay.swift
import Foundation
import GRDB

/// Re-judges memories from a point in time on, the way Dial judged them
/// live (docs/design/multi-mac-history.md, "Replaying memories").
///
/// `BadgeResolver` assumes the play it judges is the newest row, so an old
/// play can't be re-judged in place. In a throwaway copy of the archive the
/// plays from `start` on are removed and recorded again, oldest first, with
/// the calls `PetEngine` and `Importer` make. Plays and their ids in the real
/// archive are never touched.
enum MemoryReplay {
  struct Result {
    var events: [BadgeEvent]
    var playsReplayed: Int
  }

  static func run(on dbq: DatabaseQueue, from start: Int64, scratchURL: URL) throws -> Result {
    try dbq.inDatabase { db in
      try db.execute(sql: "VACUUM INTO ?", arguments: [scratchURL.path])
    }
    let scratch = try DatabaseQueue(path: scratchURL.path)
    defer { try? scratch.close() }
    return try scratch.write { db in
      let plays = try Play.fetchAll(db, sql: """
        SELECT id, played_at, track_uri, ms_played, source
        FROM plays
        WHERE played_at >= ?
        ORDER BY played_at, id
        """, arguments: [start])
      try db.execute(sql: "DELETE FROM badge_events WHERE earned_at >= ?", arguments: [start])
      try db.execute(sql: "DELETE FROM plays WHERE played_at >= ?", arguments: [start])

      for var play in plays {
        try play.insert(db)
        if let mode = try mode(for: play, in: db) {
          try BadgeResolver.recordMemories(for: play, mode: mode, in: db)
        }
      }

      let events = try BadgeEvent.fetchAll(db, sql: """
        SELECT * FROM badge_events WHERE earned_at >= ? ORDER BY earned_at, id
        """, arguments: [start])
      return Result(events: events, playsReplayed: plays.count)
    }
  }

  /// How a play earns memories when it's recorded, or nil when it earns
  /// none: imported skips (as `Importer`) and `recent` rows that are another
  /// row's twin (as `PetEngine`, which never records them).
  static func mode(for play: Play, in db: Database) throws -> BadgeRecordMode? {
    if play.source == "import" {
      return DedupRule.shouldCount(progressMs: Int(play.msPlayed), durationMs: 0) ? .imported : nil
    }
    let counted = try Bool.fetchOne(
      db,
      sql: "SELECT EXISTS (SELECT 1 FROM counted_plays WHERE id = ?)",
      arguments: [play.id]) ?? false
    return counted ? .live : nil
  }
}
