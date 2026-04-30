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

  func playsYTD(trackUri: String) throws -> Int {
    let cutoff = Self.startOfYearEpoch(for: now())
    return try dbq.read { db in
      try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND played_at >= ?",
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

  func lastPlayedAt(trackUri: String, before currentPlayAt: Int64? = nil) throws -> Int64? {
    let upperBound = currentPlayAt ?? now()
    return try dbq.read { db in
      try Int64.fetchOne(db, sql: """
        SELECT played_at
        FROM plays
        WHERE track_uri = ?
          AND played_at < ?
        ORDER BY played_at DESC, id DESC
        LIMIT 1
        """, arguments: [trackUri, upperBound])
    }
  }
}

private extension PlayAggregations {
  static func startOfYearEpoch(for epoch: Int64) -> Int64 {
    let date = Date(timeIntervalSince1970: TimeInterval(epoch))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let components = calendar.dateComponents([.year], from: date)
    let start = calendar.date(from: components) ?? date
    return Int64(start.timeIntervalSince1970)
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
    let anchor = now()
    return try dbq.read { db in
      let recentRediscovery = try Int.fetchOne(db, sql: """
        SELECT 1
        FROM badge_events
        WHERE track_uri = ?
          AND kind = ?
          AND earned_at >= ?
        LIMIT 1
        """, arguments: [
          trackUri,
          BadgeMemoryKind.rediscovered.rawValue,
          anchor - 24 * 60 * 60,
        ])
      if recentRediscovery != nil { return true }

      let latest = try Int64.fetchAll(db, sql: """
        SELECT played_at
        FROM plays
        WHERE track_uri = ?
        ORDER BY played_at DESC, id DESC
        LIMIT 2
        """, arguments: [trackUri])

      if latest.count >= 2 {
        let latestPlay = latest[0]
        let priorPlay = latest[1]
        if latestPlay >= anchor - 24 * 60 * 60,
           latestPlay - priorPlay >= ninetyDays {
          return true
        }
      }

      if let lastKnownPlay = latest.first {
        return anchor - lastKnownPlay >= ninetyDays
      }

      return false
    }
  }

  func onStreak(trackUri: String) throws -> Bool {
    let plays = try plays30d(trackUri: trackUri)
    guard plays >= 10 else { return false }
    guard let r = try rank7d(trackUri: trackUri) else { return false }
    return r <= 5
  }

  func currentBadgeInsight(trackUri: String, currentPlayAt: Int64?) throws -> BadgeInsight? {
    let anchorAt = currentPlayAt ?? now()
    return try dbq.read { db in
      try BadgeResolver.currentInsight(
        trackUri: trackUri,
        anchorAt: anchorAt,
        countedCurrentPlay: currentPlayAt != nil,
        in: db)
    }
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

  /// Total all-time plays for an artist (live + import combined). Imported
  /// history can use synthetic IDs like `artist:KETTAMA` while live playback
  /// uses canonical Spotify IDs, so artist identity falls back to normalized
  /// display name when available.
  /// `json_valid` guard skips ~108 rows in the DB with malformed JSON
  /// (unescaped backslashes from imported extended-history data) — without
  /// it, hitting one of those rows mid-query throws "malformed JSON" and
  /// the whole call returns 0, silently breaking the badge.
  func artistLifetimePlays(artistUri: String) throws -> Int {
    try dbq.read { db in
      try Int.fetchOne(db, sql: """
        WITH target AS (
          SELECT COALESCE(
            (
              SELECT NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), '')
              FROM tracks t
              WHERE json_valid(t.artists_json) = 1
                AND json_extract(t.artists_json, '$[0].uri') = ?
              LIMIT 1
            ),
            ?
          ) AS artist_key
        )
        SELECT COUNT(*)
        FROM plays p
        JOIN tracks t ON t.uri = p.track_uri
        WHERE json_valid(t.artists_json) = 1
          AND COALESCE(
            NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), ''),
            json_extract(t.artists_json, '$[0].uri')
          ) = (SELECT artist_key FROM target)
      """, arguments: [artistUri, artistUri]) ?? 0
    }
  }

  /// Ranks artists by play count in the last 7d using the same normalized
  /// identity key as `artistLifetimePlays`.
  /// Ties broken by recent play. `json_valid` guard same as `artistLifetimePlays`.
  func artistRank7d(artistUri: String) throws -> Int? {
    let cutoff = now() - 7 * 86_400
    return try dbq.read { db in
      try Int.fetchOne(db, sql: """
        WITH target AS (
          SELECT COALESCE(
            (
              SELECT NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), '')
              FROM tracks t
              WHERE json_valid(t.artists_json) = 1
                AND json_extract(t.artists_json, '$[0].uri') = ?
              LIMIT 1
            ),
            ?
          ) AS artist_key
        ),
        artist_plays AS (
          SELECT COALESCE(
                   NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), ''),
                   json_extract(t.artists_json, '$[0].uri')
                 ) AS artist_key,
                 p.played_at
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
          WHERE p.played_at > ?
            AND t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
        ),
        ranked AS (
          SELECT artist_key, COUNT(*) AS c, MAX(played_at) AS last
          FROM artist_plays GROUP BY artist_key
        )
        SELECT rnk FROM (
          SELECT artist_key, ROW_NUMBER() OVER (ORDER BY c DESC, last DESC) AS rnk FROM ranked
        ) WHERE artist_key = (SELECT artist_key FROM target)
        """, arguments: [artistUri, artistUri, cutoff])
    }
  }
}
