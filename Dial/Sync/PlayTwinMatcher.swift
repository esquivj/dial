// Dial/Sync/PlayTwinMatcher.swift
import GRDB

/// Decides when two `plays` rows of the same track are one listen, so a
/// merge never doubles a listen two Macs both recorded
/// (docs/design/multi-mac-history.md, "Twins").
///
/// Each source stamps a play differently. A `live` row carries an estimated
/// start; `recent` and `import` rows carry the time the play ended. Two Macs
/// that both counted a listen live hold two rows a few seconds apart, which
/// the unique `(played_at, track_uri, ms_played)` index can't see.
enum PlayTwinMatcher {
  struct Stamp: Equatable {
    let playedAt: Int64
    let msPlayed: Int64
    let source: String
  }

  /// True when `a` and `b`, two rows of the same track, are the same listen.
  /// `durationMs` is the track's length, if known.
  static func isSameListen(_ a: Stamp, _ b: Stamp, durationMs: Int64?) -> Bool {
    if a.playedAt == b.playedAt, a.msPlayed == b.msPlayed { return true }
    switch (Kind(a.source), Kind(b.source)) {
    case (.live, .live):
      return abs(a.playedAt - b.playedAt) < liveToleranceSec(durationMs: durationMs)
    case (.recent, .recent), (.imported, .imported):
      // The same fetch or export always gives the same row: exact key only.
      return false
    case (.recent, _):
      return inRecentWindow(recentAt: a.playedAt, otherAt: b.playedAt, durationMs: durationMs)
    case (_, .recent):
      return inRecentWindow(recentAt: b.playedAt, otherAt: a.playedAt, durationMs: durationMs)
    case (.imported, .live):
      return importMatchesLive(a, liveStart: b.playedAt, durationMs: durationMs)
    case (.live, .imported):
      return importMatchesLive(b, liveStart: a.playedAt, durationMs: durationMs)
    }
  }

  /// Whether `schema.plays` holds a row of `trackUri` that is the same
  /// listen as `stamp`. `schema` is "main" or an attached database's name.
  static func twinExists(
    of stamp: Stamp,
    trackUri: String,
    durationMs: Int64?,
    in schema: String,
    db: Database
  ) throws -> Bool {
    let reach = searchReachSec(stamp: stamp, durationMs: durationMs)
    let rows = try Row.fetchCursor(db, sql: """
      SELECT played_at, ms_played, source
      FROM \(schema).plays
      WHERE track_uri = ? AND played_at BETWEEN ? AND ?
      """, arguments: [trackUri, stamp.playedAt - reach, stamp.playedAt + reach])
    while let row = try rows.next() {
      let other = Stamp(playedAt: row["played_at"], msPlayed: row["ms_played"], source: row["source"])
      if isSameListen(stamp, other, durationMs: durationMs) { return true }
    }
    return false
  }

  // MARK: - Rules

  private enum Kind {
    case live, recent, imported

    init(_ source: String) {
      switch source {
      case RecentPlaysReconciler.source: self = .recent
      case "import": self = .imported
      default: self = .live
      }
    }
  }

  /// Two Macs' start estimates for one live listen land seconds apart. A
  /// replay starts a whole track later, so half the length (at most a
  /// minute) separates the two cases, back-to-back repeats included.
  static func liveToleranceSec(durationMs: Int64?) -> Int64 {
    let seconds = durationSec(durationMs) ?? 600
    return min(60, max(1, seconds / 2))
  }

  /// The v18 `counted_plays` window: a `recent` row (stamped when the play
  /// ended) and any other row of the same listen, matched exactly as
  /// `counted_plays` and `PetEngine` match them.
  private static func inRecentWindow(recentAt: Int64, otherAt: Int64, durationMs: Int64?) -> Bool {
    let window = durationSec(durationMs).map { max(30, $0) } ?? 600
    return otherAt >= recentAt - window - PetEngine.recentTwinToleranceSec
      && otherAt < recentAt + window
  }

  /// An export row is stamped when the stream stopped and measures the time
  /// listened, so its listen started `ms_played` before its stamp. Skips the
  /// counting rule drops are never anyone's twin.
  private static func importMatchesLive(_ imported: Stamp, liveStart: Int64, durationMs: Int64?) -> Bool {
    let counted = imported.msPlayed >= 30_000
      || (durationMs.map { $0 > 0 && imported.msPlayed * 2 >= $0 } ?? false)
    guard counted else { return false }
    let start = imported.playedAt - imported.msPlayed / 1000
    return abs(liveStart - start) < liveToleranceSec(durationMs: durationMs)
  }

  private static func durationSec(_ durationMs: Int64?) -> Int64? {
    guard let durationMs, durationMs > 0 else { return nil }
    return durationMs / 1000
  }

  /// How far either side of `stamp` a twin can sit, for the indexed lookup.
  /// Generous on purpose: `isSameListen` makes the real decision.
  private static func searchReachSec(stamp: Stamp, durationMs: Int64?) -> Int64 {
    let track = max(durationSec(durationMs) ?? 600, 600)
    return max(3 * track, stamp.msPlayed / 1000) + 60
  }
}
