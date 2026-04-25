// Dial/ViewModels/AppCoordinator.swift
import Observation
import Foundation
import GRDB

@Observable
final class AppCoordinator {
  let dbq: DatabaseQueue
  let client: SpotifyClient
  let poller: PollingService
  let engine: PetEngine
  let aggCache: AggregationsCache
  let nowPlaying: NowPlayingViewModel
  let menubar: MenubarStripViewModel
  let pet: PetViewModel
  let settings: SettingsViewModel

  init(dbq: DatabaseQueue, client: SpotifyClient, auth: SpotifyAuthService) {
    self.dbq = dbq
    self.client = client
    self.engine = PetEngine(dbq: dbq)
    self.aggCache = AggregationsCache(agg: PlayAggregations(dbq: dbq))
    self.poller = PollingService(client: client, interval: 3.0)
    self.nowPlaying = NowPlayingViewModel(agg: aggCache)
    self.menubar = MenubarStripViewModel()
    self.pet = PetViewModel()
    self.settings = SettingsViewModel(auth: auth, dbq: dbq)
    self.pet.syncFromStore(dbq: dbq)
  }

  /// Starts the polling loop. Call once on app launch (after auth is ready).
  func start() {
    Task {
      do {
        for try await event in poller.stream() {
          await handle(event)
        }
      } catch {
        print("[AppCoordinator] polling error: \(error)")
      }
    }
  }

  private func handle(_ event: PlaybackEvent) async {
    switch event {
    case let .started(uri, name, artistName, artistUri, albumName, artUrl, _, _):
      let track = NowPlayingViewModel.Track(
        uri: uri, name: name, artistName: artistName, artistUri: artistUri,
        albumName: albumName, artUrl: artUrl)
      nowPlaying.track = track
      menubar.track = track
      menubar.state = .playing
      aggCache.refresh(trackUri: uri, artistUri: artistUri)
      nowPlaying.plays30d = aggCache.plays30d
      // BPM lookup is best-effort for the beat-sync animation.
      if let trackId = uri.split(separator: ":").last,
         let features = try? await client.audioFeatures(trackId: String(trackId)) {
        pet.currentBPM = features.tempo
      }
      resolvePetBehavior()

    case .paused:
      menubar.state = .paused
      resolvePetBehavior()

    case .resumed:
      menubar.state = .playing
      resolvePetBehavior()

    case .noPlayback:
      menubar.state = .nothingPlaying
      resolvePetBehavior()

    case let .progress(ms):
      menubar.progressMs = ms

    case let .countedPlay(uri, ms, at):
      try? engine.recordPlay(.init(playedAt: at, trackUri: uri, msPlayed: ms, source: "live"))
      aggCache.refresh(trackUri: uri, artistUri: nowPlaying.track?.artistUri)
      nowPlaying.plays30d = aggCache.plays30d
      pet.syncFromStore(dbq: dbq)
      resolvePetBehavior()
    }
  }

  private func resolvePetBehavior() {
    let ctx = PetContext(
      playing: menubar.state == .playing,
      paused:  menubar.state == .paused,
      firstListen: aggCache.firstListen,
      rediscovered: aggCache.rediscovered,
      leveledUp: pet.justLeveledUp,
      lastPlayAt: pet.lastPlayAt,
      now: Int64(Date().timeIntervalSince1970),
      bpm: pet.currentBPM
    )
    pet.behavior = PetBehaviorResolver.resolve(ctx)
  }
}
