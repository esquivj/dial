import XCTest
@testable import Dial

final class PlaybackStateReducerTests: XCTestCase {
  func test_pollNoPlaybackImmediatelyAfterDesktopStartIsIgnored() {
    var reducer = PlaybackStateReducer()
    let now = Date(timeIntervalSince1970: 100)

    let started = reducer.reduce(
      .started(
        trackUri: "spotify:track:A",
        name: "A",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: nil,
        durationMs: 180_000,
        at: 100),
      source: .desktopNotification,
      receivedAt: now)

    XCTAssertEqual(started?.trackChanged, true)
    XCTAssertNil(reducer.reduce(.noPlayback, source: .poll, receivedAt: now.addingTimeInterval(0.8)))
  }

  func test_pollNoPlaybackAfterDesktopGraceClearsState() {
    var reducer = PlaybackStateReducer()
    let now = Date(timeIntervalSince1970: 100)

    _ = reducer.reduce(
      .started(
        trackUri: "spotify:track:A",
        name: "A",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: nil,
        durationMs: 180_000,
        at: 100),
      source: .desktopNotification,
      receivedAt: now)

    let cleared = reducer.reduce(.noPlayback, source: .poll, receivedAt: now.addingTimeInterval(2.2))
    XCTAssertEqual(cleared?.event, .noPlayback)
    XCTAssertEqual(cleared?.trackChanged, true)
  }

  func test_staleCountedPlayForPreviousTrackIsIgnored() {
    var reducer = PlaybackStateReducer()

    _ = reducer.reduce(
      .started(
        trackUri: "spotify:track:A",
        name: "A",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: nil,
        durationMs: 180_000,
        at: 100),
      source: .poll)
    _ = reducer.reduce(
      .started(
        trackUri: "spotify:track:B",
        name: "B",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: nil,
        durationMs: 180_000,
        at: 110),
      source: .poll)

    XCTAssertNil(reducer.reduce(
      .countedPlay(trackUri: "spotify:track:A", msPlayed: 90_000, at: 120),
      source: .poll))
  }

  func test_duplicateCountedPlayForSameTrackAndTimestampIsIgnored() {
    var reducer = PlaybackStateReducer()

    _ = reducer.reduce(
      .started(
        trackUri: "spotify:track:A",
        name: "A",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: nil,
        durationMs: 180_000,
        at: 100),
      source: .poll)

    XCTAssertNotNil(reducer.reduce(
      .countedPlay(trackUri: "spotify:track:A", msPlayed: 90_000, at: 120),
      source: .poll))
    XCTAssertNil(reducer.reduce(
      .countedPlay(trackUri: "spotify:track:A", msPlayed: 90_000, at: 120),
      source: .poll))
  }
}
