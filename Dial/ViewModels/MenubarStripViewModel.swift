// Dial/ViewModels/MenubarStripViewModel.swift
import Observation
import Foundation

enum MenubarDisplayState { case playing, paused, nothingPlaying }

@Observable
final class MenubarStripViewModel {
  var track: NowPlayingViewModel.Track?
  var state: MenubarDisplayState = .nothingPlaying
  var progressMs: Int = 0
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
}
