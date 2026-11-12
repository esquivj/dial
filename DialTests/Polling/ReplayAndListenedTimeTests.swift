import XCTest
import GRDB
@testable import Dial

/// PLA-101: a song played twice in a row is two plays, and a live play
/// stores the time actually heard, not the ~30 s at which it counted.
final class ReplayAndListenedTimeTests: XCTestCase {
  private typealias World = SimulatedSpotify

  private func ended(_ run: SimulationRun) -> [(uri: String, at: Int64, ms: Int64)] {
    run.events.compactMap {
      if case let .playEnded(uri, at, ms) = $0 { return (uri, at, ms) } else { return nil }
    }
  }

  // MARK: Polling

  func test_backToBackReplay_countsTwice_andEachPlayEndsNearTheTrackLength() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 120)
    let world = World()
    world.play(a, for: 200).play(a, for: 200).play(b, for: 60)

    let run = try await world.runCurrent(for: world.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, a.uri, b.uri])
    XCTAssertEqual(run.events.filter { $0 == .restarted(trackUri: a.uri) }.count, 1)
    let plays = run.countedPlays.filter { $0.uri == a.uri }
    XCTAssertGreaterThanOrEqual(plays[1].at - plays[0].at, 190, "the replay starts about one track later")
    let endings = ended(run).filter { $0.uri == a.uri }
    XCTAssertEqual(endings.map(\.at), plays.map(\.at), "each play ends under its own stamp")
    for ending in endings {
      XCTAssertGreaterThanOrEqual(ending.ms, 190_000)
      XCTAssertLessThanOrEqual(ending.ms, 200_000, "capped at the track length")
    }
  }

  func test_skipPartWay_storesTheTimeHeard() async throws {
    let a = World.track("a", seconds: 240), b = World.track("b", seconds: 120)
    let world = World()
    world.play(a, for: 90).play(b, for: 60)

    let run = try await world.runCurrent(for: world.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri])
    let a0 = try XCTUnwrap(ended(run).first { $0.uri == a.uri })
    XCTAssertEqual(a0.ms, 90_000, accuracy: 3_000)
    XCTAssertEqual(a0.at, run.countedPlays[0].at)
  }

  func test_pauseAndResume_isOnePlay_withTheWholeListen() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 120)
    let world = World()
    world.play(a, for: 40).pause(a, atMs: 40_000, for: 60).play(a, for: 160, fromMs: 40_000).play(b, for: 40)

    let run = try await world.runCurrent(for: world.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri])
    XCTAssertEqual(try XCTUnwrap(ended(run).first { $0.uri == a.uri }).ms, 200_000, accuracy: 3_000)
  }

  func test_seekBackEarlyInTheSong_staysOnePlay() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 120)
    let world = World()
    // Counted at 30 s, then restarted from the top at 45 s: not half heard yet.
    world.play(a, for: 45).play(a, for: 200).play(b, for: 40)

    let run = try await world.runCurrent(for: world.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri])
    XCTAssertFalse(run.events.contains(.restarted(trackUri: a.uri)))
  }

  func test_strayReadingAtTheTop_doesNotCountTheSameListenTwice() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 120)
    let world = World()
    // Mostly heard, one reading at 0:00, then straight back to where it was.
    world.play(a, for: 120).play(a, for: 2).play(a, for: 78, fromMs: 122_000).play(b, for: 40)

    let run = try await world.runCurrent(for: world.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri])
  }

  func test_reducerPassesRestartForTheCurrentTrackOnly() {
    var reducer = PlaybackStateReducer()
    _ = reducer.reduce(.started(trackUri: "t", name: "T", artistName: "A", artistUri: nil, artists: [],
                                albumName: "", artUrl: nil, durationMs: 1, at: 0), source: .poll)
    XCTAssertNotNil(reducer.reduce(.restarted(trackUri: "t"), source: .poll))
    XCTAssertNil(reducer.reduce(.restarted(trackUri: "other"), source: .poll))
    XCTAssertNotNil(reducer.reduce(.playEnded(trackUri: "other", at: 0, msPlayed: 1), source: .poll))
  }

  // MARK: Recording

  private func engineWithTrack(durationMs: Int) throws -> (DatabaseQueue, PetEngine) {
    let dbq = try InMemoryDatabase.make()
    try TracksDAO(dbq: dbq).upsert(.init(
      uri: "T", name: "Song", albumName: "Album", albumArtUrl: nil, durationMs: Int64(durationMs),
      artistsJson: #"[{"name":"Artist","uri":"art:a"}]"#))
    return (dbq, PetEngine(dbq: dbq, clock: { 1_700_000_000 }))
  }

  private func liveRows(_ dbq: DatabaseQueue) throws -> [Int64] {
    try dbq.read { db in try Int64.fetchAll(db, sql: "SELECT ms_played FROM plays ORDER BY played_at") }
  }

  func test_recordPlay_keepsAReplayThatStartsJustUnderOneTrackLengthLater() throws {
    let (dbq, engine) = try engineWithTrack(durationMs: 200_000)
    let t: Int64 = 1_700_000_000
    XCTAssertTrue(try engine.recordPlay(.init(playedAt: t, trackUri: "T", msPlayed: 30_000, source: "live")))
    // Both starts are estimates, so a replay can land a few seconds short.
    XCTAssertTrue(try engine.recordPlay(.init(playedAt: t + 196, trackUri: "T", msPlayed: 30_000, source: "live")))
    XCTAssertEqual(try liveRows(dbq).count, 2)
  }

  func test_recordPlay_stillDropsTheRelaunchDuplicate() throws {
    let (dbq, engine) = try engineWithTrack(durationMs: 200_000)
    let t: Int64 = 1_700_000_000
    XCTAssertTrue(try engine.recordPlay(.init(playedAt: t, trackUri: "T", msPlayed: 30_000, source: "live")))
    XCTAssertFalse(try engine.recordPlay(.init(playedAt: t + 3, trackUri: "T", msPlayed: 31_000, source: "live")))
    XCTAssertEqual(try liveRows(dbq).count, 1)
  }

  func test_updateListenedTime_onlyGrowsTheLivePlay() throws {
    let (dbq, engine) = try engineWithTrack(durationMs: 200_000)
    let t: Int64 = 1_700_000_000
    try engine.recordPlay(.init(playedAt: t, trackUri: "T", msPlayed: 30_000, source: "live"))

    try engine.updateListenedTime(trackUri: "T", playedAt: t, msPlayed: 187_000)
    XCTAssertEqual(try liveRows(dbq), [187_000])
    try engine.updateListenedTime(trackUri: "T", playedAt: t, msPlayed: 40_000)
    XCTAssertEqual(try liveRows(dbq), [187_000], "a later, shorter reading never shrinks it")
    try engine.updateListenedTime(trackUri: "T", playedAt: t + 999, msPlayed: 200_000)
    XCTAssertEqual(try liveRows(dbq), [187_000], "no play with that stamp: nothing changes")
  }

  // MARK: Last.fm

  func test_scrobbleTracker_replayScrobblesAgain() {
    let track = ScrobbleTracker.Track(uri: "spotify:track:t", artist: "A", name: "T", album: nil, durationMs: 200_000)
    var tracker = ScrobbleTracker()
    _ = tracker.started(track)
    _ = tracker.resumed()
    _ = tracker.progress(120_000)
    XCTAssertEqual(tracker.counted(playId: 1, uri: track.uri, msPlayed: 30_000),
                   [.scrobble(.init(playId: 1, track: track))])

    _ = tracker.restarted(uri: track.uri)
    _ = tracker.progress(110_000)
    XCTAssertEqual(tracker.counted(playId: 2, uri: track.uri, msPlayed: 30_000),
                   [.scrobble(.init(playId: 2, track: track))])
  }
}
