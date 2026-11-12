import XCTest
import GRDB
@testable import Dial

/// PLA-98: the first-artist lookups must use the v21 indexes, and give the
/// same tracks as the old `COALESCE(alias.canonical_uri, first_uri)` rule.
final class TrackArtistSQLTests: XCTestCase {
  private func makeDatabase() throws -> DatabaseQueue {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    func track(_ uri: String, artist: String, artistUri: String, album: String = "Al") throws {
      try tracks.upsert(.init(uri: uri, name: uri, albumName: album, albumArtUrl: nil, durationMs: 200_000,
                              artistsJson: #"[{"name":"\#(artist)","uri":"\#(artistUri)"}]"#))
    }
    try track("own", artist: "Main", artistUri: "art:main")
    try track("other-album", artist: "Main", artistUri: "art:main", album: "Other")
    try track("aliased", artist: "Main (old id)", artistUri: "art:old")
    try track("redirected", artist: "Moved", artistUri: "art:moved")
    try track("by-name", artist: " MAIN ", artistUri: "art:unrelated")
    try track("someone", artist: "Someone", artistUri: "art:someone")
    try tracks.upsert(.init(uri: "broken", name: "broken", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: "not json"))
    try dbq.write { db in
      // art:old resolves to art:main; art:moved resolves elsewhere.
      for (source, canonical) in [("art:old", "art:main"), ("art:moved", "art:elsewhere")] {
        try db.execute(sql: """
          INSERT INTO artist_identity_aliases
            (source_uri, source_name, normalized_name_key, canonical_uri, canonical_name,
             confidence, reason, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 1, 'test', 0, 0)
          """, arguments: [source, source, source, canonical, canonical])
      }
    }
    return dbq
  }

  private func uris(_ dbq: DatabaseQueue, artistUri: String?, name: String?, album: String? = nil) throws -> Set<String> {
    try dbq.read { db in
      let query = try TrackArtistSQL.trackURIs(
        artistUri: artistUri,
        normalizedName: name,
        extraCondition: album.map { _ in "LOWER(TRIM(t.album_name)) = ?" },
        extraArguments: album.map { [$0] } ?? [],
        in: db)
      return Set(try String.fetchAll(db, sql: query.sql, arguments: query.arguments))
    }
  }

  func test_matchesByResolvedArtistIdAndByName() throws {
    let dbq = try makeDatabase()

    XCTAssertEqual(try uris(dbq, artistUri: "art:main", name: nil), ["own", "other-album", "aliased"])
    XCTAssertEqual(try uris(dbq, artistUri: nil, name: "main"), ["own", "other-album", "by-name"])
    XCTAssertEqual(try uris(dbq, artistUri: "art:main", name: "main"), ["own", "other-album", "aliased", "by-name"])
    // An id that has been aliased away no longer matches its own tracks.
    XCTAssertEqual(try uris(dbq, artistUri: "art:moved", name: nil), [])
    XCTAssertEqual(try uris(dbq, artistUri: "art:elsewhere", name: nil), ["redirected"])
    XCTAssertEqual(try uris(dbq, artistUri: nil, name: nil), [])
  }

  func test_extraConditionAppliesToEveryBranch() throws {
    let dbq = try makeDatabase()
    XCTAssertEqual(try uris(dbq, artistUri: "art:main", name: "main", album: "al"), ["own", "aliased", "by-name"])
  }

  func test_lookupsUseTheFirstArtistIndexes() throws {
    let dbq = try makeDatabase()
    let plan = try dbq.read { db -> String in
      let query = try TrackArtistSQL.trackURIs(artistUri: "art:main", normalizedName: "main", in: db)
      let rows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(query.sql)", arguments: query.arguments)
      return rows.map { $0["detail"] as String }.joined(separator: "\n")
    }
    XCTAssertTrue(plan.contains("tracks_by_first_artist_uri"), plan)
    XCTAssertTrue(plan.contains("tracks_by_first_artist_name"), plan)
    XCTAssertFalse(plan.contains("SCAN t"), plan)
  }
}
