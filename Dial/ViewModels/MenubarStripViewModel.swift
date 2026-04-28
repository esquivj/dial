// Dial/ViewModels/MenubarStripViewModel.swift
import Observation
import Foundation

enum MenubarDisplayState: Equatable { case playing, paused, nothingPlaying }

enum LikedTrackState: Equatable {
  case unknown
  case checking
  case notLiked
  case liked
  case needsReconnect
}

@Observable
final class MenubarStripViewModel {
  var track: NowPlayingViewModel.Track?
  var state: MenubarDisplayState = .nothingPlaying
  var progressMs: Int = 0
  var durationMs: Int = 0
  var playsYTD: Int = 0
  var likedTrackState: LikedTrackState = .unknown
  /// Set whenever a fresh `.progress(ms:)` event lands. Views interpolate
  /// between polls by adding `(now - lastProgressUpdate)` to `progressMs`
  /// while `state == .playing`.
  var lastProgressUpdate: Date? = nil
  /// Current player modes. Updated on every modesChanged event from the
  /// polling service. The optimistic-flip pattern in ControlsBar mutates
  /// these directly when the user taps the toggle, then a subsequent
  /// poll either reaffirms or corrects.
  var shuffle: Bool = false
  var repeatMode: RepeatMode = .off

  var hasSeekableTrack: Bool {
    track != nil && durationMs > 0
  }

  var hasLibraryTrack: Bool {
    track?.uri.hasPrefix("spotify:track:") == true
  }

  func interpolatedProgressMs(at now: Date = Date()) -> Int {
    var ms = progressMs
    if state == .playing, let lastProgressUpdate {
      ms += max(0, Int(now.timeIntervalSince(lastProgressUpdate) * 1000))
    }
    guard durationMs > 0 else { return max(0, ms) }
    return min(durationMs, max(0, ms))
  }

  func setOptimisticProgress(_ ms: Int, at now: Date = Date()) {
    progressMs = durationMs > 0 ? min(durationMs, max(0, ms)) : max(0, ms)
    lastProgressUpdate = now
  }
}
