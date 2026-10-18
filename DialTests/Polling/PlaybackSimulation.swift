import Foundation
@testable import Dial

/// A scripted listening session on a virtual clock. The same timeline is
/// visible two ways: the Spotify app on this Mac (`localSource`) and the Web
/// API (`webClient`, which sees every device and lags a little).
final class SimulatedSpotify: @unchecked Sendable {
  enum Device { case mac, phone }

  struct Track {
    let uri: String
    let name: String
    let artistUri: String
    let durationMs: Int
  }

  /// One stretch of continuous state: `track` on `device`, from `start` to
  /// `end` seconds, beginning at `startProgressMs`.
  struct Segment {
    let start: TimeInterval
    let end: TimeInterval
    let device: Device
    let track: Track
    let startProgressMs: Int
    let playing: Bool
  }

  let t0 = Date(timeIntervalSince1970: 1_779_000_000)
  var now: TimeInterval = 0
  var segments: [Segment] = []
  /// Spotify desktop app running windows, in seconds. Default: always.
  var appRunning: [ClosedRange<TimeInterval>] = [0...TimeInterval.greatestFiniteMagnitude]
  /// Forces a reading (e.g. `.accessDenied`) while the app is running.
  var forcedLocalReading: LocalPlaybackReading?
  var webLag: TimeInterval = 1
  /// Notification delivery + Apple Event latency.
  var notificationDelay: TimeInterval = 0.05
  private(set) var webCalls = 0
  /// The poll task can run a cycle past the end before the consumer stops
  /// it; calls and reads after this time aren't counted.
  var countUntil: TimeInterval = .infinity

  // Strong references on purpose: the poll task can still be finishing a
  // cycle after the test stops reading, so the world must outlive it.
  lazy var webClient = SimulatedWebClient(world: self)
  lazy var localSource = SimulatedLocalSource(world: self)
  lazy var scheduler = VirtualPollScheduler(world: self)

  var clock: () -> Int64 { { Int64(self.t0.timeIntervalSince1970 + self.now) } }

  // MARK: Building a session

  private var cursor: TimeInterval = 0

  /// Plays `track` on `device` for `seconds`, starting at `fromMs`.
  @discardableResult
  func play(_ track: Track, on device: Device = .mac, for seconds: TimeInterval, fromMs: Int = 0) -> SimulatedSpotify {
    segments.append(.init(start: cursor, end: cursor + seconds, device: device, track: track,
                          startProgressMs: fromMs, playing: true))
    cursor += seconds
    return self
  }

  /// Holds `track` paused at `atMs` on `device` for `seconds`.
  @discardableResult
  func pause(_ track: Track, on device: Device = .mac, atMs: Int, for seconds: TimeInterval) -> SimulatedSpotify {
    segments.append(.init(start: cursor, end: cursor + seconds, device: device, track: track,
                          startProgressMs: atMs, playing: false))
    cursor += seconds
    return self
  }

  var sessionLength: TimeInterval { cursor }

  // MARK: Reading the world

  func segment(at t: TimeInterval) -> Segment? {
    segments.first { $0.start <= t && t < $0.end }
  }

  func progressMs(of segment: Segment, at t: TimeInterval) -> Int {
    guard segment.playing else { return segment.startProgressMs }
    return min(segment.track.durationMs, segment.startProgressMs + Int(((t - segment.start) * 1_000).rounded()))
  }

  func isAppRunning(at t: TimeInterval) -> Bool {
    appRunning.contains { $0.contains(t) }
  }

  func webResponse() -> CurrentlyPlaying? {
    if now < countUntil { webCalls += 1 }
    let t = max(0, now - webLag)
    guard let seg = segment(at: t) else { return nil }
    return .init(
      item: .init(uri: seg.track.uri, name: seg.track.name, duration_ms: seg.track.durationMs,
                  artists: [.init(name: "Artist", uri: seg.track.artistUri)],
                  album: .init(name: "Album", images: [.init(url: "https://i.scdn.co/\(seg.track.uri)")])),
      is_playing: seg.playing,
      progress_ms: progressMs(of: seg, at: t),
      shuffle_state: false,
      repeat_state: "off")
  }

  func localReading() -> LocalPlaybackReading {
    guard isAppRunning(at: now) else { return .notRunning }
    if let forcedLocalReading { return forcedLocalReading }
    if let seg = segment(at: now), seg.device == .mac {
      return .playback(snapshot(seg, playing: seg.playing, progressMs: progressMs(of: seg, at: now)))
    }
    // Idle app: the last track it played locally stays loaded, paused.
    if let last = segments.last(where: { $0.device == .mac && $0.start <= now }) {
      return .playback(snapshot(last, playing: false, progressMs: progressMs(of: last, at: min(now, last.end))))
    }
    return .playback(.init(track: nil, isPlaying: false, progressMs: 0))
  }

  private func snapshot(_ seg: Segment, playing: Bool, progressMs: Int) -> LocalPlaybackSnapshot {
    .init(
      track: .init(uri: seg.track.uri, name: seg.track.name, artistName: "Artist", albumName: "Album",
                   artUrl: "https://i.scdn.co/\(seg.track.uri)", durationMs: seg.track.durationMs),
      isPlaying: playing,
      progressMs: progressMs)
  }

  /// When Spotify on this Mac posts PlaybackStateChanged.
  func nextNotification(after t: TimeInterval, upTo limit: TimeInterval) -> TimeInterval? {
    let boundaries = segments.filter { $0.device == .mac }.flatMap { [$0.start, $0.end] }
    return boundaries
      .map { $0 + notificationDelay }
      .filter { $0 > t && $0 <= limit && isAppRunning(at: $0) }
      .min()
  }
}

final class SimulatedWebClient: PollingClient, @unchecked Sendable {
  let world: SimulatedSpotify
  init(world: SimulatedSpotify) { self.world = world }
  func currentlyPlaying() async throws -> CurrentlyPlaying? { world.webResponse() }
}

final class SimulatedLocalSource: LocalPlaybackSource, @unchecked Sendable {
  let world: SimulatedSpotify
  private(set) var reads = 0
  init(world: SimulatedSpotify) { self.world = world }
  func read() async -> LocalPlaybackReading {
    if world.now < world.countUntil { reads += 1 }
    return world.localReading()
  }
}

/// Advances the world's clock instead of sleeping. A wait ends early at the
/// next Spotify notification, like `WakeablePollScheduler` does.
final class VirtualPollScheduler: PollScheduler, @unchecked Sendable {
  let world: SimulatedSpotify
  var notificationsEnabled = true
  init(world: SimulatedSpotify) { self.world = world }

  func now() -> Date { world.t0.addingTimeInterval(world.now) }

  func wait(upTo seconds: TimeInterval) async {
    let target = world.now + max(seconds, 0.01)
    if notificationsEnabled, let wake = world.nextNotification(after: world.now, upTo: target) {
      world.now = wake
    } else {
      world.now = target
    }
    await Task.yield()
  }

  func wake() {}
}

/// The pre-local-source poll loop, verbatim except that `Task.sleep` became
/// the virtual scheduler. It's the "before" baseline for call counts and
/// counted plays.
final class LegacyPollingService {
  private let client: PollingClient
  private let interval: TimeInterval
  private let clock: () -> Int64
  private let scheduler: PollScheduler
  private var lastTrackUri: String?
  private var counted = false
  private var playbackState: Bool? = nil
  private var lastShuffle: Bool? = nil
  private var lastRepeat: RepeatMode? = nil

  init(client: PollingClient, interval: TimeInterval, scheduler: PollScheduler, clock: @escaping () -> Int64) {
    self.client = client
    self.interval = interval
    self.scheduler = scheduler
    self.clock = clock
  }

  func stream() -> AsyncThrowingStream<PlaybackEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          if let cp = try? await client.currentlyPlaying() {
            for e in interpret(cp) { continuation.yield(e) }
          } else {
            for e in interpret(nil) { continuation.yield(e) }
          }
          await scheduler.wait(upTo: interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func interpret(_ cp: CurrentlyPlaying?) -> [PlaybackEvent] {
    guard let cp, let item = cp.item else {
      lastTrackUri = nil; counted = false; playbackState = nil
      return [.noPlayback]
    }
    var out: [PlaybackEvent] = []
    if item.uri != lastTrackUri {
      lastTrackUri = item.uri; counted = false
      let artists = item.artists.map { PlaybackArtist(name: $0.name, uri: $0.uri) }
      out.append(.started(
        trackUri: item.uri, name: item.name,
        artistName: artists.first?.name ?? "",
        artistUri: artists.first?.uri,
        artists: artists,
        albumName: item.album.name,
        artUrl: item.album.images.first?.url,
        durationMs: item.duration_ms,
        at: clock()))
      if let p = cp.progress_ms,
         DedupRule.shouldCount(progressMs: p, durationMs: item.duration_ms) {
        counted = true
      }
    }
    if let p = cp.progress_ms {
      out.append(.progress(ms: p))
      if cp.is_playing,
         !counted,
         DedupRule.shouldCount(progressMs: p, durationMs: item.duration_ms) {
        counted = true
        let approximatePlayStartedAt = clock() - Int64(max(0, p) / 1000)
        out.append(.countedPlay(trackUri: item.uri, msPlayed: Int64(p), at: approximatePlayStartedAt))
      }
    }
    if playbackState != cp.is_playing {
      out.append(cp.is_playing ? .resumed : .paused)
      playbackState = cp.is_playing
    }
    let shuffle = cp.shuffle_state ?? false
    let repeatMode = cp.repeat_state.flatMap(RepeatMode.init(rawValue:)) ?? .off
    if lastShuffle != shuffle || lastRepeat != repeatMode {
      out.append(.modesChanged(shuffle: shuffle, repeatMode: repeatMode))
      lastShuffle = shuffle
      lastRepeat = repeatMode
    }
    return out
  }
}

struct SimulationRun {
  var events: [PlaybackEvent] = []
  var statuses: [PlaybackSourceStatus] = []
  var webCalls = 0
  var localReads = 0

  var countedUris: [String] {
    events.compactMap { if case let .countedPlay(uri, _, _) = $0 { return uri } else { return nil } }
  }
  var countedPlays: [(uri: String, ms: Int64, at: Int64)] {
    events.compactMap { if case let .countedPlay(uri, ms, at) = $0 { return (uri, ms, at) } else { return nil } }
  }
}

extension SimulatedSpotify {
  /// Drains `stream` until the virtual clock passes `seconds`.
  func run(_ stream: AsyncThrowingStream<PlaybackEvent, Error>, for seconds: TimeInterval) async throws -> [PlaybackEvent] {
    countUntil = seconds
    var events: [PlaybackEvent] = []
    for try await e in stream {
      events.append(e)
      if now >= seconds { break }
    }
    return events
  }

  /// The new service: Spotify app first, Web API behind it.
  func runCurrent(for seconds: TimeInterval, timing: PollingTiming = .standard(webInterval: 2)) async throws -> SimulationRun {
    let service = PollingService(
      client: webClient, interval: 2, localSource: localSource, timing: timing,
      scheduler: scheduler, clock: clock)
    var run = SimulationRun()
    let statusLock = NSLock()
    var statuses: [PlaybackSourceStatus] = []
    service.onStatusChange = { status in
      statusLock.lock(); statuses.append(status); statusLock.unlock()
    }
    let callsBefore = webCalls
    run.events = try await self.run(service.stream(), for: seconds)
    run.statuses = statuses
    run.webCalls = webCalls - callsBefore
    run.localReads = localSource.reads
    return run
  }

  /// The pre-change Web-API-only loop.
  func runLegacy(for seconds: TimeInterval) async throws -> SimulationRun {
    let service = LegacyPollingService(client: webClient, interval: 2, scheduler: scheduler, clock: clock)
    scheduler.notificationsEnabled = false
    defer { scheduler.notificationsEnabled = true }
    var run = SimulationRun()
    let callsBefore = webCalls
    run.events = try await self.run(service.stream(), for: seconds)
    run.webCalls = webCalls - callsBefore
    return run
  }

  static func track(_ id: String, seconds: Int) -> Track {
    Track(uri: "spotify:track:\(id)", name: "Song \(id)", artistUri: "spotify:artist:\(id)", durationMs: seconds * 1_000)
  }
}
