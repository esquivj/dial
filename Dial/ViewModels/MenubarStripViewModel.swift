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
}
