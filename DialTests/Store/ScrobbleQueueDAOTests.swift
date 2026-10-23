// DialTests/Store/ScrobbleQueueDAOTests.swift
import XCTest
import GRDB
@testable import Dial

final class ScrobbleQueueDAOTests: XCTestCase {
  func test_enqueue_refusesPlaysMergedFromAnotherMac() throws {
    let dbq = try InMemoryDatabase.make()
    let ids = try dbq.write { db -> (local: Int64, merged: Int64) in
      try db.execute(sql: """
        INSERT INTO plays (played_at, track_uri, ms_played, source)
        VALUES (1700000000, 'spotify:track:A', 200000, 'live')
        """)
      let local = db.lastInsertedRowID
      try db.execute(sql: """
        INSERT INTO plays (played_at, track_uri, ms_played, source, origin)
        VALUES (1700000500, 'spotify:track:B', 200000, 'live', 'other-mac')
        """)
      return (local, db.lastInsertedRowID)
    }

    let dao = ScrobbleQueueDAO(dbq: dbq)
    XCTAssertTrue(try dao.enqueue(
      playId: ids.local, artist: "A", track: "Song A", album: nil, durationMs: 200_000, now: 1_700_001_000))
    XCTAssertFalse(try dao.enqueue(
      playId: ids.merged, artist: "B", track: "Song B", album: nil, durationMs: 200_000, now: 1_700_001_000))
    XCTAssertEqual(try dao.pendingCount(), 1)
  }
}
