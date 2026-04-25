// Dial/Aggregations/StatsQueries.swift
import GRDB
import Foundation

/// Queries that power the History and Stats windows. All read-only.
struct StatsQueries {
  let dbq: DatabaseQueue

  // MARK: - History

  struct HistoryRow: Identifiable, Hashable {
    let id: Int64                  // play row id
    let playedAt: Int64
    let trackUri: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let albumArtUrl: String?
  }

  /// Most-recent plays first. Joins `plays` with `tracks` (left join — plays
  /// without metadata still surface, just with empty strings).
  func recentPlays(limit: Int = 500) throws -> [HistoryRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT p.id, p.played_at, p.track_uri,
               COALESCE(t.name, '') AS name,
               COALESCE(json_extract(t.artists_json, '$[0].name'), '') AS artist,
               t.album_name, t.album_art_url
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        ORDER BY p.played_at DESC
        LIMIT ?
      """, arguments: [limit]).map { row in
        HistoryRow(
          id: row["id"],
          playedAt: row["played_at"],
          trackUri: row["track_uri"],
          trackName: row["name"],
          artistName: row["artist"],
          albumName: row["album_name"],
          albumArtUrl: row["album_art_url"])
      }
    }
  }

  // MARK: - Top tracks / artists

  struct TopRow: Identifiable, Hashable {
    let uri: String
    let name: String
    let count: Int
    let artUrl: String?     // only populated by topTracks; nil for topArtists
    let subtitle: String?   // artist name for tracks; nil for artists
    var id: String { uri }
  }

  func topTracks(limit: Int = 10) throws -> [TopRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT p.track_uri AS uri,
               COALESCE(t.name, p.track_uri) AS name,
               t.album_art_url AS art_url,
               json_extract(t.artists_json, '$[0].name') AS artist_name,
               COUNT(*) AS c
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        GROUP BY p.track_uri
        ORDER BY c DESC, MAX(p.played_at) DESC
        LIMIT ?
      """, arguments: [limit]).map { row in
        TopRow(
          uri: row["uri"], name: row["name"], count: row["c"],
          artUrl: row["art_url"], subtitle: row["artist_name"]
        )
      }
    }
  }

  func topArtists(limit: Int = 10) throws -> [TopRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT
          json_extract(t.artists_json, '$[0].uri')  AS uri,
          json_extract(t.artists_json, '$[0].name') AS name,
          COUNT(*) AS c
        FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE t.artists_json IS NOT NULL
        GROUP BY uri
        ORDER BY c DESC, MAX(p.played_at) DESC
        LIMIT ?
      """, arguments: [limit]).map { row in
        TopRow(uri: row["uri"] ?? "", name: row["name"] ?? "Unknown", count: row["c"],
               artUrl: nil, subtitle: nil)
      }
    }
  }

  // MARK: - Totals

  struct Totals {
    let plays: Int
    let listeningMs: Int64
    let uniqueTracks: Int
    let uniqueArtists: Int
  }

  func totals() throws -> Totals {
    try dbq.read { db in
      let plays = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") ?? 0
      let ms = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(ms_played), 0) FROM plays") ?? 0
      let tracks = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT track_uri) FROM plays") ?? 0
      let artists = try Int.fetchOne(db, sql: """
        SELECT COUNT(DISTINCT json_extract(artists_json, '$[0].uri'))
        FROM tracks WHERE artists_json IS NOT NULL
      """) ?? 0
      return Totals(plays: plays, listeningMs: ms, uniqueTracks: tracks, uniqueArtists: artists)
    }
  }

  // MARK: - Live observation

  /// Fires whenever the `plays` table changes. Window views observe this to refresh.
  func observePlaysChanges() -> ValueObservation<ValueReducers.Fetch<Int>> {
    ValueObservation.tracking { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") ?? 0
    }
  }
}
