// Dial/History/Importer.swift
import GRDB
import Foundation

/// Imports a batch of `EndsongRow`s into the local store. Idempotent —
/// duplicate `(played_at, track_uri, ms_played)` rows are skipped.
/// XP is awarded inline (capped at the companion threshold for imports);
/// elder is locked off because it requires 30 days of live use.
/// Synthetic artist record used for imported plays — Spotify's Extended
/// Streaming History export gives us a name but no real artist URI, so
/// we synthesize one from the name. Encoded via `JSONEncoder` (not
/// hand-rolled string interpolation) so the output is always valid JSON.
private struct ImportedArtist: Encodable {
  let name: String
  let uri: String
}

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
        // Use JSONEncoder for the artists JSON to avoid hand-rolled escape
        // bugs — the previous implementation only escaped backslashes and
        // quotes in `name`, leaving the synthetic URI ("artist:Name_With_X")
        // completely unescaped. Any artist name containing characters that
        // require JSON escaping (most commonly backslashes — e.g.
        // "Axwell /\\ Ingrosso") would produce malformed JSON in the URI
        // field, which then cascaded to crash every json_extract query
        // that hit that row (Stats totals, topArtists, pet event detection).
        let artistsJson: String? = r.artistName.flatMap { name in
          let underscoredName = name.replacingOccurrences(of: " ", with: "_")
          let entry = ImportedArtist(name: name, uri: "artist:\(underscoredName)")
          return (try? JSONEncoder().encode([entry])).flatMap {
            String(data: $0, encoding: .utf8)
          }
        }
        try Track(uri: r.trackUri, name: r.trackName, albumName: r.albumName,
                  albumArtUrl: nil, durationMs: nil, artistsJson: artistsJson).mergeUpsert(db)

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
        try BadgeResolver.recordMemories(for: play, mode: .imported, in: db)
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
    var state = try PetStateDAO.singleton(in: db)
    let xpDelta = XPFormula.compute(
      msPlayed: play.msPlayed,
      variety: .none,
      streakDays: 0)

    if state.xp < 25_000 {
      state.xp = min(state.xp + xpDelta, 25_000)   // companion cap on imports
    }
    state.stage = PetStageTable.stage(forXP: state.xp, elderUnlocked: state.elderUnlockedAt != nil)
    try state.update(db)
  }
}
