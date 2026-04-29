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
