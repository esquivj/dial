// Dial/LastFM/ScrobbleBackfill.swift
import Foundation
import GRDB

/// One-time recovery for a window when no Mac scrobbled: queues the counted
/// plays in it that have no scrobble yet, and the app's normal queue sends
/// them (`--backfill-scrobbles <from> --until <to> [--dry-run]`).
///
/// This is the one exception to "Last.fm scrobbles only live plays": it takes
/// `recent` rows and plays merged from another Mac too, because in an outage
/// those are the only record. Each play still has to pass the live rules:
/// a music track with an artist and title, Last.fm's length rule, the
/// 14-day limit, and no scrobble of the same track nearby.
struct ScrobbleBackfill {
  struct Candidate: Equatable {
    let playId: Int64
    let trackUri: String
    let artist: String
    let track: String
    let album: String?
    let durationMs: Int64?
    let playedAt: Int64
  }

  struct Report: Equatable {
    var candidates: [Candidate] = []
    var playsInWindow = 0
    var alreadyScrobbled = 0
    var failsRule = 0
    var missingMetadata = 0
    var tooOld = 0
    var queued = 0

    func summaryLines(dryRun: Bool) -> [String] {
      [
        "→ Counted plays in the window: \(playsInWindow)",
        "→ Already scrobbled (this play or the same track nearby): \(alreadyScrobbled)",
        "→ Skipped: \(failsRule) too short for Last.fm, \(missingMetadata) without artist or title, \(tooOld) older than 14 days",
        dryRun
          ? "✓ Dry run: would queue \(candidates.count) scrobbles. Run again without --dry-run to queue them."
          : "✓ Queued \(queued) scrobbles. Dial sends them the next time it runs.",
      ]
    }
  }

  /// Last.fm refuses scrobbles older than this.
  static let maxAgeSeconds: Int64 = 14 * 24 * 3600

  let dbq: DatabaseQueue
  let from: Int64
  let until: Int64
  let now: Int64

  func plan() throws -> Report {
    var report = Report()
    let rows = try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT p.id, p.track_uri, p.played_at, p.ms_played,
               t.name, t.album_name, t.duration_ms,
               CASE WHEN json_valid(t.artists_json) = 1
                    THEN json_extract(t.artists_json, '$[0].name') END AS artist,
               EXISTS (
                 SELECT 1 FROM lastfm_scrobbles s
                 WHERE s.play_id = p.id
                    OR (s.track_uri = p.track_uri
                        AND abs(s.played_at - p.played_at) < IFNULL(t.duration_ms, p.ms_played) / 1000 + 60)
               ) AS scrobbled
        FROM counted_plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.played_at BETWEEN ? AND ?
          AND p.source IN ('live', 'recent')
        ORDER BY p.played_at, p.id
        """, arguments: [from, until])
    }
    report.playsInWindow = rows.count
    for row in rows {
      let uri: String = row["track_uri"]
      let playedAt: Int64 = row["played_at"]
      let msPlayed: Int64 = row["ms_played"]
      let durationMs: Int64? = row["duration_ms"]
      let artist = (row["artist"] as String?)?.trimmingCharacters(in: .whitespaces) ?? ""
      let name = (row["name"] as String?)?.trimmingCharacters(in: .whitespaces) ?? ""

      if row["scrobbled"] as Bool {
        report.alreadyScrobbled += 1
      } else if playedAt < now - Self.maxAgeSeconds {
        report.tooOld += 1
      } else if !(uri.hasPrefix("spotify:track:") || uri.hasPrefix("spotify:local:"))
                  || !LastFMScrobbleRule.shouldScrobble(
                    positionMs: Int(msPlayed), durationMs: Int(durationMs ?? 0)) {
        report.failsRule += 1
      } else if artist.isEmpty || name.isEmpty {
        report.missingMetadata += 1
      } else {
        let album = (row["album_name"] as String?).flatMap { $0.isEmpty ? nil : $0 }
        report.candidates.append(Candidate(
          playId: row["id"], trackUri: uri, artist: artist, track: name,
          album: album, durationMs: durationMs, playedAt: playedAt))
      }
    }
    return report
  }

  func run(dryRun: Bool) throws -> Report {
    var report = try plan()
    guard !dryRun else { return report }
    report.queued = try ScrobbleQueueDAO(dbq: dbq).enqueueBackfill(report.candidates, now: now)
    return report
  }

  /// `yyyy-MM-dd HH:mm` or `yyyy-MM-ddTHH:mm` in this Mac's time zone.
  static func time(_ text: String) -> Int64? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm"] {
      formatter.dateFormat = format
      if let date = formatter.date(from: text) {
        return Int64(date.timeIntervalSince1970)
      }
    }
    return nil
  }
}
