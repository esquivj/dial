// Dial/ViewModels/MenubarStripViewModel.swift
import Observation

enum MenubarDisplayState { case playing, paused, nothingPlaying }

@Observable
final class MenubarStripViewModel {
  var track: NowPlayingViewModel.Track?
  var state: MenubarDisplayState = .nothingPlaying
  var progressMs: Int = 0
}
