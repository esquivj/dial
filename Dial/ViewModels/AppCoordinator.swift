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
  /// Last.fm scrobbling and Loved sync. Fed only from the live playback
  /// path below, never from imports or recently-played sync.
  let lastFM: LastFMScrobbler
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
  private var countedPlaySideEffectsTask: Task<Void, Never>?
  private var playbackPostRenderTask: Task<Void, Never>?
  private var weeklyMemoriesTask: Task<Void, Never>?
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
  var cachedHistorySnapshot: HistoryViewSnapshot?
  var cachedStatsSnapshotYTD: StatsViewSnapshot?
  var cachedPetSnapshot: PetViewSnapshot?

  @MainActor
  func invalidateDropdownSnapshots() {
    cachedHistorySnapshot = nil
    cachedStatsSnapshotYTD = nil
    cachedPetSnapshot = nil
  }

  /// Timestamp of the last poll cycle that successfully returned events
  /// (any non-error response from the Spotify API). Surfaced in the
  /// Settings diagnostics panel so the user can confirm at a glance that
  /// polling is alive — "5 sec ago" = healthy, "12 min ago" = something
  /// upstream is broken. `nil` until the first successful poll lands.
  var lastSuccessfulPoll: Date?

  /// Which feed answers for now-playing: the Spotify app (local, instant)
  /// or the Web API. Settings uses it to explain a denied Automation grant.
  var playbackSource: PlaybackSourceStatus = .webAPI(.noLocalSource)

  init(
    dbq: DatabaseQueue,
    client: SpotifyClient,
    auth: SpotifyAuthService,
    tokenStore: TokenStore,
    defaults: UserDefaults = .standard
  ) {
    self.dbq = dbq
    self.client = client
    self.engine = PetEngine(dbq: dbq)
    self.aggCache = AggregationsCache(agg: PlayAggregations(dbq: dbq))
    self.poller = PollingService(
      client: client,
      interval: 2.0,
      localSource: SpotifyAppleEventsSource())
    self.nowPlaying = NowPlayingViewModel(agg: aggCache)
    self.menubar = MenubarStripViewModel()
    self.pet = PetViewModel()
    let settings = SettingsViewModel(auth: auth, dbq: dbq, tokenStore: tokenStore, defaults: defaults)
    self.settings = settings
    self.backgroundEnrichment = BackgroundEnrichmentCoordinator(dbq: dbq, client: client, settings: settings)
    self.artworkCache = ArtworkCache()
    self.desktopPlaybackObserver = SpotifyDesktopPlaybackObserver()
    // Built on the main thread (app launch, tests).
    self.lastFM = MainActor.assumeIsolated {
      LastFMScrobbler(
        dbq: dbq,
        credentials: { [weak settings] in settings?.lastFMCredentials },
        defaults: defaults)
    }
    self.pet.syncFromStore(dbq: dbq)
    menubar.onUserLikedChange = { [weak self] uri, liked in
      self?.syncLovedTrack(uri: uri, liked: liked)
    }
  }

  /// Starts the polling loop. Idempotent — second call is a no-op.
  /// Caller must ensure a Spotify token exists in the keychain before calling.
  func start() {
    coordLog.notice("start() called, pollingStarted=\(self.pollingStarted)")
    startDesktopObserver()
    startRecentPlayObservers()
    guard !pollingStarted else { return }
    pollingStarted = true
    poller.onStatusChange = { [weak self] status in
      DispatchQueue.main.async { self?.playbackSource = status }
    }
    startRecentPlayRepair(reason: "launch", delay: 8)
    startPeriodicRecentPlaySync()
    Task { @MainActor [weak self] in self?.lastFM.flushSoon() }
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in self.poller.stream() {
          await self.handle(event, source: .poll)
        }
      } catch let error as SpotifyAuthError where error == .missingStoredToken {
        // No token exists locally. This is the real signed-out path; refresh
        // rejections keep the credential and retry inside PollingService.
        coordLog.error("missing Spotify token; surfacing connect view")
        await MainActor.run { [weak self] in
          self?.settings.markSignedOut()
        }
      } catch let error as SpotifyAuthError {
        if case let .refreshRejected(status) = error {
          coordLog.error("Spotify refresh rejected with status \(status); preserving token and surfacing reconnect view")
          await MainActor.run { [weak self] in
            self?.settings.markConnectionNeedsAttention()
          }
        } else {
          coordLog.error("polling auth error: \(String(describing: error), privacy: .public)")
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
    refreshWeeklyMemoriesIfNeeded(delay: 12)
  }

  private func startRecentPlayRepair(reason: String, delay: TimeInterval = 0) {
    recentRepairTask?.cancel()
    recentRepairTask = Task { [weak self] in
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
      }
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
          self?.lastFM.flushSoon()
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
        invalidateDropdownSnapshots()
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
      guard let self else { return }
      // The notification is the cue to read the Spotify app now. When the
      // app is readable that read carries the same data, so the raw payload
      // is only used while Dial is on the Web API (e.g. access turned off).
      self.poller.wake()
      guard !self.playbackSource.readsSpotifyApp else { return }
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
    await MainActor.run {
      invalidateDropdownSnapshots()
    }
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
      invalidateDropdownSnapshots()
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
    func beginPollInterval(_ name: StaticString) -> DialPerfInterval? {
      source == .poll ? DialPerf.begin(name) : nil
    }
    func endPerf() {
      guard !perfEnded else { return }
      perf?.end()
      perfEnded = true
    }
    defer { endPerf() }

    // Keep the Settings heartbeat tied to the poll loop (Spotify app reads
    // or the Web API). Raw desktop notifications aren't proof it's alive.
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
      let visibleReadPerf = beginPollInterval("playback.visible_state_read")
      let visibleState = await MainActor.run {
        (
          existingTrack: nowPlaying.track,
          durationMs: menubar.durationMs
        )
      }
      visibleReadPerf?.end()
      let existingTrack = visibleState.existingTrack
      let trackChanged = reduction.trackChanged || existingTrack?.uri != uri

      let canReuseExistingMetadata = !trackChanged
      let initialResolvedName = name.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.name ?? "") : "")
        : name
      let initialResolvedArtistName = artistName.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.artistName ?? "") : "")
        : artistName
      let initialResolvedArtistUri = artistUri
        ?? (canReuseExistingMetadata ? existingTrack?.artistUri : nil)
      let initialResolvedArtists: [PlaybackArtist] = {
        if !artists.isEmpty { return artists }
        guard let initialResolvedArtistUri else { return [] }
        return [PlaybackArtist(name: initialResolvedArtistName, uri: initialResolvedArtistUri)]
      }()
      let initialResolvedAlbumName = albumName.isEmpty
        ? (canReuseExistingMetadata ? (existingTrack?.albumName ?? "") : "")
        : albumName
      let initialResolvedArtUrl = artUrl ?? (canReuseExistingMetadata ? existingTrack?.artUrl : nil)
      let initialResolvedDurationMs = durationMs > 0
        ? durationMs
        : (canReuseExistingMetadata ? visibleState.durationMs : 0)

      // Publish the visible player state before cache warming and metadata
      // persistence. Those side effects matter, but they should not sit in
      // front of the "new track appeared" path.
      let initialTrack = NowPlayingViewModel.Track(
        uri: uri,
        name: initialResolvedName,
        artistName: initialResolvedArtistName,
        artistUri: initialResolvedArtistUri,
        artistUris: initialResolvedArtists.map(\.uri).filter { $0.hasPrefix("spotify:artist:") },
        albumName: initialResolvedAlbumName,
        artUrl: initialResolvedArtUrl)
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
        if trackChanged {
          currentTrackCountedAt = nil
          menubar.setOptimisticProgress(0)
          clearAmbientTrick()
        }
        nowPlaying.track = initialTrack
        menubar.track = initialTrack
        menubar.state = .playing
        menubar.durationMs = initialResolvedDurationMs
        if trackChanged || menubar.likedTrackState == .unknown {
          refreshLikedState(for: uri)
        }
        resolvePetBehavior()
      }
      visiblePublishPerf?.end()
      endPerf()

      let needsStoredMetadata = trackChanged && (
        initialResolvedName.isEmpty ||
        initialResolvedArtistName.isEmpty ||
        initialResolvedArtistUri == nil ||
        initialResolvedArtists.isEmpty ||
        initialResolvedAlbumName.isEmpty ||
        initialResolvedArtUrl == nil ||
        initialResolvedDurationMs <= 0
      )
      let storedTrack = needsStoredMetadata ? (try? TracksDAO(dbq: dbq).fetch(uri: uri)) : nil
      let storedArtists = Self.playbackArtists(from: storedTrack?.artistsJson)
      let resolvedName = initialResolvedName.isEmpty ? (storedTrack?.name ?? "") : initialResolvedName
      let resolvedArtistName = initialResolvedArtistName.isEmpty
        ? (storedArtists.first?.name ?? "")
        : initialResolvedArtistName
      let resolvedArtistUri = initialResolvedArtistUri ?? storedArtists.first?.uri
      let resolvedArtists: [PlaybackArtist] = {
        if !initialResolvedArtists.isEmpty { return initialResolvedArtists }
        if !storedArtists.isEmpty { return storedArtists }
        guard let resolvedArtistUri else { return [] }
        return [PlaybackArtist(name: resolvedArtistName, uri: resolvedArtistUri)]
      }()
      let resolvedAlbumName = initialResolvedAlbumName.isEmpty
        ? (storedTrack?.albumName ?? "")
        : initialResolvedAlbumName
      let resolvedArtUrl = initialResolvedArtUrl ?? storedTrack?.albumArtUrl
      let resolvedDurationMs = initialResolvedDurationMs > 0
        ? initialResolvedDurationMs
        : Int(storedTrack?.durationMs ?? 0)
      let resolvedTrack = NowPlayingViewModel.Track(
        uri: uri,
        name: resolvedName,
        artistName: resolvedArtistName,
        artistUri: resolvedArtistUri,
        artistUris: resolvedArtists.map(\.uri).filter { $0.hasPrefix("spotify:artist:") },
        albumName: resolvedAlbumName,
        artUrl: resolvedArtUrl)

      if resolvedTrack != initialTrack || resolvedDurationMs != initialResolvedDurationMs {
        await MainActor.run {
          guard nowPlaying.track?.uri == uri else { return }
          nowPlaying.track = resolvedTrack
          menubar.track = resolvedTrack
          menubar.durationMs = resolvedDurationMs
        }
      }

      let scrobbleTrack = ScrobbleTracker.Track(
        uri: uri,
        artist: resolvedArtists.first?.name ?? resolvedArtistName,
        name: resolvedName,
        album: resolvedAlbumName.isEmpty ? nil : resolvedAlbumName,
        durationMs: resolvedDurationMs)
      await MainActor.run {
        guard nowPlaying.track?.uri == uri else { return }
        lastFM.trackStarted(scrobbleTrack)
      }

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

      playbackPostRenderTask?.cancel()
      let nextPostRender = Task(priority: .utility) { [weak self] in
        guard let self, !Task.isCancelled else { return }

        let stillCurrent = await MainActor.run { self.nowPlaying.track?.uri == uri }
        guard stillCurrent, !Task.isCancelled else { return }

        let postRenderComputePerf = source == .poll
          ? DialPerf.begin("playback.post_render_compute")
          : nil
        let aggregationSnapshot = self.aggCache.snapshot(
          trackUri: uri,
          artistUri: resolvedArtistUri,
          currentPlayAt: nil)
        let soundThemeDecision = self.makeSoundThemeDecision(
          for: resolvedArtists.map(\.uri),
          allowFallback: !trackChanged,
          trackName: resolvedName,
          artistName: resolvedArtistName,
          albumName: resolvedAlbumName)
        postRenderComputePerf?.end()
        guard !Task.isCancelled else { return }

        let postRenderApplyPerf = source == .poll
          ? DialPerf.begin("playback.post_render_apply")
          : nil
        await MainActor.run {
          guard self.nowPlaying.track?.uri == uri else { return }
          self.aggCache.apply(aggregationSnapshot)
          self.applySoundThemeDecision(soundThemeDecision)
          self.warmCurrentSoundTags(for: resolvedArtists)
          self.nowPlaying.playsYTD = self.aggCache.playsYTD
          self.menubar.playsYTD = self.aggCache.playsYTD
          self.updatePetMemoryText()
          self.resolvePetBehavior()
        }
        postRenderApplyPerf?.end()

        // BPM lookup is best-effort for the beat-sync animation.
        if trackChanged,
           let trackId = uri.split(separator: ":").last,
           await SpotifyRateLimitGate.shared.cooldownRemaining() <= 0,
           let features = try? await self.client.audioFeatures(trackId: String(trackId)) {
          await MainActor.run {
            guard self.nowPlaying.track?.uri == uri else { return }
            self.pet.currentBPM = features.tempo
            self.resolvePetBehavior()
          }
        }
      }
      playbackPostRenderTask = nextPostRender

    case .paused:
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
        menubar.state = .paused
        lastFM.paused()
        resolvePetBehavior()
      }
      visiblePublishPerf?.end()
      endPerf()

    case .resumed:
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
        menubar.state = .playing
        lastFM.resumed()
        resolvePetBehavior()
      }
      visiblePublishPerf?.end()
      endPerf()

    case .noPlayback:
      playbackPostRenderTask?.cancel()
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
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
        lastFM.stopped()
        aggCache.refresh(trackUri: nil, artistUri: nil, currentPlayAt: nil)
        resolvePetBehavior()
      }
      visiblePublishPerf?.end()
      endPerf()

    case let .progress(ms):
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
        menubar.progressMs = ms
        menubar.lastProgressUpdate = Date()
        lastFM.progress(ms: ms)
      }
      visiblePublishPerf?.end()
      endPerf()

    case let .modesChanged(shuffle, repeatMode):
      let visiblePublishPerf = beginPollInterval("playback.visible_publish")
      await MainActor.run {
        menubar.applyRemoteModes(shuffle: shuffle, repeatMode: repeatMode)
      }
      visiblePublishPerf?.end()
      endPerf()

    case let .countedPlay(uri, ms, at):
      let visibleReadPerf = beginPollInterval("playback.visible_state_read")
      let countedContext = await MainActor.run {
        (
          xpBefore: pet.xp,
          artistUri: nowPlaying.track?.artistUri,
          trackName: nowPlaying.track?.name ?? "this play"
        )
      }
      visibleReadPerf?.end()
      endPerf()
      let previousSideEffects = countedPlaySideEffectsTask
      let nextSideEffects = Task(priority: .utility) { [weak self] in
        await previousSideEffects?.value
        guard !Task.isCancelled else { return }
        await self?.finishCountedPlay(
          uri: uri,
          ms: ms,
          at: at,
          xpBefore: countedContext.xpBefore,
          artistUri: countedContext.artistUri,
          trackName: countedContext.trackName)
      }
      countedPlaySideEffectsTask = nextSideEffects
    }
  }

  private func finishCountedPlay(
    uri: String,
    ms: Int64,
    at: Int64,
    xpBefore: Int64,
    artistUri: String?,
    trackName: String
  ) async {
    let perf = DialPerf.begin("playback.counted_play_side_effects")
    defer { perf.end() }

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

    let currentPlayAt: Int64? = didRecord ? at : nil
    let aggregationSnapshot = aggCache.snapshot(
      trackUri: uri,
      artistUri: artistUri,
      currentPlayAt: currentPlayAt)
    let petState = try? PetStateDAO(dbq: dbq).get()

    await MainActor.run {
      let stillCurrent = nowPlaying.track?.uri == uri
      if didRecord {
        invalidateDropdownSnapshots()
      }

      if stillCurrent {
        currentTrackCountedAt = currentPlayAt
        aggCache.apply(aggregationSnapshot)
        nowPlaying.playsYTD = aggCache.playsYTD
        menubar.playsYTD = aggCache.playsYTD
      }

      if let petState {
        pet.apply(petState)
      }

      if didRecord {
        coordLog.notice("recorded live play: \(uri, privacy: .public) (\(ms)ms)")
        lastFM.livePlayRecorded(uri: uri, playedAt: at, msPlayed: ms)
        if stillCurrent {
          let xpDelta = max(0, pet.xp - xpBefore)
          pet.lastFeedingText = xpDelta > 0
            ? "+\(xpDelta.formatted()) XP · \(trackName)"
            : "Memory added · \(trackName)"
          updatePetMemoryText()
          pet.isEating = true
          resolvePetBehavior()
          scheduleAmbientTrickIfNeeded()
        }
      } else {
        coordLog.notice("ignored duplicate live play: \(uri, privacy: .public) (\(ms)ms)")
        if stillCurrent {
          updatePetMemoryText()
          resolvePetBehavior()
        }
      }
    }

    if didRecord {
      refreshWeeklyMemoriesIfNeeded()
      // A counted play gets a tiny creature pulse, then settles back into the
      // current listening motion. The UI copy stays about memory/XP, not chores.
      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard let self else { return }
        self.pet.isEating = false
        self.resolvePetBehavior()
      }
    }
  }

  private func refreshWeeklyMemoriesIfNeeded(limit: Int = 12, delay: TimeInterval = 0) {
    guard settings.petEnabled, settings.livingMemoriesEnabled else { return }
    guard weeklyMemoriesTask == nil else { return }
    let dbq = self.dbq
    weeklyMemoriesTask = Task(priority: .background) { [weak self] in
      defer { self?.weeklyMemoriesTask = nil }
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
      }
      let perf = DialPerf.begin("weekly_memories.refresh")
      defer { perf.end() }
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
    applySoundThemeDecision(makeSoundThemeDecision(
      for: artistUris,
      allowFallback: allowFallback,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName))
  }

  private func makeSoundThemeDecision(
    for artistUris: [String],
    allowFallback: Bool = true,
    trackName: String? = nil,
    artistName: String? = nil,
    albumName: String? = nil
  ) -> SoundThemeDecision? {
    let artistUris = artistUris
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let queries = StatsQueries(dbq: dbq)
    return try? queries.soundThemeDecision(
      forArtistUris: artistUris,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      allowRecentFallback: allowFallback)
  }

  private func applySoundThemeDecision(_ decision: SoundThemeDecision?) {
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

  /// A like or unlike made in Dial, confirmed by Spotify. Mirrored to
  /// Last.fm's Loved tracks when scrobbling is on.
  @MainActor
  private func syncLovedTrack(uri: String, liked: Bool) {
    // Same primary artist the scrobble uses: the stored artist list first,
    // then the name on screen.
    let stored = try? TracksDAO(dbq: dbq).fetch(uri: uri)
    let current = nowPlaying.track?.uri == uri ? nowPlaying.track : nil
    let name = current?.name ?? stored?.name ?? ""
    let artist = Self.playbackArtists(from: stored?.artistsJson).first?.name
      ?? current?.artistName
      ?? ""
    lastFM.setLoved(liked, artist: artist, track: name)
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
