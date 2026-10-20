// DialTests/Sync/PlayTwinMatcherTests.swift
import XCTest
import GRDB
@testable import Dial

final class PlayTwinMatcherTests: XCTestCase {
  private let t: Int64 = 1_700_000_000
  private let threeMinutes: Int64 = 180_000

  private func live(_ at: Int64, ms: Int64 = 31_000) -> PlayTwinMatcher.Stamp {
    .init(playedAt: at, msPlayed: ms, source: "live")
  }
  private func recent(_ at: Int64, ms: Int64 = 180_000) -> PlayTwinMatcher.Stamp {
    .init(playedAt: at, msPlayed: ms, source: RecentPlaysReconciler.source)
  }
  private func imported(_ at: Int64, ms: Int64) -> PlayTwinMatcher.Stamp {
    .init(playedAt: at, msPlayed: ms, source: "import")
  }
  private func same(_ a: PlayTwinMatcher.Stamp, _ b: PlayTwinMatcher.Stamp, durationMs: Int64? = 180_000) -> Bool {
    let forward = PlayTwinMatcher.isSameListen(a, b, durationMs: durationMs)
    XCTAssertEqual(forward, PlayTwinMatcher.isSameListen(b, a, durationMs: durationMs), "rule must be symmetric")
    return forward
  }

  func test_exactKeyIsAlwaysTheSameListen() {
    XCTAssertTrue(same(recent(t), recent(t)))
    XCTAssertTrue(same(imported(t, ms: 5_000), imported(t, ms: 5_000)))
  }

  func test_liveRowsFromTwoMacs_matchWithinSeconds() {
    XCTAssertTrue(same(live(t), live(t + 3, ms: 32_500)))
    XCTAssertTrue(same(live(t), live(t - 8)))
  }

  func test_backToBackLiveReplays_stayTwoPlays() {
    // The replay starts one track later; estimates can land a little early.
    XCTAssertFalse(same(live(t), live(t + 180)))
    XCTAssertFalse(same(live(t), live(t + 177)))
  }

  func test_liveTolerance_isHalfTheTrackAtMostAMinute() {
    XCTAssertEqual(PlayTwinMatcher.liveToleranceSec(durationMs: 180_000), 60)
    XCTAssertEqual(PlayTwinMatcher.liveToleranceSec(durationMs: 20_000), 10)
    XCTAssertEqual(PlayTwinMatcher.liveToleranceSec(durationMs: nil), 60)
    // A 20 s track looped: replays 20 s apart stay separate.
    XCTAssertFalse(same(live(t), live(t + 20), durationMs: 20_000))
    XCTAssertTrue(same(live(t), live(t + 3), durationMs: 20_000))
  }

  func test_recentRow_matchesItsLiveTwinLikeCountedPlays() {
    // Recently played is stamped at the end; the live row near the start.
    XCTAssertTrue(same(recent(t + 180), live(t - 2)))
    XCTAssertTrue(same(recent(t + 180), live(t)))
    // Outside the v18 window.
    XCTAssertFalse(same(recent(t + 180), live(t - 10)))
  }

  func test_recentRowsOrImportsWithDifferentKeys_areDifferentListens() {
    XCTAssertFalse(same(recent(t), recent(t + 1)))
    XCTAssertFalse(same(imported(t, ms: 180_000), imported(t + 1, ms: 180_000)))
  }

  func test_countedImport_matchesTheLivePlayThatStartedWhenItsListenDid() {
    // Listened 3 minutes, stopped at t + 180: started at t.
    XCTAssertTrue(same(imported(t + 180, ms: threeMinutes), live(t + 2)))
    // Partial listen: 45 s, stopped at t + 45.
    XCTAssertTrue(same(imported(t + 45, ms: 45_000), live(t - 1)))
    // The next listen starts when this one ended: not a twin.
    XCTAssertFalse(same(imported(t + 180, ms: threeMinutes), live(t + 180)))
  }

  func test_importedSkip_isNeverATwin() {
    // A 10 s skip doesn't count, so the full live play right after it stays.
    XCTAssertFalse(same(imported(t + 10, ms: 10_000), live(t + 10)))
    XCTAssertFalse(same(imported(t + 10, ms: 10_000), live(t)))
  }

  func test_twinExists_searchesTheNamedSchema() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO plays (played_at, track_uri, ms_played, source)
        VALUES (?, 'spotify:track:A', 31000, 'live'),
               (?, 'spotify:track:B', 31000, 'live')
        """, arguments: [t, t + 400])
    }

    try dbq.read { db in
      XCTAssertTrue(try PlayTwinMatcher.twinExists(
        of: live(t + 4), trackUri: "spotify:track:A", durationMs: 180_000, in: "main", db: db))
      XCTAssertFalse(try PlayTwinMatcher.twinExists(
        of: live(t + 180), trackUri: "spotify:track:A", durationMs: 180_000, in: "main", db: db))
      XCTAssertFalse(try PlayTwinMatcher.twinExists(
        of: live(t + 4), trackUri: "spotify:track:B", durationMs: 180_000, in: "main", db: db))
    }
  }
}
