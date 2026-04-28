// DialTests/Aggregations/PlayAggregationsTests.swift
import XCTest
import GRDB
import Foundation
@testable import Dial

final class PlayAggregationsTests: XCTestCase {
  var dbq: DatabaseQueue!
  var agg: PlayAggregations!
  override func setUpWithError() throws {
    dbq = try InMemoryDatabase.make()
    agg = PlayAggregations(dbq: dbq, now: { 1_700_000_000 })  // fixed clock
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    // Seed track metadata so artistRank7d (Task 13) has rows to join with
    try tracks.upsert(.init(uri: "A", name: "A", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: #"[{"name":"Caroline","uri":"art:1"}]"#))
    try tracks.upsert(.init(uri: "B", name: "B", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: #"[{"name":"Mac","uri":"art:2"}]"#))
    try tracks.upsert(.init(uri: "C", name: "C", albumName: nil, albumArtUrl: nil, durationMs: nil, artistsJson: nil))
    let now: Int64 = 1_700_000_000
    // 24 plays of C: 2 in the 7d window (rank 3, qualifies onStreak) + 22 in days 8-29
    // 7d plays: now-2d, now-3d (both within 7d and outside 60min window)
    for i in 2..<4  { try plays.insert(.init(playedAt: now - Int64(i) * 86_400, trackUri: "C", msPlayed: 200_000, source: "live")) }
    // 22 plays in days 8-29 (all within 30d, outside 7d)
    for i in 8..<30 { try plays.insert(.init(playedAt: now - Int64(i) * 86_400, trackUri: "C", msPlayed: 200_000, source: "live")) }
    // 5 plays of A in last 7d, starting 2h ago so none fall in the 60-min window
    for i in 0..<5  { try plays.insert(.init(playedAt: now - 2 * 3600 - Int64(i) * 3600, trackUri: "A", msPlayed: 200_000, source: "live")) }
    // 3 plays of B in last 7d, starting 2h ago
    for i in 0..<3  { try plays.insert(.init(playedAt: now - 2 * 3600 - Int64(i) * 3600, trackUri: "B", msPlayed: 200_000, source: "live")) }
  }

  // MARK: Task 11
  func test_plays30d_countsOnlyWithinWindow() throws {
    XCTAssertEqual(try agg.plays30d(trackUri: "C"), 24)
    XCTAssertEqual(try agg.plays30d(trackUri: "A"), 5)
  }

  func test_playsYTD_countsSinceStartOfCurrentYear() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 300 * 86_400, trackUri: "B", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 370 * 86_400, trackUri: "B", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.playsYTD(trackUri: "B"), 4)
  }

  func test_rank7d_ranksByCountDesc() throws {
    XCTAssertEqual(try agg.rank7d(trackUri: "A"), 1)
    XCTAssertEqual(try agg.rank7d(trackUri: "B"), 2)
  }

  func test_lastPlayedAt_returnsMostRecentPriorPlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 10 * 86_400, trackUri: "LAST", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 2 * 86_400, trackUri: "LAST", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.lastPlayedAt(trackUri: "LAST"), now - 2 * 86_400)
  }

  func test_lastPlayedAt_excludesCurrentCountedPlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 90 * 86_400, trackUri: "CURRENT", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now, trackUri: "CURRENT", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.lastPlayedAt(trackUri: "CURRENT", before: now), now - 90 * 86_400)
  }

  // MARK: Task 12
  func test_firstListen_onlyTrueIfNoImportAndOneLivePlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    try plays.insert(.init(playedAt: 1_700_000_000, trackUri: "NEW", msPlayed: 200_000, source: "live"))
    XCTAssertTrue(try agg.firstListen(trackUri: "NEW"))
    try plays.insert(.init(playedAt: 1_700_000_001, trackUri: "NEW", msPlayed: 200_000, source: "live"))
    XCTAssertFalse(try agg.firstListen(trackUri: "NEW"))
  }
  func test_rediscovered_gapAtLeast90Days() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 100 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now, trackUri: "OLD", msPlayed: 200_000, source: "live"))
    XCTAssertTrue(try agg.rediscovered(trackUri: "OLD"))
  }

  func test_rediscovered_falseWhenTrackWasPlayedRecently() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 100 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 2 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "live"))

    XCTAssertFalse(try agg.rediscovered(trackUri: "OLD"))
  }
  func test_onStreak_requiresPlays30dGte10AndRank7dLte5() throws {
    XCTAssertTrue(try agg.onStreak(trackUri: "C"))    // 24 plays in 30d
    XCTAssertFalse(try agg.onStreak(trackUri: "A"))   // 5 plays in 30d
  }

  // MARK: Task 13
  func test_last60MinTracks_returnsOrderedUrisWithinWindow() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 10 * 60, trackUri: "X", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 5  * 60, trackUri: "Y", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 1  * 60, trackUri: "Z", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 90 * 60, trackUri: "W", msPlayed: 200_000, source: "live"))  // outside
    let items = try agg.last60MinTracks()
    XCTAssertEqual(items.map(\.trackUri), ["Z","Y","X"])  // newest first
  }

  func test_artistRank7d() throws {
    // Tracks A and B (seeded in setUp) have artists art:1 and art:2 respectively.
    // 5 plays of A in 7d > 3 plays of B → art:1 ranks first.
    XCTAssertEqual(try agg.artistRank7d(artistUri: "art:1"), 1)
    XCTAssertEqual(try agg.artistRank7d(artistUri: "art:2"), 2)
  }
}

final class StatsQueriesTests: XCTestCase {
  func test_weekdayRhythm_normalizesByWeekdayOccurrences() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let rangeStart = localEpoch(year: 2024, month: 1, day: 1, hour: 0)
    let now = localEpoch(year: 2024, month: 1, day: 15, hour: 12)

    // Jan 1/8/15 2024 are Mondays: 6 raw plays across 3 Mondays = 2.0/day.
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 1, hour: 12), track: "mon")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 8, hour: 12), track: "mon")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 15, hour: 12), track: "mon")

    // Jan 2/9 are Tuesdays: fewer raw plays, but stronger normalized rhythm.
    try insertPlays(plays, count: 3, startingAt: localEpoch(year: 2024, month: 1, day: 2, hour: 12), track: "tue")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 9, hour: 12), track: "tue")

    let buckets = try StatsQueries(dbq: dbq).weekdayRhythm(since: rangeStart, now: now)
    let monday = try XCTUnwrap(buckets.first { $0.label == "MON" })
    let tuesday = try XCTUnwrap(buckets.first { $0.label == "TUE" })

    XCTAssertEqual(monday.count, 6)
    XCTAssertEqual(monday.occurrences, 3)
    XCTAssertEqual(monday.value, 2.0, accuracy: 0.001)
    XCTAssertEqual(tuesday.count, 5)
    XCTAssertEqual(tuesday.occurrences, 2)
    XCTAssertEqual(tuesday.value, 2.5, accuracy: 0.001)
    XCTAssertEqual(buckets.max(by: { $0.value < $1.value })?.label, "TUE")
  }

  func test_recentDailyRhythm_usesChronologicalSevenDayBuckets() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 15, hour: 12)

    try insertPlays(plays, count: 1, startingAt: localEpoch(year: 2024, month: 1, day: 9, hour: 12), track: "first")
    try insertPlays(plays, count: 3, startingAt: now - 10, track: "today")

    let buckets = try StatsQueries(dbq: dbq).recentDailyRhythm(days: 7, now: now)

    XCTAssertEqual(buckets.count, 7)
    XCTAssertEqual(buckets.first?.label, "TUE")
    XCTAssertEqual(buckets.first?.count, 1)
    let today = try XCTUnwrap(buckets.last)
    XCTAssertEqual(today.label, "TODAY")
    XCTAssertEqual(today.count, 3)
    XCTAssertEqual(today.value, 3.0, accuracy: 0.001)
  }

  private func insertPlays(
    _ plays: PlaysDAO,
    count: Int,
    startingAt epoch: Int64,
    track: String
  ) throws {
    for idx in 0..<count {
      try plays.insert(.init(
        playedAt: epoch + Int64(idx),
        trackUri: "\(track):\(idx)",
        msPlayed: 180_000,
        source: "import"))
    }
  }

  private func localEpoch(year: Int, month: Int, day: Int, hour: Int) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(
      year: year,
      month: month,
      day: day,
      hour: hour))!
    return Int64(date.timeIntervalSince1970)
  }
}
