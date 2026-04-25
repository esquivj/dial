import XCTest
import GRDB
@testable import Dial

final class PlayRecorderTests: XCTestCase {
  func test_countedPlay_insertsPlayRow() throws {
    let dbq = try InMemoryDatabase.make()
    let rec = PlayRecorder(dbq: dbq)
    try rec.handle(.countedPlay(trackUri: "T", msPlayed: 60_000, at: 1_700_000_000))
    let plays = try PlaysDAO(dbq: dbq).playsFor(trackUri: "T")
    XCTAssertEqual(plays.count, 1)
    XCTAssertEqual(plays.first?.source, "live")
  }
  func test_nonCountedEvent_isIgnored() throws {
    let dbq = try InMemoryDatabase.make()
    let rec = PlayRecorder(dbq: dbq)
    try rec.handle(.progress(ms: 1000))
    let count = try dbq.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM plays") }
    XCTAssertEqual(count, 0)
  }
}
