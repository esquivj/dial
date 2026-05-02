// Dial/ViewModels/AppCoordinator.swift
import Observation
import AppKit
import Foundation
import GRDB
import Network
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
  let backgroundEnrichment: BackgroundEnrichmentCoordinator
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
  private var ambientTrickTask: Task<Void, Never>?
  private var recentRepairTask: Task<Void, Never>?
  private var recentPeriodicTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?
  private var networkMonitor: NWPathMonitor?
  private let networkMonitorQueue = DispatchQueue(label: "com.dial.Dial.recent-play-network-monitor")
  private var networkWasSatisfied = false
  private var currentTrackCountedAt: Int64?
  private var playbackReducer = PlaybackStateReducer()

  var backgroundEnrichmentPhase: BackgroundEnrichmentPhase { backgroundEnrichment.phase }
  var backgroundEnrichmentMessage: String { backgroundEnrichment.message }
  var backgroundEnrichmentLastError: String? { backgroundEnrichment.lastError }
  var backgroundEnrichmentUpdatedAt: Date? { backgroundEnrichment.updatedAt }
  var backgroundEnrichmentLabel: String { backgroundEnrichment.label }

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
    let settings = SettingsViewModel(auth: auth, dbq: dbq, tokenStore: tokenStore)
    self.settings = settings
    self.backgroundEnrichment = BackgroundEnrichmentCoordinator(dbq: dbq, client: client, settings: settings)
    self.artworkCache = ArtworkCache()
    self.desktopPlaybackObserver = SpotifyDesktopPlaybackObserver()
    self.pet.syncFromStore(dbq: dbq)
  }

  /// Starts the polling loop. Idempotent — second call is a no-op.
  /// Caller must ensure a Spotify token exists in the keychain before calling.
  func start() {
    coordLog.notice("start() called, pollingStarted=\(self.pollingStarted)")
    startDesktopObserver()
    startRecentPlayObservers()
    guard !pollingStarted else { return }
    pollingStarted = true
    startRecentPlayRepair(reason: "launch")
    startPeriodicRecentPlaySync()
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
        coordLog.error("auth revoked; surfacing connect view")
        await MainActor.run { [weak self] in
          self?.settings.markSignedOut()
        }
      } catch {
        coordLog.error("polling error: \(String(describing: error), privacy: .public)")
      }
      // Allow re-start after the task exits (whether normally, errored, or
      // cancelled). Without this, the next signIn() would no-op because the
      // guard sees pollingStarted = true even though the loop is dead.
      self.pollingStarted = false
    }
    syncBackgroundEnrichment()
    refreshWeeklyMemoriesIfNeeded()
  }

  private func startRecentPlayRepair(reason: String) {
    recentRepairTask?.cancel()
    recentRepairTask = Task { [weak self] in
      await self?.runRecentPlayRepair(reason: reason, aggressive: true)
    }
  }

  private func startPeriodicRecentPlaySync() {
    guard recentPeriodicTask == nil else { return }
    recentPeriodicTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
        guard !Task.isCancelled else { return }
        await self?.runRecentPlayRepair(reason: "periodic", aggressive: false)
      }
    }
  }

  private func startRecentPlayObservers() {
    if wakeObserver == nil {
      wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.startRecentPlayRepair(reason: "wake")
      }
    }

    guard networkMonitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let satisfied = path.status == .satisfied
      if satisfied && !self.networkWasSatisfied {
        DispatchQueue.main.async { [weak self] in
          self?.startRecentPlayRepair(reason: "network")
        }
      }
      self.networkWasSatisfied = satisfied
    }
    monitor.start(queue: networkMonitorQueue)
    networkMonitor = monitor
  }

  private func runRecentPlayRepair(reason: String, aggressive: Bool) async {
    let maxAttempts = aggressive ? 8 : 1
    var stableNoInsertChecks = 0
    var saturatedChecks = 0

    for attempt in 1...maxAttempts {
      guard !Task.isCancelled else { return }
      let result = await reconcileRecentPlays(reason: reason, attempt: attempt)

      switch result {
      case .success(let sync):
        if sync.possiblyTruncated {
          saturatedChecks += 1
          stableNoInsertChecks = 0
        } else if sync.inserted == 0 {
          stableNoInsertChecks += 1
        } else {
          stableNoInsertChecks = 0
        }

        if !aggressive || stableNoInsertChecks >= 2 { return }
      case .failure:
        return
      }

      guard aggressive else { return }
      try? await Task.sleep(nanoseconds: 18 * 1_000_000_000)
    }

    if saturatedChecks > 0 {
      coordLog.warning("recent-play repair ended with \(saturatedChecks, privacy: .public) saturated 50-row checks; gap may be incomplete")
    }
  }

  private func reconcileRecentPlays(
    reason: String,
    attempt: Int
  ) async -> Result<RecentPlaySyncResult, Error> {
    do {
      let result = try await RecentPlaysReconciler(
        dbq: dbq,
        client: client,
        engine: engine
      ).sync()
      guard result.inserted > 0 else { return .success(result) }

      await MainActor.run {
        pet.syncFromStore(dbq: dbq)
        aggCache.refresh(
          trackUri: nowPlaying.track?.uri,
          artistUri: nowPlaying.track?.artistUri,
          currentPlayAt: currentTrackCountedAt)
        refreshCurrentSoundTheme(allowFallback: false)
        nowPlaying.playsYTD = aggCache.playsYTD
        menubar.playsYTD = aggCache.playsYTD
        updatePetMemoryText()
        resolvePetBehavior()
      }
      refreshWeeklyMemoriesIfNeeded()
      restartBackgroundEnrichmentNow()
      coordLog.notice("recent-play sync repaired \(result.inserted) missed plays reason=\(reason, privacy: .public) attempt=\(attempt, privacy: .public)")
      return .success(result)
    } catch SpotifyAPIError.rateLimited(let retryAfter) {
      coordLog.warning("recent-play sync rate limited, retryAfter=\(retryAfter ?? 0, privacy: .public)")
      return .failure(SpotifyAPIError.rateLimited(retryAfter: retryAfter))
    } catch {
      coordLog.warning("recent-play sync failed: \(String(describing: error), privacy: .public)")
      return .failure(error)
    }
  }

  func syncBackgroundEnrichment() {
    backgroundEnrichment.sync()
  }

  func restartBackgroundEnrichmentNow() {
    backgroundEnrichment.restartNow()
  }

  func stopBackgroundEnrichment(updateStatus: Bool = true) {
    backgroundEnrichment.stop(updateStatus: updateStatus)
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
    refreshCurrentSoundTheme(allowFallback: false)
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
      refreshCurrentSoundTheme(allowFallback: false)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
    }
    restartBackgroundEnrichmentNow()
  }

  private func handle(_ event: PlaybackEvent, source: PlaybackEventSource = .poll) async {
    let perf: DialPerfInterval? = source == .poll ? DialPerf.begin("playback.poll_to_render") : nil
    var perfEnded = false
    func endPerf() {
      guard !perfEnded else { return }
      perf?.end()
      perfEnded = true
    }
    defer { endPerf() }

    // Keep the Settings heartbeat tied to the Web API poller. Desktop
    // notifications are a faster local UI path, not proof the API is healthy.
    if source == .poll {
      lastSuccessfulPoll = Date()
    }
    guard let reduction = playbackReducer.reduce(event, source: source) else {
      if source == .poll {
        DialPerf.event("playback.poll_suppressed")
      }
      return
    }
    let event = reduction.event
    switch event {
    case let .started(uri, name, artistName, artistUri, artists, albumName, artUrl, durationMs, _):
      let existingTrack = nowPlaying.track
      let trackChanged = reduction.trackChanged || existingTrack?.uri != uri
      let storedTrack = trackChanged ? (try? TracksDAO(dbq: dbq).fetch(uri: uri)) : nil
      let storedArtists = Self.playbackArtists(from: storedTrack?.artistsJson)
      if trackChanged {
        currentTrackCountedAt = nil
        menubar.setOptimisticProgress(0)
        clearAmbientTrick()
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

      // Publish the visible player state before cache warming and metadata
      // persistence. Those side effects matter, but they should not sit in
      // front of the "new track appeared" path.
      let track = NowPlayingViewModel.Track(
        uri: uri,
        name: resolvedName,
        artistName: resolvedArtistName,
        artistUri: resolvedArtistUri,
        artistUris: resolvedArtists.map(\.uri).filter { $0.hasPrefix("spotify:artist:") },
        albumName: resolvedAlbumName,
        artUrl: resolvedArtUrl)
      nowPlaying.track = track
      menubar.track = track
      menubar.state = .playing
      menubar.durationMs = resolvedDurationMs
      if trackChanged || menubar.likedTrackState == .unknown {
        refreshLikedState(for: uri)
      }
      resolvePetBehavior()
      endPerf()

      await artworkCache.prefetch(resolvedArtUrl)

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

      aggCache.refresh(trackUri: uri, artistUri: resolvedArtistUri, currentPlayAt: nil)
      updateSoundTheme(
        for: resolvedArtists.map(\.uri),
        allowFallback: !trackChanged,
        trackName: resolvedName,
        artistName: resolvedArtistName,
        albumName: resolvedAlbumName)
      warmCurrentSoundTags(for: resolvedArtists)
      nowPlaying.playsYTD = aggCache.playsYTD
      menubar.playsYTD = aggCache.playsYTD
      updatePetMemoryText()
      // BPM lookup is best-effort for the beat-sync animation.
      if trackChanged,
         let trackId = uri.split(separator: ":").last,
         await SpotifyRateLimitGate.shared.cooldownRemaining() <= 0,
         let features = try? await client.audioFeatures(trackId: String(trackId)) {
        pet.currentBPM = features.tempo
      }
      resolvePetBehavior()

    case .paused:
      menubar.state = .paused
      endPerf()
      resolvePetBehavior()

    case .resumed:
      menubar.state = .playing
      endPerf()
      resolvePetBehavior()

    case .noPlayback:
      currentTrackCountedAt = nil
      clearAmbientTrick()
      nowPlaying.track = nil
      nowPlaying.playsYTD = 0
      nowPlaying.soundTheme = .classic
      nowPlaying.soundThemeDecision = nil
      menubar.track = nil
      menubar.state = .nothingPlaying
      menubar.likedTrackState = .unknown
      menubar.progressMs = 0
      menubar.durationMs = 0
      menubar.lastProgressUpdate = nil
      menubar.playsYTD = 0
      pet.currentBPM = nil
      aggCache.refresh(trackUri: nil, artistUri: nil, currentPlayAt: nil)
      endPerf()
      resolvePetBehavior()

    case let .progress(ms):
      menubar.progressMs = ms
      menubar.lastProgressUpdate = Date()
      endPerf()

    case let .modesChanged(shuffle, repeatMode):
      menubar.applyRemoteModes(shuffle: shuffle, repeatMode: repeatMode)
      endPerf()

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
        endPerf()
        return
      }
      guard didRecord else {
        coordLog.notice("ignored duplicate live play: \(uri, privacy: .public) (\(ms)ms)")
        currentTrackCountedAt = nil
        aggCache.refresh(trackUri: uri, artistUri: nowPlaying.track?.artistUri, currentPlayAt: nil)
        nowPlaying.playsYTD = aggCache.playsYTD
        menubar.playsYTD = aggCache.playsYTD
        updatePetMemoryText()
        endPerf()
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
        ? "+\(xpDelta.formatted()) XP · \(trackName)"
        : "Memory added · \(trackName)"
      updatePetMemoryText()
      refreshWeeklyMemoriesIfNeeded()
      endPerf()
      // A counted play gets a tiny creature pulse, then settles back into the
      // current listening motion. The UI copy stays about memory/XP, not chores.
      pet.isEating = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 600_000_000)
        pet.isEating = false
        resolvePetBehavior()
      }
      resolvePetBehavior()
      scheduleAmbientTrickIfNeeded()
    }
  }

  private func refreshWeeklyMemoriesIfNeeded(limit: Int = 12) {
    guard settings.petEnabled, settings.livingMemoriesEnabled else { return }
    let dbq = self.dbq
    Task(priority: .utility) {
      do {
        _ = try WeeklyMemoriesDAO(dbq: dbq).ensureRecentWeeks(limit: limit)
      } catch {
        coordLog.error("weekly memories refresh failed: \(String(describing: error), privacy: .public)")
      }
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
      ambientTrick: pet.ambientTrickBehavior,
      lastPlayAt: pet.lastPlayAt,
      now: Int64(Date().timeIntervalSince1970),
      bpm: pet.currentBPM
    )
    pet.behavior = PetBehaviorResolver.resolve(ctx)
    updatePetReactionText()
  }

  private func scheduleAmbientTrickIfNeeded() {
    guard settings.petEnabled,
          let badge = aggCache.currentBadgeInsight?.kind,
          let trick = ambientTrick(for: badge)
    else { return }

    let unlockedTricks = ((try? PetTrickUnlocksDAO(dbq: dbq).all()) ?? []).map(\.trick)
    guard unlockedTricks.contains(trick) else { return }

    ambientTrickTask?.cancel()
    let behavior = trick.displayBehavior
    ambientTrickTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 720_000_000)
      guard !Task.isCancelled, let self, self.menubar.state == .playing else { return }
      self.pet.ambientTrickBehavior = behavior
      self.resolvePetBehavior()

      try? await Task.sleep(nanoseconds: 1_150_000_000)
      guard !Task.isCancelled else { return }
      self.pet.ambientTrickBehavior = nil
      self.resolvePetBehavior()
      self.ambientTrickTask = nil
    }
  }

  private func clearAmbientTrick() {
    ambientTrickTask?.cancel()
    ambientTrickTask = nil
    pet.ambientTrickBehavior = nil
  }

  private func ambientTrick(for badge: BadgeMemoryKind) -> PetTrick? {
    switch badge {
    case .firstListen, .newArtist, .play10, .play50, .play100:
      return .sparkStep
    case .rediscovered, .deepCut, .anniversary:
      return .memorySpin
    case .onStreak, .repeatTrack, .albumMode:
      return .beatBounce
    }
  }

  private func updateSoundTheme(for artistUri: String?) {
    guard let artistUri else { return }
    updateSoundTheme(for: [artistUri])
  }

  private func updateSoundTheme(
    for artistUris: [String],
    allowFallback: Bool = true,
    trackName: String? = nil,
    artistName: String? = nil,
    albumName: String? = nil
  ) {
    let artistUris = artistUris.filter { $0.hasPrefix("spotify:artist:") }
    let queries = StatsQueries(dbq: dbq)
    let decision = try? queries.soundThemeDecision(
      forArtistUris: artistUris,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      allowRecentFallback: allowFallback)
    let resolved = Self.resolvedSoundThemeState(
      currentTheme: nowPlaying.soundTheme,
      hasTrack: nowPlaying.track != nil,
      decision: decision)
    nowPlaying.soundTheme = resolved.theme
    if let resolvedDecision = resolved.decision {
      nowPlaying.soundThemeDecision = resolvedDecision
    }
  }

  static func resolvedSoundThemeState(
    currentTheme: DialThemeID,
    hasTrack: Bool,
    decision: SoundThemeDecision?
  ) -> (theme: DialThemeID, decision: SoundThemeDecision?) {
    if let decision {
      return (decision.theme, decision)
    }
    if hasTrack {
      return (currentTheme, .holding(theme: currentTheme))
    }
    return (currentTheme, nil)
  }

  private func refreshCurrentSoundTheme(allowFallback: Bool = true) {
    guard let track = nowPlaying.track else { return }
    let artistUris = track.artistUris.isEmpty
      ? [track.artistUri].compactMap { $0 }
      : track.artistUris
    updateSoundTheme(
      for: artistUris,
      allowFallback: allowFallback,
      trackName: track.name,
      artistName: track.artistName,
      albumName: track.albumName)
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
    var seen = Set<String>()
    let artists = artists.filter { artist in
      artist.uri.hasPrefix("spotify:artist:")
        && !artist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && seen.insert(artist.uri).inserted
    }
    let artistUris = artists.map(\.uri)
    guard !artistUris.isEmpty else { return }

    let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

    currentTagWarmTask?.cancel()
    let dbq = self.dbq
    let client = self.client
    let useLastFM = settings.lastFMTagEnrichmentEnabled && !key.isEmpty
    currentTagWarmTask = Task { [weak self] in
      do {
        if await SpotifyRateLimitGate.shared.cooldownRemaining() <= 0 {
          let metadata = MetadataEnricher(dbq: dbq, client: client)
          _ = try await metadata.enrichArtists(
            uris: artistUris,
            rateLimitPerSec: 2,
            respectSpotifyCooldown: false)
        } else {
          coordLog.debug("skipping Spotify artist warmup during catalog cooldown")
        }

        if useLastFM {
          let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
          _ = try await tagger.enrichArtists(
            artists.map { ArtistTagCandidate(uri: $0.uri, name: $0.name) },
            rateLimitPerSec: 2)
        }
        try Task.checkCancellation()
        await MainActor.run { [weak self] in
          self?.refreshCurrentSoundTheme(allowFallback: false)
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
      pet.reactionText = pet.lastFeedingText ?? "Memory added."
    case .paused:
      pet.reactionText = "Paused with \(nowPlaying.track?.name ?? "this track")."
    case .dormant:
      pet.reactionText = "Quiet since the last session."
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
