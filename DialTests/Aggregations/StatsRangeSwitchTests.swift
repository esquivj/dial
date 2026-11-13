import GRDB
import XCTest
@testable import Dial

/// PLA-119: switching Stats ranges shows that range's numbers, and a load
/// the user already moved past stops instead of holding the database.
final class StatsRangeSwitchTests: XCTestCase {
  func test_eachRangeLoadsItsOwnTotals() throws {
    let dbq = try InMemoryDatabase.make()
    let now = Int64(Date().timeIntervalSince1970)
    try dbq.write { db in
      // 2 plays this week, 3 more this month, 4 more long ago.
      let agesInDays: [Int64] = [1, 2, 10, 12, 14, 900, 901, 902, 903]
      for (i, days) in agesInDays.enumerated() {
        try db.execute(
          sql: "INSERT INTO plays (played_at, track_uri, ms_played, source) VALUES (?, ?, 200000, 'live')",
          arguments: [now - days * 86_400, "spotify:track:t\(i)"])
      }
    }

    XCTAssertEqual(StatsViewSnapshot.make(dbq: dbq, range: .seven)?.totals.plays, 2)
    XCTAssertEqual(StatsViewSnapshot.make(dbq: dbq, range: .thirty)?.totals.plays, 5)
    XCTAssertEqual(StatsViewSnapshot.make(dbq: dbq, range: .all)?.totals.plays, 9)
  }

  func test_cancelledLoadStopsBeforeTheNextQuery() throws {
    let dbq = try InMemoryDatabase.make()
    var checks = 0
    let snapshot = StatsViewSnapshot.make(dbq: dbq, range: .all, isCancelled: {
      checks += 1
      return true
    })
    XCTAssertNil(snapshot)
    XCTAssertEqual(checks, 1, "a cancelled load runs no queries")
  }

  /// The ALL genre row on a real archive carries ~12k tags, mostly repeats.
  func test_genreThemeMatchesEachDistinctTagOnce() {
    let distinct = ["hip hop", "rap", "trap", "cloud rap", "indie rock", "house", "punk"]
    let tags = (0..<12_000).map { distinct[$0 % distinct.count] }
    let start = Date()
    _ = SoundThemeResolver.theme(forRawTags: tags, fallbackFamily: "rap")
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
  }
}
