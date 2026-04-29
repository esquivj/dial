// Dial/ViewModels/AppCoordinator.swift
import Observation
import Foundation
import GRDB
import os.log

private let coordLog = Logger(subsystem: "com.dial.Dial", category: "AppCoordinator")

private enum PlaybackEventSource {
  case poll
  case desktopNotification
}

enum BackgroundEnrichmentPhase: Equatable {
  case off
  case waiting
  case tracks
  case artists
  case tags
  case caughtUp
  case failed

  var label: String {
    switch self {
    case .off:      "off"
    case .waiting:  "waiting"
    case .tracks:   "tracks"
    case .artists:  "artists"
    case .tags:     "tags"
    case .caughtUp: "caught up"
    case .failed:   "paused"
    }
  }
}

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
  let desktopPlaybackObserver: SpotifyDesktopPlaybackObserver
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
  private var desktopObserverStarted = false
  private var currentTagWarmTask: Task<Void, Never>?
  private var backgroundEnrichmentTask: Task<Void, Never>?
  private var currentTrackCountedAt: Int64?

  var backgroundEnrichmentPhase: BackgroundEnrichmentPhase = .off
  var backgroundEnrichmentMessage = "Off"
  var backgroundEnrichmentLastError: String?
  var backgroundEnrichmentUpdatedAt: Date?

  var backgroundEnrichmentLabel: String {
    switch backgroundEnrichmentPhase {
    case .failed:
      return backgroundEnrichmentLastError.map { "paused · \($0)" } ?? "paused"
    default:
      return "\(backgroundEnrichmentPhase.label) · \(backgroundEnrichmentMessage)"
    }
  }

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
    self.poller = PollingService(client: client, interval: 2.0)
    self.nowPlaying = NowPlayingViewModel(agg: aggCache)
    self.menubar = MenubarStripViewModel()
    self.pet = PetViewModel()
    self.settings = SettingsViewModel(auth: auth, dbq: dbq, tokenStore: tokenStore)
    self.artworkCache = ArtworkCache()
    self.desktopPlaybackObserver = SpotifyDesktopPlaybackObserver()
    self.pet.syncFromStore(dbq: dbq)
  }

  /// Starts the polling loop. Idempotent — second call is a no-op.
  /// Caller must ensure a Spotify token exists in the keychain before calling.
  func start() {
    coordLog.notice("start() called, pollingStarted=\(self.pollingStarted)")
    startDesktopObserver()
    guard !pollingStarted else { return }
    pollingStarted = true
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in self.poller.stream() {
          await self.handle(event, source: .poll)
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
    syncBackgroundEnrichment()
  }

  func syncBackgroundEnrichment() {
    guard settings.backgroundEnrichmentEnabled, settings.signedIn else {
      stopBackgroundEnrichment()
      return
    }
    startBackgroundEnrichment(initialDelay: 15)
  }

  func restartBackgroundEnrichmentNow() {
    stopBackgroundEnrichment(updateStatus: false)
    guard settings.backgroundEnrichmentEnabled, settings.signedIn else {
      updateBackgroundEnrichment(.off, message: "Off", error: nil)
      return
    }
    startBackgroundEnrichment(initialDelay: 0)
  }

  func stopBackgroundEnrichment(updateStatus: Bool = true) {
    backgroundEnrichmentTask?.cancel()
    backgroundEnrichmentTask = nil
    if updateStatus {
      updateBackgroundEnrichment(.off, message: "Off", error: nil)
    }
  }

  private func startBackgroundEnrichment(initialDelay: TimeInterval) {
    guard backgroundEnrichmentTask == nil else { return }
    let dbq = self.dbq
    let client = self.client
    let settings = self.settings
    backgroundEnrichmentTask = Task(priority: .background) { [weak self] in
      if initialDelay > 0 {
        self?.updateBackgroundEnrichment(.waiting, message: "starts in \(Int(initialDelay))s", error: nil)
        try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
      }

      let metadata = MetadataEnricher(dbq: dbq, client: client)
      while !Task.isCancelled {
        guard settings.backgroundEnrichmentEnabled, settings.signedIn else { break }
        do {
          let before = try StatsQueries(dbq: dbq).enrichmentProgress()
          var attempted = 0

          if before.trackArtistResolved < before.total || before.enriched < before.total {
            let remaining = max(0, before.total - before.trackArtistResolved)
            self?.updateBackgroundEnrichment(.tracks, message: "\(remaining.formatted()) IDs left", error: nil)
            attempted += try await metadata.enrichMissing(rateLimitPerSec: 0.45, limit: 120)
            try Task.checkCancellation()
            if try Self.hasRecentSpotifyRateLimit(dbq) {
              self?.updateBackgroundEnrichment(.waiting, message: "Spotify cooldown", error: nil)
              try await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
              continue
            }
          }

          let afterTracks = try StatsQueries(dbq: dbq).enrichmentProgress()
          if afterTracks.artistEnriched < afterTracks.artistTotal {
            let remaining = max(0, afterTracks.artistTotal - afterTracks.artistEnriched)
            self?.updateBackgroundEnrichment(.artists, message: "\(remaining.formatted()) left", error: nil)
            attempted += try await metadata.enrichMissingArtists(rateLimitPerSec: 0.75, limit: 100)
            try Task.checkCancellation()
            if try Self.hasRecentSpotifyRateLimit(dbq) {
              self?.updateBackgroundEnrichment(.waiting, message: "Spotify cooldown", error: nil)
              try await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
              continue
            }
          }

          let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
          let afterArtists = try StatsQueries(dbq: dbq).enrichmentProgress()
          if settings.lastFMTagEnrichmentEnabled, !key.isEmpty, afterArtists.tagArtistChecked < afterArtists.tagArtistTotal {
            let remaining = max(0, afterArtists.tagArtistTotal - afterArtists.tagArtistChecked)
            self?.updateBackgroundEnrichment(.tags, message: "\(remaining.formatted()) left", error: nil)
            let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
            attempted += try await tagger.enrichMissingArtists(rateLimitPerSec: 1, limit: 100)
            try Task.checkCancellation()
          }

          let after = try StatsQueries(dbq: dbq).enrichmentProgress()
          if attempted == 0 {
            if Self.enrichmentIsCaughtUp(after, includeTags: settings.lastFMTagEnrichmentEnabled && !key.isEmpty) {
              self?.updateBackgroundEnrichment(.caughtUp, message: "library analyzed", error: nil)
              try await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            } else {
              self?.updateBackgroundEnrichment(.waiting, message: "retry window", error: nil)
              try await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
          } else {
            self?.updateBackgroundEnrichment(.waiting, message: "continuing", error: nil)
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
          }
        } catch is CancellationError {
          break
        } catch {
          self?.updateBackgroundEnrichment(.failed, message: "retrying later", error: String(describing: error))
          coordLog.error("background enrichment paused: \(String(describing: error), privacy: .public)")
          try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
        }
      }
      self?.finishBackgroundEnrichmentTask()
    }
  }

  private func updateBackgroundEnrichment(_ phase: BackgroundEnrichmentPhase, message: String, error: String?) {
    backgroundEnrichmentPhase = phase
    backgroundEnrichmentMessage = message
    backgroundEnrichmentLastError = error
    backgroundEnrichmentUpdatedAt = Date()
  }

  private func finishBackgroundEnrichmentTask() {
    backgroundEnrichmentTask = nil
    if !settings.backgroundEnrichmentEnabled || !settings.signedIn {
      updateBackgroundEnrichment(.off, message: "Off", error: nil)
    }
  }

  private static func enrichmentIsCaughtUp(_ progress: StatsQueries.EnrichmentProgress, includeTags: Bool) -> Bool {
    progress.total > 0
      && progress.trackArtistResolved >= progress.total
      && progress.artistEnriched >= progress.artistTotal
      && (!includeTags || progress.tagArtistChecked >= progress.tagArtistTotal)
  }

  private static func hasRecentSpotifyRateLimit(_ dbq: DatabaseQueue, within seconds: Int64 = 15 * 60) throws -> Bool {
    let cutoff = Int64(Date().timeIntervalSince1970) - seconds
    return try dbq.read { db in
      try Int.fetchOne(db, sql: """
        SELECT 1
        FROM metadata_enrichment_state
        WHERE provider = 'spotify'
          AND status = 'limited'
          AND fetched_at >= ?
        LIMIT 1
      """, arguments: [cutoff]) != nil
    }
  }

  private func startDesktopObserver() {
    guard !desktopObserverStarted else { return }
    desktopObserverStarted = true
    desktopPlaybackObserver.start { [weak self] events in
      Task { [weak self] in
        guard let self else { return }
        for event in events {
          await self.handle(event, source: .desktopNotification)
        }
      }
    }
  }

  func runTagEnrichment(limit: Int = 250) async throws {
    let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
    try await tagger.enrichMissingArtists(rateLimitPerSec: 1, limit: limit)
    updateSoundTheme(for: nowPlaying.track?.artistUri)
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
      updateSoundTheme(for: nowPlaying.track?.artistUri)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
    }
    restartBackgroundEnrichmentNow()
  }

  private func handle(_ event: PlaybackEvent, source: PlaybackEventSource = .poll) async {
    // Keep the Settings heartbeat tied to the Web API poller. Desktop
    // notifications are a faster local UI path, not proof the API is healthy.
    if source == .poll {
      lastSuccessfulPoll = Date()
    }
    switch event {
    case let .started(uri, name, artistName, artistUri, artists, albumName, artUrl, durationMs, _):
      let existingTrack = nowPlaying.track
      let trackChanged = existingTrack?.uri != uri
      let storedTrack = trackChanged ? (try? TracksDAO(dbq: dbq).fetch(uri: uri)) : nil
      let storedArtists = Self.playbackArtists(from: storedTrack?.artistsJson)
      if trackChanged {
        currentTrackCountedAt = nil
        menubar.setOptimisticProgress(0)
      }

      let canReuseExistingMetadata = !trackChanged
      let resolvedName = name.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.name ?? "") : (storedTrack?.name ?? ""))
        : name
      let resolvedArtistName = artistName.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.artistName ?? "") : (storedArtists.first?.name ?? ""))
        : artistName
      let resolvedArtistUri = artistUri
        ?? (canReuseExistingMetadata ? existingTrack?.artistUri : storedArtists.first?.uri)
      let resolvedArtists: [PlaybackArtist] = {
        if !artists.isEmpty { return artists }
        if !storedArtists.isEmpty { return storedArtists }
        guard let resolvedArtistUri else { return [] }
        return [PlaybackArtist(name: resolvedArtistName, uri: resolvedArtistUri)]
      }()
      let resolvedAlbumName = albumName.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.albumName ?? "") : (storedTrack?.albumName ?? ""))
        : albumName
      let resolvedArtUrl = artUrl ?? (canReuseExistingMetadata ? existingTrack?.artUrl : storedTrack?.albumArtUrl)
      let resolvedDurationMs = durationMs > 0
        ? durationMs
        : (canReuseExistingMetadata ? menubar.durationMs : Int(storedTrack?.durationMs ?? 0))

      // Persist track metadata so the SQL joins in `artistRank7d`,
      // `artistLifetimePlays`, and the PetEngine variety detection work.
      // Without this, the `tracks` table stays empty for live-only sessions.
      // Use JSONEncoder to avoid the hand-rolled escaping bug that lived
      // here previously (only escaped name's backslashes/quotes, left
      // the URI completely unescaped — symmetric to the Importer bug
      // that produced 108 malformed rows in `tracks`).
      let artistsJson: String? = {
        guard !resolvedArtists.isEmpty else { return nil }
        return (try? JSONEncoder().encode(resolvedArtists)).flatMap {
          String(data: $0, encoding: .utf8)
        }
      }()
      try? TracksDAO(dbq: dbq).upsert(.init(
        uri: uri,
        name: resolvedName.isEmpty ? nil : resolvedName,
        albumName: resolvedAlbumName.isEmpty ? nil : resolvedAlbumName,
        albumArtUrl: resolvedArtUrl,
        durationMs: resolvedDurationMs > 0 ? Int64(resolvedDurationMs) : nil,
        artistsJson: artistsJson))

      persistLiveArtists(resolvedArtists)

      let track = NowPlayingViewModel.Track(
        uri: uri,
        name: resolvedName,
        artistName: resolvedArtistName,
        artistUri: resolvedArtistUri,
        albumName: resolvedAlbumName,
        artUrl: resolvedArtUrl)
      nowPlaying.track = track
      menubar.track = track
      await artworkCache.prefetch(resolvedArtUrl)
      menubar.state = .playing
      menubar.durationMs = resolvedDurationMs
      if trackChanged || menubar.likedTrackState == .unknown {
        refreshLikedState(for: uri)
      }
      aggCache.refresh(trackUri: uri, artistUri: resolvedArtistUri, currentPlayAt: nil)
      updateSoundTheme(for: resolvedArtists.map(\.uri), allowFallback: !trackChanged)
      warmCurrentSoundTags(for: resolvedArtists)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
      updatePetMemoryText()
      // BPM lookup is best-effort for the beat-sync animation.
      if trackChanged,
         let trackId = uri.split(separator: ":").last,
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
      nowPlaying.track = nil
      nowPlaying.playsYTD = 0
      nowPlaying.soundTheme = .classic
      menubar.track = nil
      menubar.state = .nothingPlaying
      menubar.likedTrackState = .unknown
      menubar.progressMs = 0
      menubar.durationMs = 0
      menubar.lastProgressUpdate = nil
      menubar.playsYTD = 0
      pet.currentBPM = nil
      aggCache.refresh(trackUri: nil, artistUri: nil, currentPlayAt: nil)
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

  private func updateSoundTheme(for artistUri: String?) {
    guard let artistUri else { return }
    updateSoundTheme(for: [artistUri])
  }

  private func updateSoundTheme(for artistUris: [String], allowFallback: Bool = true) {
    let artistUris = artistUris.filter { $0.hasPrefix("spotify:artist:") }
    guard !artistUris.isEmpty else { return }

    let queries = StatsQueries(dbq: dbq)
    let theme = allowFallback
      ? (try? queries.soundTheme(forArtistUris: artistUris))
      : (try? queries.directSoundTheme(forArtistUris: artistUris))
    if let theme {
      nowPlaying.soundTheme = theme
    }
  }

  private static func playbackArtists(from artistsJson: String?) -> [PlaybackArtist] {
    guard
      let artistsJson,
      let data = artistsJson.data(using: .utf8),
      let artists = try? JSONDecoder().decode([PlaybackArtist].self, from: data)
    else { return [] }
    return artists.filter { $0.uri.hasPrefix("spotify:artist:") }
  }

  private func persistLiveArtists(_ artists: [PlaybackArtist]) {
    let artists = artists.filter { artist in
      artist.uri.hasPrefix("spotify:artist:") && !artist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !artists.isEmpty else { return }

    try? dbq.write { db in
      for artist in artists {
        try db.execute(sql: """
          INSERT INTO artists (uri, name, genres_json, image_url)
          VALUES (?, ?, NULL, NULL)
          ON CONFLICT(uri) DO UPDATE SET
            name = COALESCE(NULLIF(name, ''), excluded.name)
          """, arguments: [artist.uri, artist.name])
      }
    }
  }

  private func warmCurrentSoundTags(for artists: [PlaybackArtist]) {
    let artistUris = artists
      .map(\.uri)
      .filter { $0.hasPrefix("spotify:artist:") }
    guard !artistUris.isEmpty else { return }

    let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard settings.lastFMTagEnrichmentEnabled, !key.isEmpty else { return }

    currentTagWarmTask?.cancel()
    let dbq = self.dbq
    currentTagWarmTask = Task { [weak self] in
      do {
        let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
        try await tagger.enrichMissingArtists(rateLimitPerSec: 2, limit: 12)
        try Task.checkCancellation()
        await MainActor.run { [weak self] in
          self?.updateSoundTheme(for: artistUris, allowFallback: false)
        }
      } catch is CancellationError {
      } catch {
        coordLog.warning("current artist tag warmup failed: \(String(describing: error), privacy: .public)")
      }
    }
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
