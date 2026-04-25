// Dial/ViewModels/NowPlayingViewModel.swift
import Observation

@Observable
final class NowPlayingViewModel {
  struct Track: Equatable {
    var uri: String
    var name: String
    var artistName: String
    var artistUri: String?
    var albumName: String
    var artUrl: String?
  }
  var track: Track?
  var plays30d: Int = 0
  let agg: AggregationsCache
  init(agg: AggregationsCache) { self.agg = agg }
}
