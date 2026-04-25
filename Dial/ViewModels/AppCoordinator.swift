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

  /// Idempotent guard so `start()` can be called from launch (when already signed in)
  /// or from `signIn()` (after auth completes) without double-tasking the polling loop.
  private var pollingStarted = false

  init(dbq: DatabaseQueue, client: SpotifyClient, auth: SpotifyAuthService, tokenStore: TokenStore) {
    self.dbq = dbq
    self.client = client
    self.engine = PetEngine(dbq: dbq)
    self.aggCache = AggregationsCache(agg: PlayAggregations(dbq: dbq))
    self.poller = PollingService(client: client, interval: 3.0)
    self.nowPlaying = NowPlayingViewModel(agg: aggCache)
    self.menubar = MenubarStripViewModel()
    self.pet = PetViewModel()
    self.settings = SettingsViewModel(auth: auth, dbq: dbq, tokenStore: tokenStore)
    self.pet.syncFromStore(dbq: dbq)
  }

  /// Starts the polling loop. Idempotent — second call is a no-op.
  /// Caller must ensure a Spotify token exists in the keychain before calling.
  func start() {
    guard !pollingStarted else { return }
    pollingStarted = true
    Task {
      do {
        for try await event in poller.stream() {
          await handle(event)
        }
      } catch {
        print("[AppCoordinator] polling error: \(error)")
      }
    }
    // Backfill any track URIs that are referenced from `plays` but have no
    // metadata in `tracks`. Runs in the background, low priority — the
    // dropdown stays usable while it works through the queue.
    Task(priority: .background) {
      do {
        try await MetadataEnricher(dbq: dbq, client: client).enrichMissing()
      } catch {
        print("[AppCoordinator] metadata backfill error: \(error)")
      }
    }
  }

  /// Composes the full sign-in flow: OAuth → mark signed in → start polling.
  /// Called from the Settings "Connect Spotify" button.
  @MainActor
  func signIn() async throws {
    _ = try await settings.auth.signIn()
    settings.markSignedIn()
    start()
  }

  private func handle(_ event: PlaybackEvent) async {
    switch event {
    case let .started(uri, name, artistName, artistUri, albumName, artUrl, durationMs, _):
      // Persist track metadata so the SQL joins in `artistRank7d`,
      // `artistLifetimePlays`, and the PetEngine variety detection work.
      // Without this, the `tracks` table stays empty for live-only sessions.
      let artistsJson: String? = {
        guard let aUri = artistUri else { return nil }
        let safeName = artistName
          .replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "\"", with: "\\\"")
        return "[{\"name\":\"\(safeName)\",\"uri\":\"\(aUri)\"}]"
      }()
      try? TracksDAO(dbq: dbq).upsert(.init(
        uri: uri, name: name, albumName: albumName,
        albumArtUrl: artUrl, durationMs: Int64(durationMs),
        artistsJson: artistsJson))

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
      menubar.lastProgressUpdate = Date()

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
