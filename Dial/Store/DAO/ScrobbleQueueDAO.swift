// Dial/Store/DAO/ScrobbleQueueDAO.swift
import GRDB
import Foundation

struct QueuedScrobble: Equatable {
  let id: Int64
  let playId: Int64
  let trackUri: String
  let entry: LastFMScrobbleEntry
  let attempts: Int
}

struct LastScrobble: Equatable {
  let artist: String
  let track: String
  let sentAt: Int64
}

/// The `lastfm_scrobbles` queue (migration v17).
struct ScrobbleQueueDAO {
  let dbq: DatabaseQueue

  /// Queues one play. Only `live` plays recorded on this Mac qualify:
  /// imported history, recently-played sync rows and plays merged in from
  /// another Mac's archive (`origin` set) are never scrobbled. Returns false
  /// when the play doesn't qualify or is already queued.
  @discardableResult
  func enqueue(
    playId: Int64,
    artist: String,
    track: String,
    album: String?,
    durationMs: Int64?,
    now: Int64
  ) throws -> Bool {
    try dbq.write { db in
      try db.execute(sql: """
        INSERT OR IGNORE INTO lastfm_scrobbles
          (play_id, track_uri, artist, track, album, duration_ms, played_at, queued_at)
        SELECT p.id, p.track_uri, ?, ?, ?, ?, p.played_at, ?
        FROM plays p
        WHERE p.id = ? AND p.source = 'live' AND p.origin IS NULL
        """, arguments: [artist, track, album, durationMs, now, playId])
      return db.changesCount > 0
    }
  }

  /// The id of the live play recorded for this start time, track and length.
  func livePlayId(playedAt: Int64, trackUri: String, msPlayed: Int64) throws -> Int64? {
    try dbq.read { db in
      try Int64.fetchOne(db, sql: """
        SELECT id FROM plays
        WHERE played_at = ? AND track_uri = ? AND ms_played = ? AND source = 'live'
        """, arguments: [playedAt, trackUri, msPlayed])
    }
  }

  /// Oldest pending rows that are due, up to `limit`.
  func due(now: Int64, limit: Int) throws -> [QueuedScrobble] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT id, play_id, track_uri, artist, track, album, duration_ms, played_at, attempts
        FROM lastfm_scrobbles
        WHERE state = 'pending' AND next_attempt_at <= ?
        ORDER BY played_at, id
        LIMIT ?
        """, arguments: [now, limit])
      .map { row in
        QueuedScrobble(
          id: row["id"],
          playId: row["play_id"],
          trackUri: row["track_uri"],
          entry: LastFMScrobbleEntry(
            artist: row["artist"],
            track: row["track"],
            album: row["album"],
            durationMs: row["duration_ms"],
            timestamp: row["played_at"]),
          attempts: row["attempts"])
      }
    }
  }

  func markSent(ids: [Int64], now: Int64) throws {
    guard !ids.isEmpty else { return }
    try dbq.write { db in
      try db.execute(
        sql: "UPDATE lastfm_scrobbles SET state = 'sent', sent_at = ?, last_error = NULL WHERE id IN \(Self.placeholders(ids.count))",
        arguments: StatementArguments(([now] + ids).map { $0 as DatabaseValueConvertible? }))
    }
  }

  func markIgnored(id: Int64, reason: String) throws {
    try dbq.write { db in
      try db.execute(
        sql: "UPDATE lastfm_scrobbles SET state = 'ignored', last_error = ? WHERE id = ?",
        arguments: [reason, id])
    }
  }

  /// Counts a failed attempt and holds the rows until `nextAttemptAt`.
  func markFailed(ids: [Int64], error: String, nextAttemptAt: Int64) throws {
    guard !ids.isEmpty else { return }
    try dbq.write { db in
      try db.execute(
        sql: """
          UPDATE lastfm_scrobbles
          SET attempts = attempts + 1, next_attempt_at = ?, last_error = ?
          WHERE id IN \(Self.placeholders(ids.count))
          """,
        arguments: StatementArguments([nextAttemptAt, error] + ids.map { $0 as DatabaseValueConvertible? }))
    }
  }

  /// Last.fm drops scrobbles older than 14 days, so stop holding them.
  @discardableResult
  func expire(olderThan cutoff: Int64) throws -> Int {
    try dbq.write { db in
      try db.execute(
        sql: "UPDATE lastfm_scrobbles SET state = 'ignored', last_error = 'Older than 14 days' WHERE state = 'pending' AND played_at < ?",
        arguments: [cutoff])
      return db.changesCount
    }
  }

  func pendingCount() throws -> Int {
    try dbq.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lastfm_scrobbles WHERE state = 'pending'") ?? 0
    }
  }

  /// Earliest retry time among pending rows, if any are waiting.
  func nextAttemptAt() throws -> Int64? {
    try dbq.read { db in
      try Int64.fetchOne(db, sql: "SELECT MIN(next_attempt_at) FROM lastfm_scrobbles WHERE state = 'pending'")
    }
  }

  func lastSent() throws -> LastScrobble? {
    try dbq.read { db in
      guard let row = try Row.fetchOne(db, sql: """
        SELECT artist, track, sent_at FROM lastfm_scrobbles
        WHERE state = 'sent'
        ORDER BY sent_at DESC, played_at DESC
        LIMIT 1
        """) else { return nil }
      return LastScrobble(artist: row["artist"], track: row["track"], sentAt: row["sent_at"])
    }
  }

  private static func placeholders(_ count: Int) -> String {
    "(" + Array(repeating: "?", count: count).joined(separator: ",") + ")"
  }
}
