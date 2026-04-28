// Dial/ViewModels/AppCoordinator.swift
import Observation
import Foundation
import GRDB
import os.log

private let coordLog = Logger(subsystem: "com.dial.Dial", category: "AppCoordinator")

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
  let artworkCache: ArtworkCache
  /// Owns the system-audio capture + FFT pipeline that drives the spectrum
  /// visualizer. Idle until the visualizer view first appears, at which
  /// point `start()` is called and the engine triggers the Screen Recording
  /// permission prompt (first launch only).
  let visualizer: VisualizerEngine = .init()

  /// Which screen the dropdown is showing. Lifted to the coordinator so the
  /// status item's right-click menu can jump straight to History or Stats
  /// without going through the SwiftUI view's local @State (which can't be
  /// driven from outside the view tree).
  var dropdownScreen: DropdownScreen = .hud

  /// Idempotent guard so `start()` can be called from launch (when already signed in)
  /// or from `signIn()` (after auth completes) without double-tasking the polling loop.
  private var pollingStarted = false
  private var currentTrackCountedAt: Int64?

  /// Timestamp of the last poll cycle that successfully returned events
  /// (any non-error response from the Spotify API). Surfaced in the
  /// Settings diagnostics panel so the user can confirm at a glance that
  /// polling is alive — "5 sec ago" = healthy, "12 min ago" = something
  /// upstream is broken. `nil` until the first successful poll lands.
  var lastSuccessfulPoll: Date?

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
    self.artworkCache = ArtworkCache()
    self.pet.syncFromStore(dbq: dbq)
  }

  /// Starts the polling loop. Idempotent — second call is a no-op.
  /// Caller must ensure a Spotify token exists in the keychain before calling.
  func start() {
    coordLog.notice("start() called, pollingStarted=\(self.pollingStarted)")
    guard !pollingStarted else { return }
    pollingStarted = true
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in self.poller.stream() {
          await self.handle(event)
        }
      } catch let error as SpotifyAuthError where error == .refreshFailed {
        // Refresh token is dead — user disconnected Dial from Spotify on
        // the web, or the grant otherwise expired. Flip the UI back to
        // the connect view so the user knows to reconnect. Polling stays
        // stopped (loop exited via thrown stream) and a future signIn()
        // will re-call start() with the now-cleared pollingStarted guard.
        print("[AppCoordinator] auth revoked — surfacing connect view")
        await MainActor.run { [weak self] in
          self?.settings.markSignedOut()
        }
      } catch {
        print("[AppCoordinator] polling error: \(error)")
      }
      // Allow re-start after the task exits (whether normally, errored, or
      // cancelled). Without this, the next signIn() would no-op because the
      // guard sees pollingStarted = true even though the loop is dead.
      self.pollingStarted = false
    }
    // Warm the most recent missing album art after launch settles. This used
    // to kick off a full-library oEmbed crawl every app start; with 10k+
    // missing tracks that quietly kept Dial busy for ages. The full backfill
    // can still be run explicitly, but launch should stay light.
    let dbq = self.dbq
    let client = self.client
    Task(priority: .background) {
      coordLog.notice("enricher task starting")
      do {
        try await Task.sleep(nanoseconds: 15_000_000_000)
        try Task.checkCancellation()
        try await MetadataEnricher(dbq: dbq, client: client)
          .enrichMissing(rateLimitPerSec: 1, limit: 75)
        coordLog.notice("enricher task finished cleanly")
      } catch is CancellationError {
        coordLog.notice("enricher task cancelled")
      } catch {
        coordLog.error("metadata backfill error: \(String(describing: error), privacy: .public)")
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

  @MainActor
  func reconnectForLibraryAccess() async throws {
    _ = try await settings.auth.signIn()
    settings.markSignedIn()
    start()
  }

  func importHistory(from folder: URL) async {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)) ?? []
    let endsongs = urls.filter {
      let n = $0.lastPathComponent
      return n.hasPrefix("endsong_") || n.hasPrefix("Streaming_History_Audio_")
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !endsongs.isEmpty else { return }
    let total = endsongs.count

    await MainActor.run { settings.importProgress = 0.001 }

    let importer = Importer(dbq: dbq, engine: engine)
    for (idx, f) in endsongs.enumerated() {
      if let rows = try? EndsongFile.parse(at: f) {
        _ = try? importer.importBatch(rows, sourcePath: f.path)
      }
      let progress = Double(idx + 1) / Double(total)
      await MainActor.run { settings.importProgress = progress }
    }

    let last = (try? ImportsLogDAO(dbq: dbq).last()) ?? nil
    await MainActor.run {
      settings.lastImport = last
      settings.importProgress = 0
      pet.syncFromStore(dbq: dbq)
      aggCache.refresh(
        trackUri: nowPlaying.track?.uri,
        artistUri: nowPlaying.track?.artistUri,
        currentPlayAt: currentTrackCountedAt)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
    }
  }

  private func handle(_ event: PlaybackEvent) async {
    // Mark "polling is alive" on every event we receive — the API responded
    // and we got something to handle. This is the heartbeat the diagnostics
    // panel shows; granularity is per-event but functionally per-poll since
    // PollingService yields a batch of events per HTTP round-trip.
    lastSuccessfulPoll = Date()
    switch event {
    case let .started(uri, name, artistName, artistUri, albumName, artUrl, durationMs, _):
      currentTrackCountedAt = nil
      // Persist track metadata so the SQL joins in `artistRank7d`,
      // `artistLifetimePlays`, and the PetEngine variety detection work.
      // Without this, the `tracks` table stays empty for live-only sessions.
      // Use JSONEncoder to avoid the hand-rolled escaping bug that lived
      // here previously (only escaped name's backslashes/quotes, left
      // the URI completely unescaped — symmetric to the Importer bug
      // that produced 108 malformed rows in `tracks`).
      let artistsJson: String? = {
        guard let aUri = artistUri else { return nil }
        struct Entry: Encodable { let name: String; let uri: String }
        let entry = Entry(name: artistName, uri: aUri)
        return (try? JSONEncoder().encode([entry])).flatMap {
          String(data: $0, encoding: .utf8)
        }
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
      artworkCache.prefetch(artUrl)
      menubar.state = .playing
      menubar.durationMs = durationMs
      refreshLikedState(for: uri)
      aggCache.refresh(trackUri: uri, artistUri: artistUri, currentPlayAt: nil)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
      updatePetMemoryText()
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
      currentTrackCountedAt = nil
      menubar.state = .nothingPlaying
      menubar.likedTrackState = .unknown
      menubar.progressMs = 0
      menubar.durationMs = 0
      resolvePetBehavior()

    case let .progress(ms):
      menubar.progressMs = ms
      menubar.lastProgressUpdate = Date()

    case let .modesChanged(shuffle, repeatMode):
      menubar.shuffle = shuffle
      menubar.repeatMode = repeatMode

    case let .countedPlay(uri, ms, at):
      let xpBefore = pet.xp
      // Don't swallow this one with `try?`. If the play failed to record
      // (DB locked, XP overflow, FK violation), we should NOT then refresh
      // aggregations against a write that didn't land, sync the pet from
      // a state that didn't change, and — most misleadingly — fire the
      // "eating" celebration animation. That'd lie to the user about what
      // happened. Skip the entire downstream celebration on error.
      let didRecord: Bool
      do {
        didRecord = try engine.recordPlay(
          .init(playedAt: at, trackUri: uri, msPlayed: ms, source: "live"))
      } catch {
        coordLog.error("recordPlay failed for \(uri, privacy: .public): \(String(describing: error), privacy: .public)")
        return
      }
      guard didRecord else {
        coordLog.notice("ignored duplicate live play: \(uri, privacy: .public) (\(ms)ms)")
        currentTrackCountedAt = nil
        aggCache.refresh(trackUri: uri, artistUri: nowPlaying.track?.artistUri, currentPlayAt: nil)
        nowPlaying.playsYTD = aggCache.playsYTD
        menubar.playsYTD = aggCache.playsYTD
        updatePetMemoryText()
        resolvePetBehavior()
        return
      }
      coordLog.notice("recorded live play: \(uri, privacy: .public) (\(ms)ms)")
      currentTrackCountedAt = at
      aggCache.refresh(trackUri: uri, artistUri: nowPlaying.track?.artistUri, currentPlayAt: at)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
      pet.syncFromStore(dbq: dbq)
      let xpDelta = max(0, pet.xp - xpBefore)
      let trackName = nowPlaying.track?.name ?? "this play"
      pet.lastFeedingText = xpDelta > 0
        ? "+\(xpDelta.formatted()) XP from \(trackName)"
        : "Fed by \(trackName)"
      updatePetMemoryText()
      // Tamagotchi-style: a counted play "feeds" the pet — flip on the
      // eating flag for ~600ms, then auto-clear so it returns to walk/idle.
      pet.isEating = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 600_000_000)
        pet.isEating = false
        resolvePetBehavior()
      }
      resolvePetBehavior()
    }
  }

  private func resolvePetBehavior() {
    guard settings.petEnabled else {
      pet.behavior = .idle
      updatePetReactionText()
      return
    }
    let ctx = PetContext(
      playing: menubar.state == .playing,
      paused:  menubar.state == .paused,
      firstListen: settings.petFirstListenAnimation && aggCache.firstListen,
      rediscovered: settings.petRediscoveryAnimation && aggCache.rediscovered,
      eating: settings.petFeedingAnimation && pet.isEating,
      leveledUp: settings.petLevelUpAnimation && pet.justLeveledUp,
      lastPlayAt: pet.lastPlayAt,
      now: Int64(Date().timeIntervalSince1970),
      bpm: pet.currentBPM
    )
    pet.behavior = PetBehaviorResolver.resolve(ctx)
    updatePetReactionText()
  }

  private func updatePetMemoryText() {
    guard let insight = aggCache.currentBadgeInsight else {
      pet.lastMemoryText = nil
      return
    }
    pet.lastMemoryText = "\(insight.kind.label): \(insight.detail)"
  }

  private func updatePetReactionText() {
    guard settings.petEnabled else {
      pet.reactionText = "Pet disabled."
      return
    }

    switch pet.behavior {
    case .levelUp:
      pet.reactionText = "Stage up: \(pet.stage.rawValue.capitalized)."
    case .firstListen:
      pet.reactionText = "New to your history."
    case .rediscovered:
      pet.reactionText = aggCache.currentBadgeInsight?.detail ?? "An old favorite came back."
    case let .expressed(expression, _):
      switch expression {
      case .levelUp:
        pet.reactionText = "Stage up: \(pet.stage.rawValue.capitalized)."
      case .firstListen:
        pet.reactionText = "New to your history."
      case .rediscovered:
        pet.reactionText = aggCache.currentBadgeInsight?.detail ?? "An old favorite came back."
      }
    case .eating:
      pet.reactionText = pet.lastFeedingText ?? "Fed by this play."
    case .paused:
      pet.reactionText = "Paused with \(nowPlaying.track?.name ?? "this track")."
    case .dormant:
      pet.reactionText = "Dormant. Play something to wake it."
    case let .beatSync(bpm):
      pet.reactionText = "Synced to \(Int(bpm.rounded())) BPM."
    case .sparkStep:
      pet.reactionText = "Spark Step."
    case .memorySpin:
      pet.reactionText = "Memory Spin."
    case .beatBounce:
      pet.reactionText = "Beat Bounce."
    case .walk:
      pet.reactionText = aggCache.currentBadgeInsight.map {
        "\($0.kind.label): \($0.detail)"
      } ?? "Listening."
    case .idle:
      pet.reactionText = "Waiting for playback."
    }
  }

  private func refreshLikedState(for uri: String) {
    guard uri.hasPrefix("spotify:track:") else {
      menubar.likedTrackState = .unknown
      return
    }

    menubar.likedTrackState = .checking
    Task { [weak self] in
      guard let self else { return }
      do {
        let isLiked = try await self.client.libraryContains(uri: uri)
        await MainActor.run {
          guard self.menubar.track?.uri == uri else { return }
          self.menubar.likedTrackState = isLiked ? .liked : .notLiked
        }
      } catch SpotifyAPIError.httpStatus(403) {
        await MainActor.run {
          guard self.menubar.track?.uri == uri else { return }
          self.menubar.likedTrackState = .needsReconnect
        }
      } catch {
        await MainActor.run {
          guard self.menubar.track?.uri == uri else { return }
          self.menubar.likedTrackState = .unknown
        }
      }
    }
  }
}
