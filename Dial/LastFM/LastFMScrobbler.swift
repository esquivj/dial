// Dial/LastFM/LastFMScrobbler.swift
import Foundation
import GRDB
import Observation
import os.log

private let scrobbleLog = Logger(subsystem: "com.dial.Dial", category: "LastFMScrobbler")

enum LastFMConnectionState: Equatable {
  case disconnected
  case waitingForApproval
  case connected
  /// Last.fm rejected the session key (revoked from last.fm settings).
  case needsReconnect
}

/// Sends live plays to Last.fm.
///
/// Only live plays from `PollingService` reach it: the coordinator feeds it
/// playback events and the plays `PetEngine` recorded. Imported history and
/// recently-played sync rows never do, and `ScrobbleQueueDAO.enqueue`
/// refuses any play whose source isn't `live`.
///
/// Plays are queued in SQLite first, then sent oldest first in batches of
/// up to 50. A failed batch waits (1 min, doubling, capped at 1 h) and is
/// retried; the queue survives relaunches.
@MainActor
@Observable
final class LastFMScrobbler {
  private(set) var connection: LastFMConnectionState = .disconnected
  private(set) var username: String?
  private(set) var pendingCount = 0
  private(set) var lastScrobble: LastScrobble?
  /// Why the last send or connect attempt failed, in plain words.
  private(set) var problem: String?

  var scrobblingEnabled: Bool {
    didSet {
      defaults.set(scrobblingEnabled, forKey: Key.enabled)
      if scrobblingEnabled { flushSoon() }
    }
  }

  /// True when plays should be queued and sent right now.
  var isActive: Bool {
    scrobblingEnabled && connection == .connected && session != nil
  }

  @ObservationIgnored private let queue: ScrobbleQueueDAO
  @ObservationIgnored private let api: LastFMScrobbleAPI
  @ObservationIgnored private let credentials: () -> LastFMCredentials?
  @ObservationIgnored private let sessionKeyStore: SecretStringStore
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let clock: () -> Int64
  @ObservationIgnored private let sleep: (TimeInterval) async throws -> Void
  @ObservationIgnored private let autoFlush: Bool
  @ObservationIgnored private var sessionKey: String?
  @ObservationIgnored private var tracker = ScrobbleTracker()
  @ObservationIgnored private var flushTask: Task<Void, Never>?
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  @ObservationIgnored private var connectTask: Task<Void, Never>?
  @ObservationIgnored private var loveTask: Task<Void, Never>?

  static let batchSize = LastFMWebClient.maxBatch
  static let maxAgeSeconds: Int64 = 14 * 24 * 60 * 60
  static let approvalPollInterval: TimeInterval = 3
  static let approvalTimeout: Int64 = 10 * 60

  static func retryDelay(afterAttempts attempts: Int) -> Int64 {
    let exponent = min(max(attempts, 0), 6)
    return min(60 * (Int64(1) << exponent), 3_600)
  }

  init(
    dbq: DatabaseQueue,
    api: LastFMScrobbleAPI = LastFMWebClient(),
    credentials: @escaping () -> LastFMCredentials?,
    sessionKeyStore: SecretStringStore = LastFMSecretStorage.makeSessionKeyStore(),
    defaults: UserDefaults = .standard,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
    sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
    autoFlush: Bool = true
  ) {
    self.queue = ScrobbleQueueDAO(dbq: dbq)
    self.api = api
    self.credentials = credentials
    self.sessionKeyStore = sessionKeyStore
    self.defaults = defaults
    self.clock = clock
    self.sleep = sleep
    self.autoFlush = autoFlush
    self.scrobblingEnabled = defaults.bool(forKey: Key.enabled)
    let storedKey = ((try? sessionKeyStore.load()) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
    self.sessionKey = storedKey
    self.username = storedKey == nil ? nil : defaults.string(forKey: Key.username)
    self.connection = storedKey == nil ? .disconnected : .connected
    refreshStatus()
  }

  private var session: LastFMSession? {
    guard let sessionKey, let credentials = credentials() else { return nil }
    return LastFMSession(credentials: credentials, key: sessionKey)
  }

  // MARK: - Playback feed (live plays only)

  func trackStarted(_ track: ScrobbleTracker.Track) {
    perform(tracker.started(track))
  }

  func progress(ms: Int) {
    perform(tracker.progress(ms))
  }

  func paused() {
    tracker.paused()
  }

  func resumed() {
    perform(tracker.resumed())
  }

  func stopped() {
    tracker.stopped()
  }

  /// `PetEngine` recorded a counted live play for the current track.
  func livePlayRecorded(uri: String, playedAt: Int64, msPlayed: Int64) {
    guard let playId = try? queue.livePlayId(playedAt: playedAt, trackUri: uri, msPlayed: msPlayed) else {
      return
    }
    perform(tracker.counted(playId: playId, uri: uri, msPlayed: Int(msPlayed)))
  }

  private func perform(_ actions: [ScrobbleTracker.Action]) {
    for action in actions {
      switch action {
      case let .nowPlaying(track):
        sendNowPlaying(track)
      case let .scrobble(candidate):
        enqueue(candidate)
      }
    }
  }

  private func sendNowPlaying(_ track: ScrobbleTracker.Track) {
    guard isActive, let session else { return }
    let entry = LastFMScrobbleEntry(
      artist: track.artist,
      track: track.name,
      album: track.album,
      durationMs: track.durationMs > 0 ? Int64(track.durationMs) : nil,
      timestamp: clock())
    let api = self.api
    Task {
      do {
        try await api.updateNowPlaying(entry, session: session)
      } catch {
        scrobbleLog.notice("now playing not sent: \(String(describing: error), privacy: .public)")
      }
    }
  }

  private func enqueue(_ candidate: ScrobbleTracker.Candidate) {
    guard isActive else { return }
    do {
      let added = try queue.enqueue(
        playId: candidate.playId,
        artist: candidate.track.artist,
        track: candidate.track.name,
        album: candidate.track.album,
        durationMs: candidate.track.durationMs > 0 ? Int64(candidate.track.durationMs) : nil,
        now: clock())
      if added {
        scrobbleLog.notice("queued scrobble for play \(candidate.playId)")
      }
    } catch {
      scrobbleLog.error("enqueue failed: \(String(describing: error), privacy: .public)")
    }
    refreshStatus()
    flushSoon()
  }

  // MARK: - Loved tracks

  /// Mirrors a like or unlike made in Dial to Last.fm's Loved tracks.
  /// Calls go one at a time so a quick like-then-unlike lands in order.
  func setLoved(_ loved: Bool, artist: String, track: String) {
    guard isActive, let session,
          !artist.isEmpty, !track.isEmpty else { return }
    let api = self.api
    let previous = loveTask
    loveTask = Task {
      await previous?.value
      do {
        try await api.setLoved(loved, artist: artist, track: track, session: session)
        scrobbleLog.notice("\(loved ? "loved" : "unloved", privacy: .public) on Last.fm")
      } catch {
        scrobbleLog.notice("love not sent: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// Waits for queued love/unlove calls. For tests.
  func lovesSent() async {
    await loveTask?.value
  }

  // MARK: - Sending

  /// Starts a flush unless one is running. Used after queueing, at launch,
  /// and when the network comes back.
  func flushSoon() {
    guard autoFlush, isActive, flushTask == nil else { return }
    flushTask = Task { [weak self] in
      await self?.flush()
      self?.flushTask = nil
      self?.scheduleRetryIfNeeded()
    }
  }

  /// Sends every due row, 50 at a time, until the queue is empty or a
  /// batch fails.
  func flush() async {
    while isActive, let session {
      let now = clock()
      _ = try? queue.expire(olderThan: now - Self.maxAgeSeconds)
      guard let batch = try? queue.due(now: now, limit: Self.batchSize), !batch.isEmpty else { break }

      do {
        let results = try await api.scrobble(batch.map(\.entry), session: session)
        try record(results, for: batch, now: clock())
        problem = nil
      } catch let LastFMError.api(code, message) where code == LastFMErrorCode.invalidSessionKey {
        scrobbleLog.error("session rejected: \(message, privacy: .public)")
        dropSession()
        connection = .needsReconnect
        problem = "Last.fm signed Dial out. Connect again to keep scrobbling."
        break
      } catch {
        let attempts = batch.map(\.attempts).max() ?? 0
        let retryAt = clock() + Self.retryDelay(afterAttempts: attempts)
        try? queue.markFailed(ids: batch.map(\.id), error: Self.describe(error), nextAttemptAt: retryAt)
        problem = Self.plainProblem(error)
        scrobbleLog.notice("scrobble batch failed, retry in \(retryAt - self.clock())s: \(String(describing: error), privacy: .public)")
        break
      }
    }
    refreshStatus()
  }

  private func record(_ results: [LastFMScrobbleResult], for batch: [QueuedScrobble], now: Int64) throws {
    var sent: [Int64] = []
    var limited: [Int64] = []
    for (row, result) in zip(batch, results) {
      if result.accepted {
        sent.append(row.id)
      } else if result.ignoredCode == LastFMErrorCode.dailyScrobbleLimit {
        limited.append(row.id)
      } else {
        try queue.markIgnored(id: row.id, reason: "Last.fm ignored it (\(result.ignoredCode)): \(result.ignoredMessage)")
      }
    }
    try queue.markSent(ids: sent, now: now)
    if !limited.isEmpty {
      try queue.markFailed(ids: limited, error: "Daily scrobble limit", nextAttemptAt: now + 3_600)
    }
    scrobbleLog.notice("scrobbled \(sent.count) of \(batch.count)")
  }

  private func scheduleRetryIfNeeded() {
    retryTask?.cancel()
    retryTask = nil
    guard autoFlush, isActive,
          pendingCount > 0,
          let next = try? queue.nextAttemptAt() else { return }
    let delay = max(1, next - clock())
    let sleep = self.sleep
    retryTask = Task { [weak self] in
      try? await sleep(TimeInterval(delay))
      guard !Task.isCancelled else { return }
      self?.flushSoon()
    }
  }

  func refreshStatus() {
    pendingCount = (try? queue.pendingCount()) ?? 0
    lastScrobble = (try? queue.lastSent()) ?? nil
  }

  // MARK: - Connecting

  /// Desktop auth: get a token, send the user to last.fm to approve Dial,
  /// then poll until Last.fm hands back a session key.
  func connect(open: @escaping (URL) -> Void) {
    guard let credentials = credentials() else {
      problem = "Add your Last.fm API key and shared secret first."
      return
    }
    connectTask?.cancel()
    problem = nil
    connection = .waitingForApproval
    connectTask = Task { [weak self] in
      await self?.runConnect(credentials: credentials, open: open)
    }
  }

  func cancelConnect() {
    connectTask?.cancel()
    connectTask = nil
    if connection == .waitingForApproval {
      connection = sessionKey == nil ? .disconnected : .connected
    }
  }

  private func runConnect(credentials: LastFMCredentials, open: (URL) -> Void) async {
    do {
      let token = try await api.getToken(credentials: credentials)
      open(LastFMWebClient.authorizeURL(token: token, apiKey: credentials.apiKey))
      let deadline = clock() + Self.approvalTimeout
      while true {
        try await sleep(Self.approvalPollInterval)
        try Task.checkCancellation()
        do {
          let session = try await api.getSession(token: token, credentials: credentials)
          try Task.checkCancellation()
          didConnect(username: session.username, key: session.key)
          return
        } catch LastFMError.api(LastFMErrorCode.tokenNotAuthorized, _) {
          // Not approved yet.
          guard clock() < deadline else { throw LastFMError.api(LastFMErrorCode.tokenExpired, "timed out") }
        }
      }
    } catch is CancellationError {
      return
    } catch {
      guard connection == .waitingForApproval else { return }
      connection = sessionKey == nil ? .disconnected : .connected
      problem = Self.plainConnectProblem(error)
      scrobbleLog.error("connect failed: \(String(describing: error), privacy: .public)")
    }
    connectTask = nil
  }

  private func didConnect(username: String, key: String) {
    try? sessionKeyStore.save(key)
    defaults.set(username, forKey: Key.username)
    sessionKey = key
    self.username = username
    connection = .connected
    problem = nil
    connectTask = nil
    // Connecting is the opt-in; the toggle can turn it off afterwards.
    scrobblingEnabled = true
    scrobbleLog.notice("connected to Last.fm")
    flushSoon()
  }

  /// Forgets the session key. Queued plays stay and send after reconnecting
  /// (Last.fm still drops anything older than 14 days).
  func disconnect() {
    cancelConnect()
    dropSession()
    connection = .disconnected
    scrobblingEnabled = false
    problem = nil
  }

  private func dropSession() {
    try? sessionKeyStore.clear()
    defaults.removeObject(forKey: Key.username)
    sessionKey = nil
    username = nil
    flushTask?.cancel()
    retryTask?.cancel()
  }

  // MARK: - Copy

  private static func describe(_ error: Error) -> String {
    if case let LastFMError.api(code, message) = error { return "Last.fm \(code): \(message)" }
    if case let LastFMError.httpStatus(status) = error { return "HTTP \(status)" }
    return String(describing: error)
  }

  private static func plainProblem(_ error: Error) -> String {
    switch error {
    case let LastFMError.api(code, _)
      where code == LastFMErrorCode.invalidAPIKey
        || code == LastFMErrorCode.invalidSignature
        || code == LastFMErrorCode.suspendedAPIKey:
      return "Last.fm rejected the API key or shared secret. Plays are waiting."
    case is URLError:
      return "Offline. Plays will send when Last.fm is reachable."
    default:
      return "Last.fm didn't answer. Dial will try again."
    }
  }

  private static func plainConnectProblem(_ error: Error) -> String {
    switch error {
    case let LastFMError.api(code, _)
      where code == LastFMErrorCode.invalidAPIKey
        || code == LastFMErrorCode.invalidSignature
        || code == LastFMErrorCode.suspendedAPIKey:
      return "Last.fm rejected the API key or shared secret."
    case LastFMError.api(LastFMErrorCode.tokenExpired, _):
      return "Last.fm approval timed out. Try again."
    case is URLError:
      return "Couldn't reach Last.fm."
    default:
      return "Couldn't connect to Last.fm."
    }
  }

  enum Key {
    static let enabled = "settings.lastFMScrobblingEnabled"
    static let username = "settings.lastFMUsername"
  }
}
