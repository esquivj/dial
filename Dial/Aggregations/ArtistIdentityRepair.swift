// Dial/Aggregations/ArtistIdentityRepair.swift
import Foundation
import GRDB

enum ArtistIdentityRepair {
  static func createTable(in db: Database) throws {
    try db.create(table: "artist_identity_aliases", ifNotExists: true) { t in
      t.column("source_uri", .text).primaryKey()
      t.column("source_name", .text).notNull()
      t.column("normalized_name_key", .text).notNull()
      t.column("canonical_uri", .text).notNull()
      t.column("canonical_name", .text).notNull()
      t.column("confidence", .double).notNull()
      t.column("reason", .text).notNull()
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "artist_identity_aliases_by_canonical", on: "artist_identity_aliases", columns: ["canonical_uri"], ifNotExists: true)
    try db.create(index: "artist_identity_aliases_by_name_key", on: "artist_identity_aliases", columns: ["normalized_name_key"], ifNotExists: true)
  }

  @discardableResult
  static func rebuildAliases(in db: Database, now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> Int {
    try createTable(in: db)
    try db.execute(sql: "DELETE FROM artist_identity_aliases WHERE reason = 'exact_normalized_name'")
    try db.execute(sql: """
      WITH artist_rows AS (
        SELECT DISTINCT
               NULLIF(TRIM(json_extract(j.value, '$.uri')), '') AS artist_uri,
               NULLIF(TRIM(json_extract(j.value, '$.name')), '') AS artist_name,
               LOWER(TRIM(json_extract(j.value, '$.name'))) AS name_key
        FROM tracks t
        CROSS JOIN json_each(
          CASE WHEN json_valid(t.artists_json) = 1 THEN t.artists_json ELSE '[]' END
        ) j
        WHERE t.artists_json IS NOT NULL
          AND json_valid(t.artists_json) = 1
          AND NULLIF(TRIM(json_extract(j.value, '$.uri')), '') IS NOT NULL
          AND NULLIF(TRIM(json_extract(j.value, '$.name')), '') IS NOT NULL
      ),
      canonical_names AS (
        SELECT name_key,
               MIN(artist_uri) AS canonical_uri,
               MIN(artist_name) AS canonical_name,
               COUNT(DISTINCT artist_uri) AS canonical_count
        FROM artist_rows
        WHERE artist_uri LIKE 'spotify:artist:%'
        GROUP BY name_key
        HAVING canonical_count = 1
      ),
      fallback_names AS (
        SELECT artist_uri AS source_uri,
               MIN(artist_name) AS source_name,
               name_key
        FROM artist_rows
        WHERE artist_uri NOT LIKE 'spotify:artist:%'
        GROUP BY artist_uri, name_key
      ),
      exact_aliases AS (
        SELECT f.source_uri,
               f.source_name,
               f.name_key,
               c.canonical_uri,
               c.canonical_name
        FROM fallback_names f
        JOIN canonical_names c ON c.name_key = f.name_key
        WHERE f.source_uri <> c.canonical_uri
      )
      INSERT INTO artist_identity_aliases (
        source_uri,
        source_name,
        normalized_name_key,
        canonical_uri,
        canonical_name,
        confidence,
        reason,
        created_at,
        updated_at
      )
      SELECT source_uri,
             source_name,
             name_key,
             canonical_uri,
             canonical_name,
             1.0,
             'exact_normalized_name',
             ?,
             ?
      FROM exact_aliases
      WHERE 1 = 1
      ON CONFLICT(source_uri) DO UPDATE SET
        source_name = excluded.source_name,
        normalized_name_key = excluded.normalized_name_key,
        canonical_uri = excluded.canonical_uri,
        canonical_name = excluded.canonical_name,
        confidence = excluded.confidence,
        reason = excluded.reason,
        updated_at = excluded.updated_at
      """, arguments: [now, now])

    return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM artist_identity_aliases") ?? 0
  }

  static func resolvedArtistUris(_ artistUris: [String], in db: Database) throws -> [String] {
    let clean = artistUris
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !clean.isEmpty else { return [] }

    let values = clean.enumerated().map { _, _ in "(?, ?)" }.joined(separator: ",")
    var arguments: [DatabaseValueConvertible] = []
    for (index, uri) in clean.enumerated() {
      arguments.append(uri)
      arguments.append(index)
    }
    return try String.fetchAll(db, sql: """
      WITH input(uri, ord) AS (VALUES \(values)),
      resolved AS (
        SELECT COALESCE(a.canonical_uri, input.uri) AS uri,
               MIN(input.ord) AS ord
        FROM input
        LEFT JOIN artist_identity_aliases a ON a.source_uri = input.uri
        GROUP BY COALESCE(a.canonical_uri, input.uri)
      )
      SELECT uri
      FROM resolved
      ORDER BY ord
      """, arguments: StatementArguments(arguments))
  }
}
