// DialTests/LastFM/ScrobbleBackfillTests.swift
import XCTest
import GRDB
@testable import Dial

final class ScrobbleBackfillTests: XCTestCase {
  private let now: Int64 = 1_700_100_000
  private let from: Int64 = 1_700_000_000
  private let until: Int64 = 1_700_050_000

  private func makeArchive() throws -> DatabaseQueue {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      for (uri, name, artist) in [
        ("spotify:track:A", "Song A", "Artist A"),
        ("spotify:track:B", "Song B", "Artist B"),
        ("spotify:track:C", "Song C", "Artist C"),
        ("spotify:track:D", "Song D", ""),
        ("spotify:track:E", "Song E", "Artist E"),
      ] {
        try db.execute(sql: """
          INSERT INTO tracks (uri, name, album_name, duration_ms, artists_json)
          VALUES (?, ?, 'Album', 200000, ?)
          """, arguments: [uri, name, "[{\"name\":\"\(artist)\",\"uri\":\"x\"}]"])
      }
    }
    return dbq
  }

  @discardableResult
  private func play(
    _ dbq: DatabaseQueue, _ uri: String, at: Int64, ms: Int64 = 200_000,
    source: String = "live", origin: String? = nil
  ) throws -> Int64 {
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO plays (played_at, track_uri, ms_played, source, origin)
        VALUES (?, ?, ?, ?, ?)
        """, arguments: [at, uri, ms, source, origin])
      return db.lastInsertedRowID
    }
  }

  func test_queuesRecentAndMergedPlays_andSkipsWhatALiveScrobbleWould() throws {
    let dbq = try makeArchive()
    let recent = try play(dbq, "spotify:track:A", at: from + 100, source: "recent")
    let merged = try play(dbq, "spotify:track:B", at: from + 1_000, origin: "mini")
    try play(dbq, "spotify:track:C", at: from + 2_000, ms: 40_000)  // counted, but under half
    try play(dbq, "spotify:track:D", at: from + 3_000)  // no artist
    try play(dbq, "spotify:track:A", at: until + 100)  // outside the window
    // E already went to Last.fm from another row of the same play.
    let sent = try play(dbq, "spotify:track:E", at: from + 4_000)
    try ScrobbleQueueDAO(dbq: dbq).enqueue(
      playId: sent, artist: "Artist E", track: "Song E", album: nil, durationMs: 200_000, now: now)
    try play(dbq, "spotify:track:E", at: from + 4_010, ms: 199_000, origin: "mini")

    let backfill = ScrobbleBackfill(dbq: dbq, from: from, until: until, now: now)
    let report = try backfill.run(dryRun: false)

    XCTAssertEqual(report.candidates.map(\.playId), [recent, merged])
    XCTAssertEqual(report.queued, 2)
    XCTAssertEqual(report.failsRule, 1)
    XCTAssertEqual(report.missingMetadata, 1)
    XCTAssertEqual(report.alreadyScrobbled, 2)
    let first = try XCTUnwrap(report.candidates.first)
    XCTAssertEqual(first.artist, "Artist A")
    XCTAssertEqual(first.track, "Song A")
    XCTAssertEqual(first.album, "Album")
    XCTAssertEqual(first.playedAt, from + 100)
    XCTAssertEqual(try ScrobbleQueueDAO(dbq: dbq).pendingCount(), 3)
  }

  func test_dryRunQueuesNothing_andASecondRunQueuesNothingNew() throws {
    let dbq = try makeArchive()
    try play(dbq, "spotify:track:A", at: from + 100, source: "recent")
    let backfill = ScrobbleBackfill(dbq: dbq, from: from, until: until, now: now)

    let dry = try backfill.run(dryRun: true)
    XCTAssertEqual(dry.candidates.count, 1)
    XCTAssertEqual(dry.queued, 0)
    XCTAssertEqual(try ScrobbleQueueDAO(dbq: dbq).pendingCount(), 0)

    XCTAssertEqual(try backfill.run(dryRun: false).queued, 1)
    let again = try backfill.run(dryRun: false)
    XCTAssertEqual(again.queued, 0)
    XCTAssertEqual(again.alreadyScrobbled, 1)
  }

  func test_skipsPlaysOlderThanLastFMAccepts() throws {
    let dbq = try makeArchive()
    try play(dbq, "spotify:track:A", at: from + 100, source: "recent")
    let late = from + 100 + ScrobbleBackfill.maxAgeSeconds + 1
    let report = try ScrobbleBackfill(dbq: dbq, from: from, until: until, now: late).plan()
    XCTAssertEqual(report.tooOld, 1)
    XCTAssertTrue(report.candidates.isEmpty)
  }

  func test_parsesLocalTimes() {
    XCTAssertNotNil(ScrobbleBackfill.time("2026-11-11 21:03"))
    XCTAssertEqual(ScrobbleBackfill.time("2026-11-11T21:03"), ScrobbleBackfill.time("2026-11-11 21:03"))
    XCTAssertNil(ScrobbleBackfill.time("Nov 11"))
  }
}
