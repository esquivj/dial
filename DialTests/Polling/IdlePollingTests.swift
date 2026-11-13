import XCTest
@testable import Dial

/// PLA-102: with nothing playing, Dial stops asking Spotify every 2 s.
final class IdlePollingTests: XCTestCase {
  private typealias World = SimulatedSpotify

  private func count(_ run: SimulationRun, _ match: (PlaybackEvent) -> Bool) -> Int {
    run.events.filter(match).count
  }

  func test_appClosed_nothingPlaying_backsOffTo15ThenThirtySeconds() async throws {
    let world = World()
    world.appRunning = []

    let run = try await world.runCurrent(for: 600)

    // 0–120 s every 15 s (9 calls), then every 30 s to 600 s (16 calls).
    // The old loop asked every 2 s: 300 calls.
    XCTAssertGreaterThanOrEqual(run.webCalls, 20)
    XCTAssertLessThanOrEqual(run.webCalls, 30, "web calls: \(run.webCalls)")
    XCTAssertEqual(count(run) { $0 == .noPlayback }, 1, "an unchanged answer isn't republished")
  }

  func test_appClosed_playbackStartsOnPhone_returnsToFastPolling() async throws {
    let world = World()
    world.appRunning = []
    let track = World.track("p", seconds: 200)
    // Nothing for 5 minutes, then the phone starts playing.
    world.segments.append(.init(start: 300, end: 500, device: .phone, track: track,
                                startProgressMs: 0, playing: true))

    let run = try await world.runCurrent(for: 500)

    let startedAt = run.events.compactMap { event -> Int64? in
      if case let .started(uri, _, _, _, _, _, _, _, at) = event, uri == track.uri { return at }
      return nil
    }.first
    let start = try XCTUnwrap(startedAt)
    let secondsIn = Double(start) - world.t0.timeIntervalSince1970
    XCTAssertLessThanOrEqual(secondsIn, 300 + 30 + 1, "noticed within one deep-idle poll")
    XCTAssertEqual(run.countedUris, [track.uri], "fast polling resumed and the play counted")
    // Idle stretch ~15 calls; playing stretch at 2 s adds ~85.
    XCTAssertGreaterThan(run.webCalls, 80, "back to the 2 s cadence while playing")
  }

  func test_appOpenAndPaused_remoteChecksBackOff() async throws {
    let world = World()
    let track = World.track("idle", seconds: 200)
    world.pause(track, atMs: 40_000, for: 610)

    let run = try await world.runCurrent(for: 600)

    // Remote-device checks were every 10 s (60 calls); now 15 s, then 30 s.
    XCTAssertLessThanOrEqual(run.webCalls, 30, "web calls: \(run.webCalls)")
    let progress = count(run) { if case .progress = $0 { return true } else { return false } }
    XCTAssertLessThanOrEqual(progress, 1, "a paused position that doesn't move isn't republished")
  }

  func test_appClosed_playingStaysOnTheTwoSecondCadence() async throws {
    let world = World()
    world.appRunning = []
    world.play(World.track("q", seconds: 200), on: .phone, for: 200)

    let run = try await world.runCurrent(for: 200)

    XCTAssertGreaterThanOrEqual(run.webCalls, 90, "web calls: \(run.webCalls)")
  }

  func test_wakeAsksTheWebAPIRightAway() async throws {
    let lock = NSLock()
    var calls = 0
    let client = FakeClient {
      lock.lock(); calls += 1; lock.unlock()
      return nil
    }
    var timing = PollingTiming.standard(webInterval: 2)
    timing.idleWebInterval = 60
    timing.deepIdleWebInterval = 60
    let svc = PollingService(client: client, interval: 2, timing: timing, clock: { 1_700_000_000 })
    let task = Task { for try await _ in svc.stream() {} }
    defer { task.cancel() }

    try await waitUntil { lock.withLock { calls } >= 1 }   // "nothing playing": next ask in 60 s
    try await Task.sleep(nanoseconds: 200_000_000)
    let before = lock.withLock { calls }
    XCTAssertEqual(before, 1, "idle: no second call without a wake")
    svc.wake()
    try await waitUntil { lock.withLock { calls } > before }
  }

  private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline { XCTFail("timed out"); return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}
