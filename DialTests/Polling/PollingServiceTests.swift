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
    let svc = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })
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

  func test_refreshRejectedRetriesThenSurfacesWithoutImmediateSignOut() async {
    var calls = 0
    let lock = NSLock()
    let client = ThrowingFakeClient {
      lock.lock(); defer { lock.unlock() }
      calls += 1
      throw SpotifyAuthError.refreshRejected(400)
    }
    let svc = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })

    do {
      for try await _ in svc.stream() {}
      XCTFail("stream should finish with refreshRejected")
    } catch let error as SpotifyAuthError {
      XCTAssertEqual(error, .refreshRejected(400))
    } catch {
      XCTFail("unexpected error: \(error)")
    }

    XCTAssertEqual(calls, 3)
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
