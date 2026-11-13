import XCTest
@testable import Dial

final class PollingServiceTests: XCTestCase {
  func test_scriptedPolls_emitStartedAndCountedPlay() async throws {
    var scripted: [CurrentlyPlaying?] = [
      nil,  // no playback
      .init(item: .init(uri: "T", name: "Track", duration_ms: 200000,
                        artists: [.init(name: "A", uri: "spotify:artist:A")],
                        album: .init(name: "Al", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 5_000),
      .init(item: .init(uri: "T", name: "Track", duration_ms: 200000,
                        artists: [.init(name: "A", uri: "spotify:artist:A")],
                        album: .init(name: "Al", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 35_000)   // crosses 30s → count
    ]
    let lock = NSLock()
    let client = FakeClient {
      lock.lock(); defer { lock.unlock() }
      return scripted.isEmpty ? nil : scripted.removeFirst()
    }
    // About counting, not cadence: no idle back-off between scripted polls.
    var timing = PollingTiming.standard(webInterval: 0)
    timing.idleWebInterval = 0
    timing.deepIdleWebInterval = 0
    let svc = PollingService(client: client, interval: 0, timing: timing, clock: { 1_700_000_000 })
    var events: [PlaybackEvent] = []
    let exp = expectation(description: "events received")
    exp.expectedFulfillmentCount = 1
    _ = Task {
      var seenStarted = false
      var seenCounted = false
      for try await e in svc.stream() {
        events.append(e)
        if case .started = e { seenStarted = true }
        if case .countedPlay = e { seenCounted = true }
        if seenStarted && seenCounted { exp.fulfill(); break }
      }
    }
    await fulfillment(of: [exp], timeout: 5.0)
    XCTAssertTrue(events.contains(.noPlayback))
    XCTAssertTrue(events.contains(where: { if case .started = $0 { return true } else { return false } }))
    XCTAssertTrue(events.contains(where: { if case .countedPlay = $0 { return true } else { return false } }))
    XCTAssertTrue(events.contains(.countedPlay(trackUri: "T", msPlayed: 35_000, at: 1_699_999_965)))
  }

  func test_firstObservationPastThresholdDoesNotEmitCountedPlay() async throws {
    var scripted: [CurrentlyPlaying?] = [
      .init(item: .init(uri: "T", name: "Track", duration_ms: 200000,
                        artists: [.init(name: "A", uri: "spotify:artist:A")],
                        album: .init(name: "Al", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 35_000),
      .init(item: .init(uri: "T", name: "Track", duration_ms: 200000,
                        artists: [.init(name: "A", uri: "spotify:artist:A")],
                        album: .init(name: "Al", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 40_000)
    ]
    let lock = NSLock()
    let client = FakeClient {
      lock.lock(); defer { lock.unlock() }
      return scripted.isEmpty ? nil : scripted.removeFirst()
    }
    let svc = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })
    var events: [PlaybackEvent] = []
    let exp = expectation(description: "two poll observations received")
    _ = Task {
      for try await e in svc.stream() {
        events.append(e)
        if events.count >= 5 {
          exp.fulfill()
          break
        }
      }
    }
    await fulfillment(of: [exp], timeout: 5.0)

    XCTAssertTrue(events.contains(where: { if case .started = $0 { return true } else { return false } }))
    XCTAssertFalse(events.contains(where: { if case .countedPlay = $0 { return true } else { return false } }))
  }

  func test_refreshRejectedSurfacesNeedsAttentionAndKeepsPolling() async throws {
    var calls = 0
    var states: [WebAuthState] = []
    let lock = NSLock()
    let client = ThrowingFakeClient {
      lock.lock(); defer { lock.unlock() }
      calls += 1
      if calls <= 4 { throw SpotifyAuthError.refreshRejected(400) }
      return Self.playing(progressMs: 5_000)
    }
    let svc = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })
    svc.onWebAuthChange = { state in
      lock.lock(); states.append(state); lock.unlock()
    }

    // The stream outlives the rejections and delivers the next good read.
    for try await e in svc.stream() {
      if case .started = e { break }
    }

    let (finalCalls, finalStates) = lock.withLock { (calls, states) }
    XCTAssertGreaterThanOrEqual(finalCalls, 5, "polling continued past the rejections")
    XCTAssertEqual(finalStates, [.needsAttention, .ok])
  }

  func test_missingTokenPausesWebReadsUntilRetry() async throws {
    var calls = 0
    var signedIn = false
    let lock = NSLock()
    let client = ThrowingFakeClient {
      lock.lock(); defer { lock.unlock() }
      calls += 1
      guard signedIn else { throw SpotifyAuthError.missingStoredToken }
      return Self.playing(progressMs: 5_000)
    }
    let svc = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })
    let signedOut = expectation(description: "signed out reported")
    svc.onWebAuthChange = { state in
      if state == .signedOut { signedOut.fulfill() }
    }
    let started = expectation(description: "playback read after retry")
    let task = Task {
      for try await e in svc.stream() {
        if case .started = e { started.fulfill(); break }
      }
    }
    defer { task.cancel() }

    await fulfillment(of: [signedOut], timeout: 5.0)
    try await Task.sleep(nanoseconds: 300_000_000)
    let callsWhileSignedOut = lock.withLock { () -> Int in
      signedIn = true
      return calls
    }
    XCTAssertEqual(callsWhileSignedOut, 1, "no Web API calls while there is no token")

    svc.retryWebNow()
    await fulfillment(of: [started], timeout: 5.0)
  }

  private static func playing(progressMs: Int) -> CurrentlyPlaying {
    .init(item: .init(uri: "T", name: "Track", duration_ms: 200000,
                      artists: [.init(name: "A", uri: "spotify:artist:A")],
                      album: .init(name: "Al", images: [.init(url: "http://a")])),
          is_playing: true, progress_ms: progressMs)
  }
}

final class FakeClient: PollingClient, @unchecked Sendable {
  let respond: () -> CurrentlyPlaying?
  init(_ respond: @escaping () -> CurrentlyPlaying?) { self.respond = respond }
  func currentlyPlaying() async throws -> CurrentlyPlaying? { respond() }
}

final class ThrowingFakeClient: PollingClient, @unchecked Sendable {
  let respond: () throws -> CurrentlyPlaying?
  init(_ respond: @escaping () throws -> CurrentlyPlaying?) { self.respond = respond }
  func currentlyPlaying() async throws -> CurrentlyPlaying? { try respond() }
}
