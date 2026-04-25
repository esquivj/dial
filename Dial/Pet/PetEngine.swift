// Dial/Pet/PetEngine.swift
import GRDB
import Foundation

/// Inserts a `Play` and awards pet XP atomically. Used by:
///  - `PlayRecorder` callsite: live polling counted plays
///  - `Importer`:               imported history (with the companion XP cap)
final class PetEngine {
  private let dbq: DatabaseQueue
  private let clock: () -> Int64
  private let elderLockDays: Int64 = 30
  private let importedXPCap: Int64 = 25_000     // cap at companion threshold

  init(dbq: DatabaseQueue, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
    self.dbq = dbq
    self.clock = clock
  }

  /// Insert the play and update pet state in one write transaction.
  func recordPlay(_ play: Play) throws {
    try dbq.write { db in
      var p = play
      try p.insert(db)

      var state = try PetState.fetchOne(db, key: 1)!

      let variety = try Self.variety(for: p, in: db)
      let day = StreakCalendar.ymd(from: p.playedAt)
      let streak = StreakCalendar().apply(
        playDate: day,
        priorAnchor: state.streakAnchorDate,
        priorDays: state.streakDays)

      let xpDelta = XPFormula.compute(
        msPlayed: p.msPlayed,
        variety: variety,
        streakDays: streak.days)

      let proposed = state.xp + xpDelta
      if p.source == "import" {
        state.xp = min(proposed, importedXPCap)
      } else {
        state.xp = proposed
      }

      state.streakAnchorDate = streak.anchor
      state.streakDays = streak.days
      state.lastPlayAt = p.playedAt

      // Elder unlock: 30 calendar days after install.
      let elderUnlocked = (clock() - state.installedAt) >= elderLockDays * 86_400
      if elderUnlocked, state.elderUnlockedAt == nil { state.elderUnlockedAt = clock() }

      let newStage = PetStageTable.stage(forXP: state.xp, elderUnlocked: elderUnlocked)
      if newStage == .hatching, state.hatchedAt == nil { state.hatchedAt = clock() }
      state.stage = newStage

      try state.update(db)
    }
  }

  /// Determines variety bonus by checking whether *prior* plays exist for the
  /// same artist/album. Runs inside the same transaction the play was just inserted into.
  private static func variety(for play: Play, in db: Database) throws -> VarietyBonus {
    let track = try Track.fetchOne(db, key: play.trackUri)
    let artistUri: String? = {
      guard let json = track?.artistsJson?.data(using: .utf8) else { return nil }
      struct A: Decodable { let uri: String }
      return (try? JSONDecoder().decode([A].self, from: json))?.first?.uri
    }()

    // newArtist: this play is the only one whose track maps to this artist
    if let au = artistUri {
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id != ? AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [play.id ?? -1, au]) ?? 0
      if count == 0 { return .newArtist }
    }

    // newAlbum: this play is the only one for tracks with the same (album, artist)
    if let albumName = track?.albumName, let artistUri {
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id != ? AND t.album_name = ? AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [play.id ?? -1, albumName, artistUri]) ?? 0
      if count == 0 { return .newAlbum }
    }

    return .none
  }
}
