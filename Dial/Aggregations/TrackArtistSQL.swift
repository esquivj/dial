// Dial/Aggregations/TrackArtistSQL.swift
import Foundation
import GRDB

/// Indexed lookups of tracks by their first artist (PLA-98).
///
/// `tracks.artists_json` holds the artist list as JSON, so "every track by
/// this artist" used to mean evaluating JSON for all ~50k tracks, joined to
/// all ~200k counted plays, on every play Dial recorded or replayed (about
/// 0.6 s per play on a real archive). Migration v21 indexes the two
/// expressions below. A query uses an expression index only when its
/// expression matches the indexed one exactly, so they live here, and
/// `TrackArtistSQLTests` checks that SQLite's plan picks the indexes.
enum TrackArtistSQL {
  /// The first artist's id, or NULL when `artists_json` is missing or not
  /// valid JSON. Indexed as `tracks_by_first_artist_uri`.
  static func firstArtistURI(_ table: String) -> String {
    "(CASE WHEN json_valid(\(table).artists_json) = 1 THEN json_extract(\(table).artists_json, '$[0].uri') END)"
  }

  /// The first artist's name, trimmed and lowercased, or NULL. Indexed as
  /// `tracks_by_first_artist_name`.
  static func firstArtistName(_ table: String) -> String {
    "(CASE WHEN json_valid(\(table).artists_json) = 1 THEN LOWER(TRIM(json_extract(\(table).artists_json, '$[0].name'))) END)"
  }

  /// The uris of tracks whose first artist resolves to `artistUri` (after
  /// `artist_identity_aliases`), or whose first artist's normalized name is
  /// `normalizedName`. Either filter may be nil.
  ///
  /// Same result as the old per-play predicate
  /// `COALESCE(alias.canonical_uri, first_uri) = ? OR first_name = ?`, split
  /// so each branch is an index lookup:
  ///  1. first artist is `artistUri` and has no alias;
  ///  2. first artist has an alias whose canonical id is `artistUri`;
  ///  3. first artist's name matches.
  ///
  /// Branch 2's alias ids are read first and bound as values. macOS's SQLite
  /// (3.54) won't use the expression index for a join or `IN (SELECT …)`
  /// on that branch and scans every track instead, about 30 ms a call.
  ///
  /// Returns the SQL for an `IN (...)` subquery and its arguments, with an
  /// optional extra condition on `t` applied to every branch.
  static func trackURIs(
    artistUri: String?,
    normalizedName: String?,
    extraCondition: String? = nil,
    extraArguments: [DatabaseValueConvertible?] = [],
    in db: Database
  ) throws -> (sql: String, arguments: StatementArguments) {
    let uri = firstArtistURI("t")
    let name = firstArtistName("t")
    let extra = extraCondition.map { " AND (\($0))" } ?? ""
    let aliasSources = try artistUri.map {
      try String.fetchAll(
        db,
        sql: "SELECT source_uri FROM artist_identity_aliases WHERE canonical_uri = ?",
        arguments: [$0])
    } ?? []

    var branches = ["""
      SELECT t.uri FROM tracks t
      WHERE \(uri) = ?
        AND NOT EXISTS (SELECT 1 FROM artist_identity_aliases a WHERE a.source_uri = \(uri))\(extra)
      """]
    var arguments: [DatabaseValueConvertible?] = [artistUri]
    arguments += extraArguments
    if !aliasSources.isEmpty {
      let placeholders = Array(repeating: "?", count: aliasSources.count).joined(separator: ", ")
      branches.append("SELECT t.uri FROM tracks t WHERE \(uri) IN (\(placeholders))\(extra)")
      arguments += aliasSources.map { $0 as DatabaseValueConvertible? }
      arguments += extraArguments
    }
    branches.append("SELECT t.uri FROM tracks t WHERE \(name) = ?\(extra)")
    arguments.append(normalizedName)
    arguments += extraArguments
    return (branches.joined(separator: "\nUNION\n"), StatementArguments(arguments))
  }
}
