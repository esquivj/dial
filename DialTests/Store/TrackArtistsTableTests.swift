// DialTests/Store/TrackArtistsTableTests.swift
import XCTest
import GRDB
@testable import Dial

/// PLA-151: `track_artists` mirrors every credited artist id in
/// `tracks.artists_json`, filled by migration v22 and kept in step by
/// triggers on `tracks`.
final class TrackArtistsTableTests: XCTestCase {
  private struct Row: Hashable {
    let track: String
    let position: Int
    let artist: String
  }

  private func rows(_ dbq: DatabaseQueue) throws -> Set<Row> {
    try dbq.read { db in
      Set(try GRDB.Row.fetchAll(db, sql: "SELECT track_uri, position, artist_uri FROM track_artists").map {
        Row(track: $0["track_uri"], position: $0["position"], artist: $0["artist_uri"])
      })
    }
  }

  private func insertRaw(_ db: Database, _ uri: String, _ artistsJson: String?) throws {
    try db.execute(
      sql: "INSERT INTO tracks (uri, name, artists_json) VALUES (?, ?, ?)",
      arguments: [uri, uri, artistsJson])
  }

  func test_migrationBackfillsFromArtistsJson() throws {
    let dbq = try DatabaseQueue()
    let migrations = Migrations.register()
    try migrations.migrate(dbq, upTo: "v21_tracks_first_artist_indexes")
    try dbq.write { db in
      try insertRaw(db, "solo", #"[{"name":"A","uri":"art:a"}]"#)
      try insertRaw(db, "duet", #"[{"name":"A","uri":"art:a"},{"name":"B","uri":"art:b"}]"#)
      try insertRaw(db, "no-uri", #"[{"name":"Nameless"},{"name":"C","uri":"art:c"}]"#)
      try insertRaw(db, "strings", #"["art:x", {"name":"D","uri":"art:d"}]"#)
      try insertRaw(db, "object", #"{"name":"E","uri":"art:e"}"#)
      try insertRaw(db, "broken", "not json")
      try insertRaw(db, "missing", nil)
    }
    try migrations.migrate(dbq)

    XCTAssertEqual(try rows(dbq), [
      Row(track: "solo", position: 0, artist: "art:a"),
      Row(track: "duet", position: 0, artist: "art:a"),
      Row(track: "duet", position: 1, artist: "art:b"),
      Row(track: "no-uri", position: 1, artist: "art:c"),
      Row(track: "strings", position: 1, artist: "art:d"),
    ])
  }

  func test_triggersFollowEveryWriteToTracks() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    func upsert(_ uri: String, _ artistsJson: String?) throws {
      try tracks.upsert(.init(uri: uri, name: uri, albumName: nil, albumArtUrl: nil, durationMs: nil,
                              artistsJson: artistsJson))
    }

    // Imported history first: a synthetic id.
    try upsert("t1", #"[{"name":"A","uri":"artist:A"}]"#)
    XCTAssertEqual(try rows(dbq), [Row(track: "t1", position: 0, artist: "artist:A")])

    // A write without artists keeps them (the upsert's COALESCE).
    try upsert("t1", nil)
    XCTAssertEqual(try rows(dbq), [Row(track: "t1", position: 0, artist: "artist:A")])

    // Enrichment replaces them with real ids, and a feature.
    try upsert("t1", #"[{"name":"A","uri":"spotify:artist:a"},{"name":"F","uri":"spotify:artist:f"}]"#)
    XCTAssertEqual(try rows(dbq), [
      Row(track: "t1", position: 0, artist: "spotify:artist:a"),
      Row(track: "t1", position: 1, artist: "spotify:artist:f"),
    ])

    // Invalid JSON clears them rather than failing the write.
    try dbq.write { db in try db.execute(sql: "UPDATE tracks SET artists_json = 'oops' WHERE uri = 't1'") }
    XCTAssertEqual(try rows(dbq), [])

    try upsert("t2", #"[{"name":"B","uri":"spotify:artist:b"}]"#)
    try dbq.write { db in try db.execute(sql: "UPDATE tracks SET uri = 't3' WHERE uri = 't2'") }
    XCTAssertEqual(try rows(dbq), [Row(track: "t3", position: 0, artist: "spotify:artist:b")])

    try dbq.write { db in try db.execute(sql: "DELETE FROM tracks WHERE uri = 't3'") }
    XCTAssertEqual(try rows(dbq), [])
  }

  /// `SoundThemeResolver.artistPlayCount`'s artist-to-tracks step, before
  /// (JSON over every track) and after (`track_artists`), must agree for
  /// every artist, through aliases both ways.
  func test_artistTracksMatchTheJsonScan() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try insertRaw(db, "solo", #"[{"name":"A","uri":"art:a"}]"#)
      try insertRaw(db, "feature", #"[{"name":"B","uri":"art:b"},{"name":"A","uri":"art:a"}]"#)
      try insertRaw(db, "old-id", #"[{"name":"A","uri":"art:a-old"}]"#)
      try insertRaw(db, "synthetic", #"[{"name":"C","uri":"artist:C"}]"#)
      try insertRaw(db, "nameless", #"[{"name":"N"}]"#)
      try insertRaw(db, "broken", "not json")
      try insertRaw(db, "missing", nil)
      for (source, canonical) in [("art:a-old", "art:a"), ("artist:C", "art:c")] {
        try db.execute(sql: """
          INSERT INTO artist_identity_aliases
            (source_uri, source_name, normalized_name_key, canonical_uri, canonical_name,
             confidence, reason, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 1, 'test', 0, 0)
          """, arguments: [source, source, source, canonical, canonical])
      }
    }
    let targets = """
      WITH target(uri) AS (SELECT value FROM json_each(?)),
      target_sources AS (
        SELECT uri FROM target
        UNION SELECT source_uri FROM artist_identity_aliases WHERE canonical_uri IN (SELECT uri FROM target)
        UNION SELECT canonical_uri FROM artist_identity_aliases WHERE source_uri IN (SELECT uri FROM target)
      )
      """
    let before = targets + """
      SELECT DISTINCT t.uri FROM tracks t,
        json_each(CASE WHEN json_valid(t.artists_json) = 1 THEN t.artists_json ELSE '[]' END) j
      WHERE t.artists_json IS NOT NULL AND json_valid(t.artists_json) = 1
        AND json_extract(j.value, '$.uri') IN (SELECT uri FROM target_sources)
      """
    let after = targets + """
      SELECT DISTINCT track_uri FROM track_artists WHERE artist_uri IN (SELECT uri FROM target_sources)
      """
    let cases: [(String, Set<String>)] = [
      (#"["art:a"]"#, ["solo", "feature", "old-id"]),
      (#"["art:a-old"]"#, ["solo", "feature", "old-id"]),
      (#"["art:b"]"#, ["feature"]),
      (#"["art:c"]"#, ["synthetic"]),
      (#"["artist:C", "art:b"]"#, ["synthetic", "feature"]),
      (#"["art:nobody"]"#, []),
    ]
    try dbq.read { db in
      for (artists, expected) in cases {
        let old = Set(try String.fetchAll(db, sql: before, arguments: [artists]))
        let new = Set(try String.fetchAll(db, sql: after, arguments: [artists]))
        XCTAssertEqual(old, expected, artists)
        XCTAssertEqual(new, old, artists)
      }
    }
  }

  func test_lookupByArtistUsesTheIndex() throws {
    let dbq = try InMemoryDatabase.make()
    let detail = try dbq.read { db in
      try GRDB.Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT track_uri FROM track_artists WHERE artist_uri = 'x'")
        .map { $0["detail"] as String }.joined(separator: "\n")
    }
    XCTAssertTrue(detail.contains("track_artists_by_artist"), detail)
  }
}
