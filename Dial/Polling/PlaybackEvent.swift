import Foundation

/// Spotify's repeat state has three values: off, context (= playlist/album
/// loops), track (= current song loops). Mirrors the API's strings exactly
/// for round-trip safety.
enum RepeatMode: String, Equatable {
  case off, context, track
}

struct PlaybackArtist: Equatable, Codable {
  let name: String
  let uri: String
}

enum PlaybackEvent: Equatable {
  case started(trackUri: String, name: String, artistName: String, artistUri: String?,
               artists: [PlaybackArtist], albumName: String, artUrl: String?, durationMs: Int, at: Int64)
  case progress(ms: Int)
  case paused
  case resumed
  case noPlayback
  case countedPlay(trackUri: String, msPlayed: Int64, at: Int64)
  /// Fires only when shuffle or repeat has changed since the last poll —
  /// avoids re-broadcasting the same state every 3s.
  case modesChanged(shuffle: Bool, repeatMode: RepeatMode)
}

enum PlaybackEventSource {
  case poll
  case desktopNotification
}

struct PlaybackStateReduction: Equatable {
  let event: PlaybackEvent
  let trackChanged: Bool
  let generation: Int
}

/// Normalizes the two playback feeds before they mutate UI state.
/// Spotify desktop notifications are fast but occasionally ahead of Web API
/// polling, so a just-after-start stale 204 should not blank the HUD.
struct PlaybackStateReducer {
  private var currentTrackUri: String?
  private var generation = 0
  private var lastDesktopStartAt: Date?
  private var lastCountedKey: String?

  mutating func reduce(
    _ event: PlaybackEvent,
    source: PlaybackEventSource,
    receivedAt: Date = Date()
  ) -> PlaybackStateReduction? {
    switch event {
    case let .started(uri, _, _, _, _, _, _, _, _):
      let changed = currentTrackUri != uri
      currentTrackUri = uri
      if changed {
        generation += 1
        lastCountedKey = nil
      }
      if source == .desktopNotification {
        lastDesktopStartAt = receivedAt
      }
      return PlaybackStateReduction(event: event, trackChanged: changed, generation: generation)

    case .noPlayback:
      if source == .poll,
         currentTrackUri != nil,
         let lastDesktopStartAt,
         receivedAt.timeIntervalSince(lastDesktopStartAt) < 2.0 {
        return nil
      }
      let changed = currentTrackUri != nil
      currentTrackUri = nil
      lastDesktopStartAt = nil
      lastCountedKey = nil
      if changed { generation += 1 }
      return PlaybackStateReduction(event: event, trackChanged: changed, generation: generation)

    case let .countedPlay(uri, _, at):
      guard currentTrackUri == uri else { return nil }
      let key = "\(uri):\(at)"
      guard lastCountedKey != key else { return nil }
      lastCountedKey = key
      return PlaybackStateReduction(event: event, trackChanged: false, generation: generation)

    case .progress:
      guard currentTrackUri != nil else { return nil }
      return PlaybackStateReduction(event: event, trackChanged: false, generation: generation)

    case .paused, .resumed, .modesChanged:
      return PlaybackStateReduction(event: event, trackChanged: false, generation: generation)
    }
  }
}
