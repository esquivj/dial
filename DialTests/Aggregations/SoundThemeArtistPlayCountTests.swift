import XCTest
import GRDB
@testable import Dial

/// PLA-150: the core-library play count follows artist aliases both ways and
/// probes plays by track instead of scanning every play.
final class SoundThemeArtistPlayCountTests: XCTestCase {
  private func makeDatabase() throws -> DatabaseQueue {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    let plays = PlaysDAO(dbq: dbq)
    func track(_ uri: String, artists: String) throws {
      try tracks.upsert(.init(uri: uri, name: uri, albumName: "Al", albumArtUrl: nil, durationMs: 200_000,
                              artistsJson: artists))
    }
    try track("own", artists: #"[{"name":"Main","uri":"art:main"}]"#)
    try track("aliased", artists: #"[{"name":"Main (old id)","uri":"art:old"}]"#)
    try track("feature", artists: #"[{"name":"Guest","uri":"art:guest"},{"name":"Main","uri":"art:main"}]"#)
    try track("someone", artists: #"[{"name":"Someone","uri":"art:someone"}]"#)
    try tracks.upsert(.init(uri: "broken", name: "broken", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: "not json"))

    var at: Int64 = 1_000
    func play(_ track: String, times: Int, msPlayed: Int64 = 180_000) throws {
      for _ in 0..<times {
        at += 1_000
        try plays.insert(.init(playedAt: at, trackUri: track, msPlayed: msPlayed, source: "import"))
      }
    }
    try play("own", times: 3)
    try play("aliased", times: 2)
    try play("feature", times: 1)
    try play("someone", times: 4)
    try play("broken", times: 1)
    // Under 30 s and under half the track: not a counted play.
    try play("own", times: 2, msPlayed: 5_000)

    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO artist_identity_aliases
          (source_uri, source_name, normalized_name_key, canonical_uri, canonical_name,
           confidence, reason, created_at, updated_at)
        VALUES ('art:old', 'Main (old id)', 'main', 'art:main', 'Main', 1, 'test', 0, 0)
        """)
    }
    return dbq
  }

  private func count(_ dbq: DatabaseQueue, _ artistUris: [String]) throws -> Int {
    try dbq.read { db in try SoundThemeResolver.artistPlayCount(db: db, artistUris: artistUris) }
  }

  func test_countsCountedPlaysThroughAliasesBothWays() throws {
    let dbq = try makeDatabase()
    // Canonical id picks up its alias's tracks and features.
    XCTAssertEqual(try count(dbq, ["art:main"]), 6)
    // An aliased id picks up its canonical artist's tracks.
    XCTAssertEqual(try count(dbq, ["art:old"]), 6)
    XCTAssertEqual(try count(dbq, ["art:main", "art:old", " art:main "]), 6)
    XCTAssertEqual(try count(dbq, ["art:guest"]), 1)
    XCTAssertEqual(try count(dbq, ["art:someone"]), 4)
    XCTAssertEqual(try count(dbq, ["art:nobody"]), 0)
    XCTAssertEqual(try count(dbq, []), 0)
  }

  func test_playsAreSearchedByTrackNotScanned() throws {
    let dbq = try makeDatabase()
    let plan = try dbq.read { db -> String in
      let rows = try Row.fetchAll(
        db,
        sql: "EXPLAIN QUERY PLAN \(SoundThemeResolver.artistPlayCountSQL)",
        arguments: [#"["art:main"]"#])
      return rows.map { $0["detail"] as String }.joined(separator: "\n")
    }
    XCTAssertTrue(plan.contains("plays_by_track"), plan)
    let scansPlays = plan.split(separator: "\n").contains { line in
      line == "SCAN p" || line.hasPrefix("SCAN p ") || line.hasPrefix("SCAN plays")
    }
    XCTAssertFalse(scansPlays, plan)
  }
}
