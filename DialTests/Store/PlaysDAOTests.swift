// DialTests/Store/PlaysDAOTests.swift
import XCTest
import GRDB
@testable import Dial

final class PlaysDAOTests: XCTestCase {
  var dbq: DatabaseQueue!
  var dao: PlaysDAO!
  override func setUpWithError() throws {
    dbq = try InMemoryDatabase.make()
    dao = PlaysDAO(dbq: dbq)
  }
  func test_insert_and_fetchByTrack() throws {
    try dao.insert(.init(playedAt: 100, trackUri: "spotify:track:A", msPlayed: 60000, source: "live"))
    try dao.insert(.init(playedAt: 200, trackUri: "spotify:track:A", msPlayed: 90000, source: "live"))
    let plays = try dao.playsFor(trackUri: "spotify:track:A")
    XCTAssertEqual(plays.count, 2)
  }
  func test_uniqueConstraint_preventsDuplicates() throws {
    let p = Play(playedAt: 100, trackUri: "spotify:track:A", msPlayed: 60000, source: "live")
    try dao.insert(p)
    XCTAssertThrowsError(try dao.insert(p))
  }
}
