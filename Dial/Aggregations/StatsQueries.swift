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
  ///
  /// Default cap of 200 is intentional: HistoryView is a "what did I just
  /// listen to" feed, not an archive browser. The full history stays in the
  /// DB (where Stats aggregates against it) — there's just no need to scroll
  /// through 193k rows in a popover that's 320pt wide.
  ///
  /// Defensive `json_valid` guard: some `artists_json` rows in the DB have
  /// malformed JSON (e.g. unescaped backslashes from imported Spotify
  /// extended-history rows like `"artist:Axwell_/\_Ingrosso"`). Without
  /// this guard, hitting one of those rows during the join causes SQLite
  /// to throw "malformed JSON" and the whole query fails — so the view
  /// silently shows empty data via `try?`. Wrapping in CASE returns NULL
  /// (handled downstream) instead of crashing the query.
  func recentPlays(limit: Int = 200) throws -> [HistoryRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT p.id, p.played_at, p.track_uri,
               COALESCE(t.name, '') AS name,
               COALESCE(
                 CASE WHEN json_valid(t.artists_json) = 1
                      THEN json_extract(t.artists_json, '$[0].name')
                      ELSE NULL END,
                 ''
               ) AS artist,
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
               CASE WHEN json_valid(t.artists_json) = 1
                    THEN json_extract(t.artists_json, '$[0].name')
                    ELSE NULL END AS artist_name,
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

  /// Top artists by play count. Filters to rows with VALID `artists_json`
  /// (some imported rows have malformed JSON that crashes json_extract).
  ///
  /// **Alias note**: the column alias is `artist_uri`, not `uri`. SQLite's
  /// GROUP BY resolves `uri` to the unambiguous `tracks.uri` column (track
  /// URI — unique per track) instead of our extracted-artist alias, which
  /// produced one row per track (not per artist). Symptom in the UI:
  /// the same artist (e.g. "Junior H") appearing multiple times in
  /// top-artists with different play counts that don't sum to the artist's
  /// actual total. Renaming the alias avoids the collision.
  func topArtists(limit: Int = 10) throws -> [TopRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT
          json_extract(t.artists_json, '$[0].uri')  AS artist_uri,
          json_extract(t.artists_json, '$[0].name') AS name,
          COUNT(*) AS c
        FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE t.artists_json IS NOT NULL AND json_valid(t.artists_json) = 1
        GROUP BY artist_uri
        ORDER BY c DESC, MAX(p.played_at) DESC
        LIMIT ?
      """, arguments: [limit]).map { row in
        TopRow(uri: row["artist_uri"] ?? "", name: row["name"] ?? "Unknown", count: row["c"],
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
      // One scan of `plays` for the three play-derived metrics — was three
      // separate scans, which at 193k rows is 3× the work for no reason.
      // COUNT, SUM, and COUNT(DISTINCT) all share the same row stream and
      // SQLite handles them in a single pass when issued together.
      let row = try Row.fetchOne(db, sql: """
        SELECT COUNT(*) AS plays,
               COALESCE(SUM(ms_played), 0) AS total_ms,
               COUNT(DISTINCT track_uri) AS uniq_tracks
        FROM plays
      """)
      // Artists live in a different table, so this stays as a separate
      // query. Filter to rows with VALID `artists_json` — some imported
      // rows have malformed JSON (unescaped backslashes in URIs) which
      // makes `json_extract` throw "malformed JSON" mid-query. Before
      // the `json_valid` guard, ONE bad row would crash the whole
      // `totals()` call and the view's `try?` would silently fall back
      // to all zeros — making Stats look completely broken to the user.
      let artists = try Int.fetchOne(db, sql: """
        SELECT COUNT(DISTINCT json_extract(artists_json, '$[0].uri'))
        FROM tracks
        WHERE artists_json IS NOT NULL AND json_valid(artists_json) = 1
      """) ?? 0
      return Totals(
        plays: row?["plays"] ?? 0,
        listeningMs: row?["total_ms"] ?? 0,
        uniqueTracks: row?["uniq_tracks"] ?? 0,
        uniqueArtists: artists)
    }
  }

  // MARK: - Enrichment progress

  struct EnrichmentProgress: Equatable {
    let total: Int     // distinct spotify track URIs seen in plays
    let enriched: Int  // those with album_art_url populated in tracks
  }

  /// Counts distinct Spotify track URIs seen in `plays` and how many of
  /// those have been enriched (album_art_url populated by MetadataEnricher).
  /// Surfaced in the Settings diagnostic panel as "47,234 / 49,229 tracks"
  /// so the user can see the backfill progress without tailing logs.
  ///
  /// Single scan via a CASE expression — at 193k plays we don't want two
  /// separate full-table joins.
  func enrichmentProgress() throws -> EnrichmentProgress {
    try dbq.read { db in
      let row = try Row.fetchOne(db, sql: """
        SELECT
          COUNT(DISTINCT p.track_uri) AS total,
          COUNT(DISTINCT CASE WHEN t.album_art_url IS NOT NULL
                              THEN p.track_uri END) AS enriched
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.track_uri LIKE 'spotify:track:%'
      """)
      return EnrichmentProgress(
        total: row?["total"] ?? 0,
        enriched: row?["enriched"] ?? 0)
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
