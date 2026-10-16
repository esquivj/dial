import XCTest
import GRDB
@testable import Dial

final class FlowTests: XCTestCase {
  func test_scriptedPolling_populatesAggregationsAndPet() async throws {
    let dbq = try InMemoryDatabase.make()
    var scripted: [CurrentlyPlaying?] = [
      .init(item: .init(uri: "spotify:track:NEW", name: "N", duration_ms: 200000,
                        artists: [.init(name: "CP", uri: "spotify:artist:CP")],
                        album: .init(name: "Pang", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 5_000),
      .init(item: .init(uri: "spotify:track:NEW", name: "N", duration_ms: 200000,
                        artists: [.init(name: "CP", uri: "spotify:artist:CP")],
                        album: .init(name: "Pang", images: [.init(url: "http://a")])),
            is_playing: true, progress_ms: 45_000)   // crosses 30s → counted
    ]
    let lock = NSLock()
    let client = FakeFlowClient {
      lock.lock(); defer { lock.unlock() }
      return scripted.isEmpty ? nil : scripted.removeFirst()
    }
    let poller = PollingService(client: client, interval: 0, clock: { 1_700_000_000 })
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    let tracks = TracksDAO(dbq: dbq)

    var events: [PlaybackEvent] = []
    let exp = expectation(description: "started + counted observed")
    _ = Task {
      var seenStarted = false
      var seenCounted = false
      for try await e in poller.stream() {
        if case let .started(uri, _, _, _, _, albumName, _, _, _) = e {
          try? tracks.upsert(.init(
            uri: uri, name: "N", albumName: albumName, albumArtUrl: nil,
            durationMs: 200000,
            artistsJson: #"[{"name":"CP","uri":"spotify:artist:CP"}]"#))
          seenStarted = true
        }
        if case .countedPlay = e {
          _ = try? engine.recordPlay(.init(
            playedAt: 1_700_000_000,
            trackUri: "spotify:track:NEW",
            msPlayed: 45_000,
            source: "live"))
          seenCounted = true
        }
        events.append(e)
        if seenStarted && seenCounted { exp.fulfill(); break }
      }
    }
    await fulfillment(of: [exp], timeout: 5)

    let agg = PlayAggregations(dbq: dbq, now: { 1_700_000_000 })
    XCTAssertEqual(try agg.plays30d(trackUri: "spotify:track:NEW"), 1)
    XCTAssertEqual(try agg.playsYTD(trackUri: "spotify:track:NEW"), 1)
    XCTAssertTrue(try agg.firstListen(trackUri: "spotify:track:NEW"))

    let state = try PetStateDAO(dbq: dbq).get()
    XCTAssertGreaterThan(state.xp, 0)
  }
}

private final class FakeFlowClient: PollingClient, @unchecked Sendable {
  let respond: () -> CurrentlyPlaying?
  init(_ respond: @escaping () -> CurrentlyPlaying?) { self.respond = respond }
  func currentlyPlaying() async throws -> CurrentlyPlaying? { respond() }
}
