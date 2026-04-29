import XCTest
@testable import Dial

final class SpotifyDesktopPlaybackObserverTests: XCTestCase {
  func test_desktopNotificationEmitsStartedProgressAndResumed() {
    var previousTrackUri: String?
    var previousPlaybackState: Bool?

    let events = SpotifyDesktopPlaybackObserver.events(
      from: [
        "Player State": "Playing",
        "Track ID": "spotify:track:abc",
        "Name": "Song",
        "Artist": "Artist",
        "Album": "Album",
        "Artwork URL": "https://image",
        "Duration": 180,
        "Playback Position": 12.5,
      ],
      previousTrackUri: &previousTrackUri,
      previousPlaybackState: &previousPlaybackState,
      now: 1_700_000_000)

    XCTAssertEqual(events, [
      .started(
        trackUri: "spotify:track:abc",
        name: "Song",
        artistName: "Artist",
        artistUri: nil,
        artists: [],
        albumName: "Album",
        artUrl: "https://image",
        durationMs: 180_000,
        at: 1_700_000_000),
      .progress(ms: 12_500),
      .resumed,
    ])
  }

  func test_duplicateTrackNotificationDoesNotEmitStartedAgain() {
    var previousTrackUri: String? = "spotify:track:abc"
    var previousPlaybackState: Bool? = true

    let events = SpotifyDesktopPlaybackObserver.events(
      from: [
        "Player State": "Playing",
        "Track ID": "spotify:track:abc",
        "Playback Position": 14,
      ],
      previousTrackUri: &previousTrackUri,
      previousPlaybackState: &previousPlaybackState,
      now: 1_700_000_010)

    XCTAssertEqual(events, [.progress(ms: 14_000)])
  }

  func test_stoppedNotificationClearsPlayback() {
    var previousTrackUri: String? = "spotify:track:abc"
    var previousPlaybackState: Bool? = true

    let events = SpotifyDesktopPlaybackObserver.events(
      from: ["Player State": "Stopped"],
      previousTrackUri: &previousTrackUri,
      previousPlaybackState: &previousPlaybackState,
      now: 1_700_000_020)

    XCTAssertEqual(events, [.noPlayback])
    XCTAssertNil(previousTrackUri)
    XCTAssertNil(previousPlaybackState)
  }
}
