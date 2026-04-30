// Dial/ViewModels/NowPlayingViewModel.swift
import Observation

@Observable
final class NowPlayingViewModel {
  struct Track: Equatable {
    var uri: String
    var name: String
    var artistName: String
    var artistUri: String?
    var artistUris: [String]
    var albumName: String
    var artUrl: String?

    init(
      uri: String,
      name: String,
      artistName: String,
      artistUri: String?,
      artistUris: [String]? = nil,
      albumName: String,
      artUrl: String?
    ) {
      self.uri = uri
      self.name = name
      self.artistName = artistName
      self.artistUri = artistUri
      self.artistUris = artistUris ?? artistUri.map { [$0] } ?? []
      self.albumName = albumName
      self.artUrl = artUrl
    }
  }
  var track: Track?
  var playsYTD: Int = 0
  var soundTheme: DialThemeID = .classic
  var soundThemeDecision: SoundThemeDecision?
  let agg: AggregationsCache
  init(agg: AggregationsCache) { self.agg = agg }
}
