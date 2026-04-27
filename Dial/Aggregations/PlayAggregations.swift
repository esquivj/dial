// Dial/Aggregations/PlayAggregations.swift
import GRDB
import Foundation

struct PlayAggregations {
  let dbq: DatabaseQueue
  var now: () -> Int64 = { Int64(Date().timeIntervalSince1970) }

  func plays30d(trackUri: String) throws -> Int {
    let cutoff = now() - 30 * 86_400
    return try dbq.read { db in
      try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND played_at > ?",
        arguments: [trackUri, cutoff]) ?? 0
    }
  }

  /// 1-based rank within last 7d among all tracks played in that window.
  /// Ties broken by most-recent play.
  func rank7d(trackUri: String) throws -> Int? {
    let cutoff = now() - 7 * 86_400
    return try dbq.read { db in
      try Int.fetchOne(db, sql: """
        WITH ranked AS (
          SELECT track_uri, COUNT(*) as c, MAX(played_at) as last
          FROM plays WHERE played_at > ? GROUP BY track_uri
        )
        SELECT rnk FROM (
          SELECT track_uri, ROW_NUMBER() OVER (ORDER BY c DESC, last DESC) as rnk FROM ranked
        ) WHERE track_uri = ?
        """, arguments: [cutoff, trackUri])
    }
  }
}

extension PlayAggregations {
  func firstListen(trackUri: String) throws -> Bool {
    try dbq.read { db in
      let imports = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND source = 'import'",
        arguments: [trackUri]) ?? 0
      let live = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND source = 'live'",
        arguments: [trackUri]) ?? 0
      return imports == 0 && live == 1
    }
  }

  func rediscovered(trackUri: String) throws -> Bool {
    let ninetyDays: Int64 = 90 * 86_400
    let cutoff = now() - ninetyDays
    return try dbq.read { db in
      let previous = try Int64.fetchOne(db,
        sql: "SELECT MAX(played_at) FROM plays WHERE track_uri = ? AND played_at < ?",
        arguments: [trackUri, cutoff])
      return previous != nil
    }
  }

  func onStreak(trackUri: String) throws -> Bool {
    let plays = try plays30d(trackUri: trackUri)
    guard plays >= 10 else { return false }
    guard let r = try rank7d(trackUri: trackUri) else { return false }
    return r <= 5
  }
}

extension PlayAggregations {
  struct SessionPlay: Equatable, Sendable, Hashable {
    let playedAt: Int64
    let trackUri: String
    let msPlayed: Int64
  }

  func last60MinTracks() throws -> [SessionPlay] {
    let cutoff = now() - 3600
    return try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT played_at, track_uri, ms_played FROM plays
        WHERE played_at > ? ORDER BY played_at DESC
      """, arguments: [cutoff]).map { row in
        SessionPlay(playedAt: row["played_at"], trackUri: row["track_uri"], msPlayed: row["ms_played"])
      }
    }
  }

  /// Total all-time plays for an artist (live + import combined).
  /// Joins via `tracks.artists_json[0].uri`; tracks without artist metadata are skipped.
  /// `json_valid` guard skips ~108 rows in the DB with malformed JSON
  /// (unescaped backslashes from imported extended-history data) — without
  /// it, hitting one of those rows mid-query throws "malformed JSON" and
  /// the whole call returns 0, silently breaking the badge.
  func artistLifetimePlays(artistUri: String) throws -> Int {
    try dbq.read { db in
      try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE json_valid(t.artists_json) = 1
          AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [artistUri]) ?? 0
    }
  }

  /// Ranks artists by play count in the last 7d via `tracks.artists_json[0].uri`.
  /// Ties broken by recent play. `json_valid` guard same as `artistLifetimePlays`.
  func artistRank7d(artistUri: String) throws -> Int? {
    let cutoff = now() - 7 * 86_400
    return try dbq.read { db in
      try Int.fetchOne(db, sql: """
        WITH artist_plays AS (
          SELECT json_extract(t.artists_json, '$[0].uri') AS aurl, p.played_at
          FROM plays p JOIN tracks t ON t.uri = p.track_uri
          WHERE p.played_at > ? AND t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
        ),
        ranked AS (
          SELECT aurl, COUNT(*) AS c, MAX(played_at) AS last
          FROM artist_plays GROUP BY aurl
        )
        SELECT rnk FROM (
          SELECT aurl, ROW_NUMBER() OVER (ORDER BY c DESC, last DESC) AS rnk FROM ranked
        ) WHERE aurl = ?
        """, arguments: [cutoff, artistUri])
    }
  }
}
