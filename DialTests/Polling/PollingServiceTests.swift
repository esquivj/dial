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
    Task {
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
  }
}

final class FakeClient: PollingClient, @unchecked Sendable {
  let respond: () -> CurrentlyPlaying?
  init(_ respond: @escaping () -> CurrentlyPlaying?) { self.respond = respond }
  func currentlyPlaying() async throws -> CurrentlyPlaying? { respond() }
}
