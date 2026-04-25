// Dial/History/Importer.swift
import GRDB
import Foundation

/// Imports a batch of `EndsongRow`s into the local store. Idempotent —
/// duplicate `(played_at, track_uri, ms_played)` rows are skipped.
/// XP is awarded inline (capped at the companion threshold for imports);
/// elder is locked off because it requires 30 days of live use.
final class Importer {
  private let dbq: DatabaseQueue
  private let engine: PetEngine

  init(dbq: DatabaseQueue, engine: PetEngine) {
    self.dbq = dbq
    self.engine = engine
  }

  @discardableResult
  func importBatch(_ rows: [EndsongRow], sourcePath: String) throws -> Int {
    var inserted = 0
    try dbq.write { db in
      for r in rows {
        // Upsert minimal Track metadata so artistRank7d-style aggregations have something to join.
        let artistsJson: String? = r.artistName.map {
          let safeName = $0
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
          let safeArtistId = $0.replacingOccurrences(of: " ", with: "_")
          return "[{\"name\":\"\(safeName)\",\"uri\":\"artist:\(safeArtistId)\"}]"
        }
        try Track(uri: r.trackUri, name: r.trackName, albumName: r.albumName,
                  albumArtUrl: nil, durationMs: nil, artistsJson: artistsJson).save(db)

        // Insert the play; rely on the unique index `(played_at, track_uri, ms_played)`
        // to reject duplicates. Other DatabaseErrors propagate.
        var play = Play(playedAt: r.playedAt, trackUri: r.trackUri,
                        msPlayed: r.msPlayed, source: "import")
        do {
          try play.insert(db)
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
          continue   // duplicate — skip
        }
        inserted += 1
        try applyXPInTxn(for: play, in: db)
      }
      var entry = ImportLogEntry(
        importedAt: Int64(Date().timeIntervalSince1970),
        sourcePath: sourcePath,
        rowsInserted: Int64(inserted),
        notes: nil)
      try entry.insert(db)
    }
    return inserted
  }

  /// Imported plays award XP at the same per-minute base rate but never get the
  /// variety / streak multipliers (those reflect *live* listening behavior).
  /// Total imported XP is capped at the companion threshold.
  private func applyXPInTxn(for play: Play, in db: Database) throws {
    var state = try PetState.fetchOne(db, key: 1)!
    let day = StreakCalendar.ymd(from: play.playedAt)
    let streak = StreakCalendar().apply(
      playDate: day,
      priorAnchor: state.streakAnchorDate,
      priorDays: state.streakDays)

    let xpDelta = XPFormula.compute(
      msPlayed: play.msPlayed,
      variety: .none,
      streakDays: streak.days)

    state.xp = min(state.xp + xpDelta, 25_000)   // companion cap on imports
    state.streakAnchorDate = streak.anchor
    state.streakDays = streak.days
    state.lastPlayAt = play.playedAt
    state.stage = PetStageTable.stage(forXP: state.xp, elderUnlocked: false)
    try state.update(db)
  }
}
