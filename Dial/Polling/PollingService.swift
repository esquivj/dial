import Foundation
import os.log

private let pollingLog = Logger(subsystem: "com.dial.Dial", category: "PollingService")

protocol PollingClient {
  func currentlyPlaying() async throws -> CurrentlyPlaying?
}
extension SpotifyClient: PollingClient {}

/// Which feed is answering for now-playing state right now.
enum PlaybackSourceStatus: Equatable {
  case spotifyApp
  case webAPI(WebAPIReason)

  enum WebAPIReason: Equatable {
    case noLocalSource
    case appNotRunning
    case accessPending
    case accessDenied
    case appUnavailable
    /// The Spotify app is open but idle while another device plays.
    case remoteDevice
  }

  /// True when the Spotify app answered the last read. Its notifications
  /// then reach the HUD through `PollingService.wake()`, so the raw
  /// notification feed is redundant.
  var readsSpotifyApp: Bool {
    switch self {
    case .spotifyApp, .webAPI(.remoteDevice): return true
    case .webAPI: return false
    }
  }
}

/// How often each feed is asked, by situation.
struct PollingTiming: Equatable {
  /// Web API is the only source (Spotify app closed, access off, or another
  /// device playing). Same cadence as before the local source existed.
  var webInterval: TimeInterval
  /// Spotify app reads. Local Apple Events, no network, no rate limit.
  var localInterval: TimeInterval = 2
  /// Spotify app open but idle: how often to look for playback elsewhere.
  var remoteCheckInterval: TimeInterval = 10
  /// Spotify app playing: Web API refresh for shuffle/repeat, which the app
  /// doesn't report reliably.
  var webSafetyInterval: TimeInterval = 30
  /// After a track change, the Web API is asked for artist URIs and album art
  /// a few times until it catches up with the app.
  var metadataRetryInterval: TimeInterval = 2
  var metadataAttempts = 4
  /// The Web API trails the app by a second or two. For this long after the
  /// app stops playing, a Web API "playing" report for the same track is the
  /// app's own echo, not a phone taking over.
  var localEchoWindow: TimeInterval = 5

  static func standard(webInterval: TimeInterval) -> PollingTiming {
    PollingTiming(webInterval: webInterval)
  }
}

/// Sleeps between poll cycles. `wake()` ends the current wait early.
protocol PollScheduler: AnyObject {
  func now() -> Date
  func wait(upTo seconds: TimeInterval) async
  func wake()
}

/// Turns playback state into `PlaybackEvent`s.
///
/// Two sources can answer: the Spotify desktop app (local, instant) and the
/// Web API (any device). Each cycle feeds exactly one of them into
/// `interpret`, so the once-per-track counting flag and `DedupRule` see one
/// consistent stream no matter which source answered:
///
/// - Spotify app playing: the app is authoritative. The Web API is only
///   asked for metadata after a track change and for shuffle/repeat.
/// - Spotify app idle: the app's state is shown, and the Web API is checked
///   now and then in case a phone or speaker starts playing.
/// - Spotify app closed or not readable: Web API only, as before.
final class PollingService {
  private let client: PollingClient
  private let localSource: LocalPlaybackSource?
  private let timing: PollingTiming
  private let scheduler: PollScheduler
  private let clock: () -> Int64
  private var lastTrackUri: String?
  private var counted = false
  private var playbackState: Bool? = nil
  // Track previous shuffle/repeat so we only emit modesChanged on actual
  // change, not every 3s. nil means we haven't observed yet — first
  // observation always emits.
  private var lastShuffle: Bool? = nil
  private var lastRepeat: RepeatMode? = nil

  // Source arbitration.
  private enum Authority { case local, web }
  private var authority: Authority?
  private var remotePlaying = false
  private var lastLocalPlayingAt: Date?
  private var lastWebAttemptAt: Date?
  private var webFailures = 0
  private var refreshRejections = 0
  private var metadataPendingUri: String?
  private var metadataAttemptsMade = 0
  private var status: PlaybackSourceStatus?

  /// Called on the polling task whenever the answering source changes.
  var onStatusChange: ((PlaybackSourceStatus) -> Void)?

  init(client: PollingClient,
       interval: TimeInterval = 3.0,
       localSource: LocalPlaybackSource? = nil,
       timing: PollingTiming? = nil,
       scheduler: PollScheduler = WakeablePollScheduler(),
       clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
    self.client = client
    self.localSource = localSource
    self.timing = timing ?? .standard(webInterval: interval)
    self.scheduler = scheduler
    self.clock = clock
  }

  /// Read again now. Wired to Spotify's PlaybackStateChanged notification.
  func wake() {
    scheduler.wake()
  }

  func stream() -> AsyncThrowingStream<PlaybackEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        pollingLog.notice("polling stream started, webInterval=\(self.timing.webInterval)s local=\(self.localSource != nil)")
        while !Task.isCancelled {
          do {
            let delay = try await self.cycle { continuation.yield($0) }
            await self.scheduler.wait(upTo: delay)
          } catch {
            continuation.finish(throwing: error)
            return
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - One cycle

  /// Runs one read-and-emit cycle and returns how long to wait before the
  /// next. Throws only errors that should end the stream (signed out).
  private func cycle(_ emit: (PlaybackEvent) -> Void) async throws -> TimeInterval {
    let reading = await localSource?.read()
    if case let .playback(local)? = reading {
      if local.isPlaying {
        return try await localPlayingCycle(local, emit)
      }
      return try await localIdleCycle(local, emit)
    }
    return try await webOnlyCycle(reason: Self.reason(for: reading), emit)
  }

  private func localPlayingCycle(
    _ local: LocalPlaybackSnapshot,
    _ emit: (PlaybackEvent) -> Void
  ) async throws -> TimeInterval {
    authority = .local
    remotePlaying = false
    lastLocalPlayingAt = scheduler.now()
    publish(.spotifyApp)

    let previousUri = lastTrackUri
    for e in interpret(PlaybackSnapshot(local: local)) { emit(e) }
    if let uri = local.track?.uri, uri != previousUri {
      metadataPendingUri = uri
      metadataAttemptsMade = 0
    } else if local.track == nil {
      metadataPendingUri = nil
    }

    if localWebIsDue() {
      if metadataPendingUri != nil { metadataAttemptsMade += 1 }
      if let response = try await fetchWeb() {
        // Shuffle/repeat are account-wide, so they apply whatever the Web
        // API thinks is playing.
        for e in modeEvents(PlaybackSnapshot(web: response)) { emit(e) }
        if let pending = metadataPendingUri,
           let track = PlaybackSnapshot(web: response).track,
           track.uri == pending,
           pending == lastTrackUri {
          // Same track, richer data (artist URIs, all artists). Emitted
          // outside `interpret` so the counting state is untouched.
          emit(Self.startedEvent(for: track, at: clock()))
          metadataPendingUri = nil
        }
      }
      if metadataAttemptsMade >= timing.metadataAttempts { metadataPendingUri = nil }
    }
    return timing.localInterval
  }

  private func localIdleCycle(
    _ local: LocalPlaybackSnapshot,
    _ emit: (PlaybackEvent) -> Void
  ) async throws -> TimeInterval {
    metadataPendingUri = nil
    let webInterval = remotePlaying ? timing.webInterval : timing.remoteCheckInterval
    if webIsDue(every: webInterval), let response = try await fetchWeb() {
      remotePlaying = response?.is_playing == true && !isLocalEcho(response, local: local)
      if remotePlaying {
        authority = .web
      } else if authority == nil {
        authority = .local
      }
      if authority == .web {
        for e in interpret(PlaybackSnapshot(web: response)) { emit(e) }
      }
    }
    // Stay with whichever source last reported playing, so a paused phone
    // doesn't flip the HUD to whatever the idle app last had loaded.
    if authority != .web {
      for e in interpret(PlaybackSnapshot(local: local)) { emit(e) }
    }
    publish(authority == .web ? .webAPI(.remoteDevice) : .spotifyApp)
    return min(timing.localInterval, webWait(every: remotePlaying ? timing.webInterval : timing.remoteCheckInterval))
  }

  private func webOnlyCycle(
    reason: PlaybackSourceStatus.WebAPIReason,
    _ emit: (PlaybackEvent) -> Void
  ) async throws -> TimeInterval {
    authority = .web
    metadataPendingUri = nil
    publish(.webAPI(reason))
    if webIsDue(every: timing.webInterval), let response = try await fetchWeb() {
      remotePlaying = response?.is_playing == true
      for e in interpret(PlaybackSnapshot(web: response)) { emit(e) }
    }
    return webWait(every: timing.webInterval)
  }

  private func isLocalEcho(_ response: CurrentlyPlaying?, local: LocalPlaybackSnapshot) -> Bool {
    guard authority == .local,
          let lastLocalPlayingAt,
          scheduler.now().timeIntervalSince(lastLocalPlayingAt) < timing.localEchoWindow,
          let uri = response?.item?.uri
    else { return false }
    return uri == local.track?.uri
  }

  // MARK: - Web API

  private func localWebIsDue() -> Bool {
    if metadataPendingUri != nil, metadataAttemptsMade < timing.metadataAttempts {
      if metadataAttemptsMade == 0 { return true }
      return webIsDue(every: timing.metadataRetryInterval)
    }
    return webIsDue(every: timing.webSafetyInterval)
  }

  private func webIsDue(every interval: TimeInterval) -> Bool {
    webWait(every: interval) <= 0
  }

  /// Seconds until the Web API may be asked again, including failure backoff.
  private func webWait(every interval: TimeInterval) -> TimeInterval {
    guard let last = lastWebAttemptAt else { return 0 }
    // Backoff schedule (webInterval = 2s baseline):
    //   1st fail: 2s, 2nd: 4s, 3rd: 8s, 4th: 16s, 5th: 32s, then 60s cap.
    let backoff = webFailures > 0
      ? min(timing.webInterval * pow(2.0, Double(min(webFailures - 1, 6))), 60.0)
      : 0
    let wait = max(interval, backoff) - scheduler.now().timeIntervalSince(last)
    // Sub-millisecond leftovers are clock rounding, not a reason to skip.
    return wait > 0.001 ? wait : 0
  }

  /// One `/me/player` call. Returns nil when the call failed in a way worth
  /// retrying (the cycle then emits nothing from the Web API), `.some(nil)`
  /// when nothing is playing anywhere.
  private func fetchWeb() async throws -> CurrentlyPlaying?? {
    // Spacing is measured from when the call finishes, like the old
    // call-then-sleep loop, so web-only polling is never faster than before.
    defer { lastWebAttemptAt = scheduler.now() }
    do {
      let cp = try await client.currentlyPlaying()
      // Per-poll outcome at debug level — quiet by default but
      // available via `log show --debug` for live-play diagnosis.
      if let item = cp?.item {
        pollingLog.debug("poll: \(item.name, privacy: .public) at \(cp?.progress_ms ?? -1)ms (playing=\(cp?.is_playing ?? false))")
      } else {
        pollingLog.debug("poll: no playback")
      }
      webFailures = 0
      refreshRejections = 0
      return .some(cp)
    } catch {
      // No local token means there is nothing to refresh. A rejected
      // refresh token gets a short retry window, then surfaces as a
      // connection-needs-attention state without deleting the credential.
      if let authError = error as? SpotifyAuthError {
        if authError == .missingStoredToken { throw error }
        if case .refreshRejected = authError {
          refreshRejections += 1
          if refreshRejections >= 3 { throw error }
        } else {
          refreshRejections = 0
        }
      } else {
        refreshRejections = 0
      }
      // Everything else: keep the stream alive and back off. A single
      // Wi-Fi blip must not freeze the menubar for the rest of the session,
      // and while the Spotify app is playing, local reads carry on.
      webFailures += 1
      pollingLog.error("error #\(self.webFailures): \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  private func publish(_ next: PlaybackSourceStatus) {
    guard next != status else { return }
    status = next
    pollingLog.notice("playback source: \(String(describing: next), privacy: .public)")
    onStatusChange?(next)
  }

  private static func reason(for reading: LocalPlaybackReading?) -> PlaybackSourceStatus.WebAPIReason {
    switch reading {
    case nil: return .noLocalSource
    case .notRunning?: return .appNotRunning
    case .accessPending?: return .accessPending
    case .accessDenied?: return .accessDenied
    case .unavailable?: return .appUnavailable
    case .playback?: return .appUnavailable
    }
  }

  // MARK: - Interpretation (unchanged counting rules)

  private func interpret(_ snapshot: PlaybackSnapshot) -> [PlaybackEvent] {
    guard let item = snapshot.track else {
      lastTrackUri = nil; counted = false; playbackState = nil
      return [.noPlayback]
    }
    var out: [PlaybackEvent] = []
    if item.uri != lastTrackUri {
      lastTrackUri = item.uri; counted = false
      out.append(Self.startedEvent(for: item, at: clock()))
      if let p = snapshot.progressMs,
         DedupRule.shouldCount(progressMs: p, durationMs: item.durationMs) {
        // First sighting is already past the count threshold. That usually
        // means Dial relaunched mid-track, so don't duplicate the same play;
        // recently-played reconciliation will repair any genuinely missed row.
        counted = true
      }
    }
    if let p = snapshot.progressMs {
      out.append(.progress(ms: p))
      if snapshot.isPlaying,
         !counted,
         DedupRule.shouldCount(progressMs: p, durationMs: item.durationMs) {
        counted = true
        let approximatePlayStartedAt = clock() - Int64(max(0, p) / 1000)
        out.append(.countedPlay(trackUri: item.uri, msPlayed: Int64(p), at: approximatePlayStartedAt))
      }
    }
    if playbackState != snapshot.isPlaying {
      out.append(snapshot.isPlaying ? .resumed : .paused)
      playbackState = snapshot.isPlaying
    }
    out.append(contentsOf: modeEvents(snapshot))
    return out
  }

  /// Shuffle/repeat, only when they changed. The Spotify app's snapshot
  /// carries none, so the last Web API answer stands.
  private func modeEvents(_ snapshot: PlaybackSnapshot) -> [PlaybackEvent] {
    guard let shuffle = snapshot.shuffle, let repeatMode = snapshot.repeatMode else { return [] }
    guard lastShuffle != shuffle || lastRepeat != repeatMode else { return [] }
    lastShuffle = shuffle
    lastRepeat = repeatMode
    return [.modesChanged(shuffle: shuffle, repeatMode: repeatMode)]
  }

  private static func startedEvent(for item: PlaybackSnapshot.Track, at: Int64) -> PlaybackEvent {
    .started(
      trackUri: item.uri, name: item.name,
      artistName: item.artistName,
      artistUri: item.artistUri,
      artists: item.artists,
      albumName: item.albumName,
      artUrl: item.artUrl,
      durationMs: item.durationMs,
      at: at)
  }
}

/// One source-neutral reading of the player, the input to `interpret`.
struct PlaybackSnapshot: Equatable {
  struct Track: Equatable {
    let uri: String
    let name: String
    let artistName: String
    let artistUri: String?
    let artists: [PlaybackArtist]
    let albumName: String
    let artUrl: String?
    let durationMs: Int
  }

  let track: Track?
  let isPlaying: Bool
  let progressMs: Int?
  /// nil means "this source doesn't know".
  let shuffle: Bool?
  let repeatMode: RepeatMode?

  init(web cp: CurrentlyPlaying?) {
    guard let cp, let item = cp.item else {
      self.track = nil
      self.isPlaying = false
      self.progressMs = nil
      self.shuffle = nil
      self.repeatMode = nil
      return
    }
    let artists = item.artists.map { PlaybackArtist(name: $0.name, uri: $0.uri) }
    self.track = Track(
      uri: item.uri,
      name: item.name,
      artistName: artists.first?.name ?? "",
      artistUri: artists.first?.uri,
      artists: artists,
      albumName: item.album.name,
      artUrl: item.album.images.first?.url,
      durationMs: item.duration_ms)
    self.isPlaying = cp.is_playing
    self.progressMs = cp.progress_ms
    // /me/player returns these consistently; /currently-playing wouldn't
    // have, hence the sensible defaults.
    self.shuffle = cp.shuffle_state ?? false
    self.repeatMode = cp.repeat_state.flatMap(RepeatMode.init(rawValue:)) ?? .off
  }

  init(local: LocalPlaybackSnapshot) {
    self.track = local.track.map {
      Track(
        uri: $0.uri,
        name: $0.name,
        artistName: $0.artistName,
        artistUri: nil,
        artists: [],
        albumName: $0.albumName,
        artUrl: $0.artUrl,
        durationMs: $0.durationMs)
    }
    self.isPlaying = local.isPlaying
    self.progressMs = local.track == nil ? nil : local.progressMs
    self.shuffle = nil
    self.repeatMode = nil
  }
}

/// Real-time scheduler. `wake()` cuts the current wait short; a wake that
/// arrives between waits is remembered and ends the next one immediately.
final class WakeablePollScheduler: PollScheduler, @unchecked Sendable {
  private let lock = NSLock()
  private var pendingWake = false
  private var waiter: (id: UInt64, continuation: CheckedContinuation<Void, Never>)?
  private var nextID: UInt64 = 0

  func now() -> Date { Date() }

  func wake() {
    lock.lock()
    if let waiter {
      self.waiter = nil
      lock.unlock()
      waiter.continuation.resume()
    } else {
      pendingWake = true
      lock.unlock()
    }
  }

  func wait(upTo seconds: TimeInterval) async {
    guard seconds > 0 else {
      await Task.yield()
      return
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        lock.lock()
        if pendingWake || Task.isCancelled {
          pendingWake = false
          lock.unlock()
          continuation.resume()
          return
        }
        nextID &+= 1
        let id = nextID
        waiter = (id, continuation)
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
          self?.resume(id: id)
        }
      }
    } onCancel: {
      self.resume(id: nil)
    }
  }

  private func resume(id: UInt64?) {
    lock.lock()
    guard let waiter, id == nil || waiter.id == id else {
      lock.unlock()
      return
    }
    self.waiter = nil
    lock.unlock()
    waiter.continuation.resume()
  }
}
