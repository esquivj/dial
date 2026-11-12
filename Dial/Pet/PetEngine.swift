// Dial/Pet/PetEngine.swift
import GRDB
import Foundation
import os.log

private let petLog = Logger(subsystem: "com.dial.Dial", category: "PetEngine")

/// Inserts a `Play` and awards pet XP atomically. Used by:
///  - `AppCoordinator`: live polling counted plays (source "live")
///  - `RecentPlaysReconciler`: plays recovered from Spotify's recently-played list (source "recent")
/// Streaming-history imports do not come through here; `Importer` inserts rows directly.
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
  /// Recently-played gap sync (`source: "recent"`) uses a similar but
  /// cross-source check: if Dial already saw a live/imported play for the
  /// same track inside the track-duration window, the API row is just repair
  /// noise and should not double-count.
  ///
  /// Imports (`source: "import"`) never reach this method — `Importer` inserts
  /// directly and relies on the unique `(played_at, track_uri, ms_played)` index
  /// on the plays table for dedup.
  @discardableResult
  func recordPlay(_ play: Play) throws -> Bool {
    try dbq.write { db in
      if play.source == "live",
         try Self.duplicateLivePlayExists(of: play, in: db) {
        petLog.notice("dedup: skipping duplicate live play for \(play.trackUri, privacy: .public) (mid-track restart)")
        return false
      }
      if play.source == RecentPlaysReconciler.source,
         try Self.duplicateRecentSyncPlayExists(of: play, in: db) {
        petLog.notice("dedup: skipping duplicate recent-play sync row for \(play.trackUri, privacy: .public)")
        return false
      }
      var p = play
      try p.insert(db)
      let isImport = p.source == "import"
      try BadgeResolver.recordMemories(
        for: p,
        mode: isImport ? .imported : .live,
        in: db)

      var state = try PetStateDAO.singleton(in: db)

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
    let artist: ArtistEntry? = {
      guard let json = track?.artistsJson?.data(using: .utf8) else { return nil }
      return (try? JSONDecoder().decode([ArtistEntry].self, from: json))?.first
    }()

    // newArtist: this play is the only one whose track maps to this artist.
    // `json_valid` guard skips rows with malformed `artists_json` (~108
    // rows in the DB from imported extended-history) — without it, the
    // bad-JSON exception propagates up and the pet's "new artist" XP
    // bonus silently disappears for every play.
    if let artist {
      let count = try priorArtistPlayCount(excludingPlayID: play.id, artist: artist, in: db)
      if count == 0 { return .newArtist }
    }

    // newAlbum: this play is the only one for tracks with the same (album, artist).
    // Same `json_valid` guard.
    if let albumName = track?.albumName, let artist {
      let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id != ? AND t.album_name = ?
          AND json_valid(t.artists_json) = 1
          AND (
            (? IS NOT NULL AND json_extract(t.artists_json, '$[0].uri') = ?)
            OR
            (? IS NOT NULL AND LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))) = ?)
          )
      """, arguments: [
        play.id ?? -1,
        albumName,
        artist.uri,
        artist.uri,
        artist.normalizedName,
        artist.normalizedName,
      ]) ?? 0
      if count == 0 { return .newAlbum }
    }

    return .none
  }

  private static func priorArtistPlayCount(
    excludingPlayID playID: Int64?,
    artist: ArtistEntry,
    in db: Database
  ) throws -> Int {
    try Int.fetchOne(db, sql: """
      SELECT COUNT(*)
      FROM plays p
      JOIN tracks t ON t.uri = p.track_uri
      WHERE p.id != ?
        AND json_valid(t.artists_json) = 1
        AND (
          (? IS NOT NULL AND json_extract(t.artists_json, '$[0].uri') = ?)
          OR
          (? IS NOT NULL AND LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))) = ?)
        )
    """, arguments: [
      playID ?? -1,
      artist.uri,
      artist.uri,
      artist.normalizedName,
      artist.normalizedName,
    ]) ?? 0
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

  /// The window, in seconds, that one recently-played row covers: the
  /// track's length (at least 30 s), or 600 s when the length is unknown.
  static func recentTwinWindowSec(durationMs: Int64?) -> Int64 {
    guard let durationMs, durationMs > 0 else { return 600 }
    return max(30, durationMs / 1000)
  }

  /// Slack for matching a recently-played row to its live twin. Spotify's
  /// `played_at` is when the play *ended*; a live row stores the estimated
  /// *start* (`now - progress`, to the second). For a full play the two sit
  /// about one track-duration apart. Most land within 10 s of that, but
  /// Spotify often stamps the end 10–60 s late (measured on a real archive,
  /// Nov 2026), so the slack is 60 s.
  ///
  /// It stays under half the track's length, so the play before a
  /// back-to-back repeat (a full duration earlier) never matches.
  static func recentTwinToleranceSec(windowSec: Int64) -> Int64 {
    min(60, windowSec / 2)
  }

  /// A recently-played row closer than this to the end of an earlier
  /// recently-played row of the same track wasn't a new full play: Spotify
  /// lists a restart or scrub-back as another entry.
  static let recentRepeatSlackSec: Int64 = 10

  /// Returns true if the recently-played row is already covered:
  ///  - a live or imported play of the same track sits within one
  ///    track-duration of it (plus the early-side tolerance, because live
  ///    rows are start-stamped and recent rows end-stamped);
  ///  - the same, for the same song under another track id (Spotify
  ///    relinking): same title and first artist, case and spacing aside;
  ///  - or an earlier recently-played row of the same track ended less than
  ///    one track-duration before it.
  ///
  /// `counted_plays` (v20) applies the same three rules to rows already in
  /// the archive. Change both together.
  private static func duplicateRecentSyncPlayExists(of play: Play, in db: Database) throws -> Bool {
    let durationMs = try Int64.fetchOne(
      db,
      sql: "SELECT duration_ms FROM tracks WHERE uri = ?",
      arguments: [play.trackUri])
    let window = recentTwinWindowSec(durationMs: durationMs)
    let lower = play.playedAt - window - recentTwinToleranceSec(windowSec: window)
    let upper = play.playedAt + window
    let recent = RecentPlaysReconciler.source

    let sameTrack = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM plays
        WHERE track_uri = ?
          AND source != ?
          AND played_at >= ?
          AND played_at < ?
        LIMIT 1
        """,
      arguments: [play.trackUri, recent, lower, upper])
    if sameTrack != nil { return true }

    let relinked = try Int.fetchOne(
      db,
      sql: """
        SELECT 1
        FROM tracks tp
        JOIN plays l ON l.played_at >= ? AND l.played_at < ?
        JOIN tracks tl ON tl.uri = l.track_uri
        WHERE tp.uri = ?
          AND l.track_uri != tp.uri
          AND l.source != ?
          AND tp.name IS NOT NULL AND TRIM(tp.name) != ''
          AND LOWER(TRIM(tl.name)) = LOWER(TRIM(tp.name))
          AND json_valid(tp.artists_json) = 1
          AND json_valid(tl.artists_json) = 1
          AND LOWER(TRIM(json_extract(tl.artists_json, '$[0].name')))
            = LOWER(TRIM(json_extract(tp.artists_json, '$[0].name')))
        LIMIT 1
        """,
      arguments: [lower, upper, play.trackUri, recent])
    if relinked != nil { return true }

    let restart = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM plays
        WHERE track_uri = ?
          AND source = ?
          AND played_at > ?
          AND played_at < ?
        LIMIT 1
        """,
      arguments: [play.trackUri, recent, play.playedAt - window + recentRepeatSlackSec, play.playedAt])
    return restart != nil
  }
}

private struct ArtistEntry: Decodable {
  let name: String
  let uri: String

  var normalizedName: String? {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
  }
}
