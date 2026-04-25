import Foundation

enum PlaybackEvent: Equatable {
  case started(trackUri: String, name: String, artistName: String, artistUri: String?,
               albumName: String, artUrl: String?, durationMs: Int, at: Int64)
  case progress(ms: Int)
  case paused
  case resumed
  case noPlayback
  case countedPlay(trackUri: String, msPlayed: Int64, at: Int64)
}
