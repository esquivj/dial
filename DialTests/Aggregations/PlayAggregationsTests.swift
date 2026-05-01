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

  func test_artistAggregatesMergeImportedAndSpotifyIdsByDisplayName() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try tracks.upsert(.init(
      uri: "OLD_KETTAMA",
      name: "Old KETTAMA",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"KETTAMA","uri":"artist:KETTAMA"}]"#))
    try tracks.upsert(.init(
      uri: "LIVE_KETTAMA",
      name: "Live KETTAMA",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"KETTAMA","uri":"spotify:artist:kettama"}]"#))
    try tracks.upsert(.init(
      uri: "OTHER_HIGH",
      name: "Other",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Other","uri":"spotify:artist:other"}]"#))

    try plays.insert(.init(playedAt: now - 100, trackUri: "OLD_KETTAMA", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 90, trackUri: "OLD_KETTAMA", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 80, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 79, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 78, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 77, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 70, trackUri: "OTHER_HIGH", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 60, trackUri: "OTHER_HIGH", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.artistLifetimePlays(artistUri: "spotify:artist:kettama"), 6)
    XCTAssertEqual(try agg.artistRank7d(artistUri: "spotify:artist:kettama"), 1)
  }
}
