// Dial/Pet/PetEngine.swift
import GRDB
import Foundation
import os.log

private let petLog = Logger(subsystem: "com.dial.Dial", category: "PetEngine")

/// Inserts a `Play` and awards pet XP atomically. Used by:
///  - `PlayRecorder` callsite: live polling counted plays
///  - historical/import flows when they need the same insert/accounting path
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
  ///
  /// **Restart-mid-track dedup** (only for `source: "live"`): the
  /// `PollingService.counted` flag lives in memory and resets on every
  /// app launch. If you quit Dial while a track is playing past the
  /// 30s/50% threshold and reopen mid-track, the new PollingService
  /// instance sees the same track at high progress and fires another
  /// `.countedPlay` — duplicating the play. Detect this case by looking
  /// for an existing live play of the same track within one track-duration
  /// of the current `playedAt`; if present, skip the insert silently.
  /// Replays after the track has finished correctly fall outside the
  /// window (diff ≥ trackDuration) and count normally.
  ///
  /// Imports (`source: "import"`) bypass this check — duplicates there
  /// are already deduped by the unique `(played_at, track_uri, ms_played)`
  /// index on the plays table.
  @discardableResult
  func recordPlay(_ play: Play) throws -> Bool {
    try dbq.write { db in
      if play.source == "live",
         try Self.duplicateLivePlayExists(of: play, in: db) {
        petLog.notice("dedup: skipping duplicate live play for \(play.trackUri, privacy: .public) (mid-track restart)")
        return false
      }
      var p = play
      try p.insert(db)
      let isImport = p.source == "import"
      try BadgeResolver.recordMemories(
        for: p,
        mode: isImport ? .imported : .live,
        in: db)

      var state = try PetState.fetchOne(db, key: 1)!

      let variety = isImport ? VarietyBonus.none : try Self.variety(for: p, in: db)
      let streak: StreakCalendar.Result?
      if isImport {
        streak = nil
      } else {
        let day = StreakCalendar.ymd(from: p.playedAt)
        streak = StreakCalendar().apply(
          playDate: day,
          priorAnchor: state.streakAnchorDate,
          priorDays: state.streakDays)
      }

      let xpDelta = XPFormula.compute(
        msPlayed: p.msPlayed,
        variety: variety,
        streakDays: streak?.days ?? 0)

      let proposed = state.xp + xpDelta
      if isImport {
        if state.xp < importedXPCap {
          state.xp = min(proposed, importedXPCap)
        }
      } else {
        state.xp = proposed
      }

      if let streak {
        state.streakAnchorDate = streak.anchor
        state.streakDays = streak.days
        state.lastPlayAt = p.playedAt
      }

      // Elder unlock: 30 calendar days after install.
      let liveElderUnlocked = !isImport && (clock() - state.installedAt) >= elderLockDays * 86_400
      if liveElderUnlocked, state.elderUnlockedAt == nil { state.elderUnlockedAt = clock() }
      let elderUnlocked = state.elderUnlockedAt != nil || liveElderUnlocked

      let newStage = PetStageTable.stage(forXP: state.xp, elderUnlocked: elderUnlocked)
      if newStage == .hatching, state.hatchedAt == nil { state.hatchedAt = clock() }
      state.stage = newStage

      try state.update(db)
      return true
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

    // newArtist: this play is the only one whose track maps to this artist.
    // `json_valid` guard skips rows with malformed `artists_json` (~108
    // rows in the DB from imported extended-history) — without it, the
    // bad-JSON exception propagates up and the pet's "new artist" XP
    // bonus silently disappears for every play.
    if let au = artistUri {
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id != ? AND json_valid(t.artists_json) = 1
          AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [play.id ?? -1, au]) ?? 0
      if count == 0 { return .newArtist }
    }

    // newAlbum: this play is the only one for tracks with the same (album, artist).
    // Same `json_valid` guard.
    if let albumName = track?.albumName, let artistUri {
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id != ? AND t.album_name = ?
          AND json_valid(t.artists_json) = 1
          AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [play.id ?? -1, albumName, artistUri]) ?? 0
      if count == 0 { return .newAlbum }
    }

    return .none
  }

  /// Returns true if a live play of the same track already exists within
  /// one track-duration of the candidate `play.playedAt`. Used to dedup
  /// the "quit Dial mid-track, reopen" case where the new PollingService's
  /// in-memory `counted` flag flips false and the same playback session
  /// gets counted twice. Threshold = the track's `duration_ms` (in seconds)
  /// when known, else a 600s fallback for unenriched tracks.
  ///
  /// **Why duration as the threshold**: a legitimate replay of the same
  /// track happens AT EARLIEST at `played_at_1 + trackDuration` (the
  /// previous play has to finish before the next can start). A restart
  /// mid-track happens by definition WITHIN one trackDuration of the
  /// previous count. The boundary is exclusive (`played_at > cutoff`)
  /// so back-to-back replays where the diff equals trackDuration
  /// correctly count as two plays.
  private static func duplicateLivePlayExists(of play: Play, in db: Database) throws -> Bool {
    let durationMs = try Int64.fetchOne(
      db,
      sql: "SELECT duration_ms FROM tracks WHERE uri = ?",
      arguments: [play.trackUri]) ?? 0
    let thresholdSec: Int64 = durationMs > 0 ? (durationMs / 1000) : 600
    let cutoff = play.playedAt - thresholdSec
    let row = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM plays
        WHERE track_uri = ? AND source = 'live' AND played_at > ?
        LIMIT 1
        """,
      arguments: [play.trackUri, cutoff])
    return row != nil
  }
}
