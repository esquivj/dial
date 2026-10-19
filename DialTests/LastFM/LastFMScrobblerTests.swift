// DialTests/LastFM/LastFMScrobblerTests.swift
import XCTest
import GRDB
@testable import Dial

@MainActor
final class LastFMScrobblerTests: XCTestCase {
  private var now: Int64 = 1_779_100_000   // week of May 18, 2026

  // MARK: - Rule

  func test_rule_isStricterOfDialAndLastFM() {
    // 3-minute track: Dial counts at 30 s, Last.fm needs half (90 s).
    XCTAssertTrue(DedupRule.shouldCount(progressMs: 30_000, durationMs: 180_000))
    XCTAssertFalse(LastFMScrobbleRule.shouldScrobble(positionMs: 30_000, durationMs: 180_000))
    XCTAssertFalse(LastFMScrobbleRule.shouldScrobble(positionMs: 89_999, durationMs: 180_000))
    XCTAssertTrue(LastFMScrobbleRule.shouldScrobble(positionMs: 90_000, durationMs: 180_000))
    // 10-minute track: 4 minutes is enough.
    XCTAssertFalse(LastFMScrobbleRule.shouldScrobble(positionMs: 239_000, durationMs: 600_000))
    XCTAssertTrue(LastFMScrobbleRule.shouldScrobble(positionMs: 240_000, durationMs: 600_000))
    // Tracks of 30 s or less never scrobble, even played in full.
    XCTAssertTrue(DedupRule.shouldCount(progressMs: 30_000, durationMs: 30_000))
    XCTAssertFalse(LastFMScrobbleRule.shouldScrobble(positionMs: 30_000, durationMs: 30_000))
    // Unknown length: only 4 minutes counts.
    XCTAssertFalse(LastFMScrobbleRule.shouldScrobble(positionMs: 200_000, durationMs: 0))
    XCTAssertTrue(LastFMScrobbleRule.shouldScrobble(positionMs: 240_000, durationMs: 0))
  }

  // MARK: - Queue

  func test_countedLivePlay_queuesOnlyAtLastFMPoint() throws {
    let dbq = try InMemoryDatabase.make()
    let scrobbler = makeScrobbler(dbq: dbq, api: FakeLastFM())
    let track = Self.track("spotify:track:A", durationMs: 200_000)

    try play(track, on: scrobbler, dbq: dbq, upTo: 99_000)
    XCTAssertEqual(try ScrobbleQueueDAO(dbq: dbq).pendingCount(), 0, "counted by Dial, not yet by Last.fm")

    scrobbler.progress(ms: 100_000)
    scrobbler.progress(ms: 120_000)
    scrobbler.progress(ms: 199_000)

    XCTAssertEqual(try ScrobbleQueueDAO(dbq: dbq).pendingCount(), 1)
    XCTAssertEqual(scrobbler.pendingCount, 1)
    let row = try XCTUnwrap(ScrobbleQueueDAO(dbq: dbq).due(now: now, limit: 50).first)
    XCTAssertEqual(row.entry.artist, "Artist A")
    XCTAssertEqual(row.entry.track, "Song A")
    XCTAssertEqual(row.entry.album, "Album")
    XCTAssertEqual(row.entry.durationMs, 200_000)
    XCTAssertEqual(row.entry.timestamp, now - 30, "scrobble carries the play's start time")
  }

  func test_skippedTrack_isNeverQueued() throws {
    let dbq = try InMemoryDatabase.make()
    let scrobbler = makeScrobbler(dbq: dbq, api: FakeLastFM())
    let track = Self.track("spotify:track:A", durationMs: 200_000)

    try play(track, on: scrobbler, dbq: dbq, upTo: 60_000)
    scrobbler.trackStarted(Self.track("spotify:track:B", durationMs: 200_000))
    scrobbler.progress(ms: 150_000)  // B's position, not A's

    XCTAssertEqual(try ScrobbleQueueDAO(dbq: dbq).pendingCount(), 0)
  }

  func test_flush_sendsQueuedPlay_andRecordsLastScrobbled() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    try play(Self.track("spotify:track:A", durationMs: 200_000), on: scrobbler, dbq: dbq, upTo: 100_000)

    await scrobbler.flush()

    XCTAssertEqual(api.scrobbleBatches.map(\.count), [1])
    XCTAssertEqual(api.scrobbleBatches.first?.first?.track, "Song A")
    XCTAssertEqual(scrobbler.pendingCount, 0)
    XCTAssertEqual(scrobbler.lastScrobble, LastScrobble(artist: "Artist A", track: "Song A", sentAt: now))
  }

  func test_offlinePlays_stayQueued_andRetryWithBackoff() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    api.scrobbleFailures = [URLError(.notConnectedToInternet), URLError(.timedOut)]
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    try play(Self.track("spotify:track:A", durationMs: 200_000), on: scrobbler, dbq: dbq, upTo: 100_000)

    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 1)
    XCTAssertEqual(scrobbler.pendingCount, 1)
    XCTAssertNotNil(scrobbler.problem)

    // Held for a minute: flushing again right away sends nothing.
    now += 59
    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 1)

    now += 1
    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 2, "second try after 60 s")
    XCTAssertEqual(scrobbler.pendingCount, 1)

    // Second failure doubles the wait.
    now += 119
    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 2)
    now += 1
    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 3)
    XCTAssertEqual(scrobbler.pendingCount, 0)
    XCTAssertNil(scrobbler.problem)
  }

  func test_retryDelay_doublesUpToOneHour() {
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 0), 60)
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 1), 120)
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 2), 240)
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 5), 1_920)
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 6), 3_600)
    XCTAssertEqual(LastFMScrobbler.retryDelay(afterAttempts: 40), 3_600)
  }

  func test_backlog_sendsOldestFirstInBatchesOfFifty() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    let dao = ScrobbleQueueDAO(dbq: dbq)
    for i in 0..<120 {
      let id = try insertPlay(dbq: dbq, uri: "spotify:track:\(i)", at: now - 100_000 + Int64(i) * 300, source: "live")
      XCTAssertTrue(try dao.enqueue(playId: id, artist: "Artist", track: "Song \(i)", album: nil, durationMs: 200_000, now: now))
    }

    await scrobbler.flush()

    XCTAssertEqual(api.scrobbleBatches.map(\.count), [50, 50, 20])
    XCTAssertEqual(api.scrobbleBatches.first?.first?.track, "Song 0")
    XCTAssertEqual(api.scrobbleBatches.last?.last?.track, "Song 119")
    XCTAssertEqual(scrobbler.pendingCount, 0)
  }

  func test_ignoredScrobble_isNotRetried_dailyLimitIs() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    api.scrobbleResults = [[
      LastFMScrobbleResult(ignoredCode: 1, ignoredMessage: "Artist ignored"),
      LastFMScrobbleResult(ignoredCode: LastFMErrorCode.dailyScrobbleLimit, ignoredMessage: "Daily limit"),
      .acceptedResult
    ]]
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    let dao = ScrobbleQueueDAO(dbq: dbq)
    for i in 0..<3 {
      let id = try insertPlay(dbq: dbq, uri: "spotify:track:\(i)", at: now - 1_000 + Int64(i), source: "live")
      try dao.enqueue(playId: id, artist: "Artist", track: "Song \(i)", album: nil, durationMs: nil, now: now)
    }

    await scrobbler.flush()
    XCTAssertEqual(scrobbler.pendingCount, 1, "only the rate-limited one waits")

    now += 3_600
    await scrobbler.flush()
    XCTAssertEqual(api.scrobbleBatches.map { $0.map(\.track) }, [["Song 0", "Song 1", "Song 2"], ["Song 1"]])
    XCTAssertEqual(scrobbler.pendingCount, 0)
  }

  func test_playsOlderThanFourteenDays_areDropped() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    let id = try insertPlay(dbq: dbq, uri: "spotify:track:old", at: now - 15 * 86_400, source: "live")
    try ScrobbleQueueDAO(dbq: dbq).enqueue(playId: id, artist: "A", track: "Old", album: nil, durationMs: nil, now: now)

    await scrobbler.flush()

    XCTAssertTrue(api.scrobbleBatches.isEmpty)
    XCTAssertEqual(scrobbler.pendingCount, 0)
  }

  // MARK: - Relaunch

  func test_relaunch_neverScrobblesAPlayTwice() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let defaults = freshDefaults()
    let keys = InMemorySecrets("sk")
    let track = Self.track("spotify:track:A", durationMs: 200_000)

    // First run: queued, sent.
    let first = makeScrobbler(dbq: dbq, api: api, defaults: defaults, sessionKeys: keys)
    try play(track, on: first, dbq: dbq, upTo: 120_000)
    await first.flush()
    XCTAssertEqual(api.scrobbleBatches.count, 1)

    // Relaunch mid-track. PollingService doesn't re-count a track first
    // seen past the count point (PollingServiceTests
    // .test_firstObservationPastThresholdDoesNotEmitCountedPlay), but even
    // if the same play reached the scrobbler again, its play id is queued.
    let second = makeScrobbler(dbq: dbq, api: api, defaults: defaults, sessionKeys: keys)
    second.trackStarted(track)
    second.resumed()
    second.livePlayRecorded(uri: track.uri, playedAt: now - 30, msPlayed: 30_000)
    second.progress(ms: 150_000)
    await second.flush()

    XCTAssertEqual(api.scrobbleBatches.count, 1)
    XCTAssertEqual(try queueRowCount(dbq), 1)
  }

  func test_playQueuedBeforeQuit_sendsOnceAfterRelaunch() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    api.scrobbleFailures = [URLError(.notConnectedToInternet)]
    let defaults = freshDefaults()
    let keys = InMemorySecrets("sk")

    let first = makeScrobbler(dbq: dbq, api: api, defaults: defaults, sessionKeys: keys)
    try play(Self.track("spotify:track:A", durationMs: 200_000), on: first, dbq: dbq, upTo: 120_000)
    await first.flush()
    XCTAssertEqual(first.pendingCount, 1)

    now += 3_600
    let second = makeScrobbler(dbq: dbq, api: api, defaults: defaults, sessionKeys: keys)
    XCTAssertEqual(second.pendingCount, 1, "queue survived the relaunch")
    await second.flush()
    let third = makeScrobbler(dbq: dbq, api: api, defaults: defaults, sessionKeys: keys)
    await third.flush()

    XCTAssertEqual(api.scrobbleBatches.count, 2, "one failed try, one successful send")
    XCTAssertEqual(third.pendingCount, 0)
  }

  // MARK: - Imports and recently-played rows

  func test_importedAndRecentlyPlayedRows_areNeverScrobbled() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    let engine = PetEngine(dbq: dbq)
    let importer = Importer(dbq: dbq, engine: engine)
    XCTAssertEqual(try importer.importBatch([
      .init(playedAt: now - 5_000, msPlayed: 200_000, trackUri: "spotify:track:A",
            trackName: "Song A", artistName: "Artist A", albumName: "Album")
    ], sourcePath: "dummy"), 1)
    XCTAssertTrue(try engine.recordPlay(.init(
      playedAt: now - 2_000, trackUri: "spotify:track:B", msPlayed: 200_000, source: RecentPlaysReconciler.source)))

    let dao = ScrobbleQueueDAO(dbq: dbq)
    let ids = try playIds(dbq)
    XCTAssertEqual(ids.count, 2)
    for id in ids {
      XCTAssertFalse(try dao.enqueue(playId: id, artist: "A", track: "T", album: nil, durationMs: nil, now: now))
    }

    // Even with the track on screen, a non-live row isn't picked up.
    scrobbler.trackStarted(Self.track("spotify:track:A", durationMs: 200_000))
    scrobbler.resumed()
    scrobbler.livePlayRecorded(uri: "spotify:track:A", playedAt: now - 5_000, msPlayed: 200_000)
    scrobbler.progress(ms: 190_000)
    await scrobbler.flush()

    XCTAssertTrue(api.scrobbleBatches.isEmpty)
    XCTAssertEqual(try queueRowCount(dbq), 0)
  }

  // MARK: - Switches

  func test_scrobblingOff_queuesNothing() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)
    scrobbler.scrobblingEnabled = false

    try play(Self.track("spotify:track:A", durationMs: 200_000), on: scrobbler, dbq: dbq, upTo: 150_000)
    await scrobbler.flush()

    XCTAssertEqual(scrobbler.pendingCount, 0)
    XCTAssertTrue(api.scrobbleBatches.isEmpty)
    XCTAssertTrue(api.nowPlaying.isEmpty)
  }

  func test_notConnected_isOffByDefault() throws {
    let dbq = try InMemoryDatabase.make()
    let scrobbler = LastFMScrobbler(
      dbq: dbq,
      api: FakeLastFM(),
      credentials: { Self.credentials },
      sessionKeyStore: InMemorySecrets(nil),
      defaults: freshDefaults(),
      clock: { [unowned self] in self.now },
      autoFlush: false)

    XCTAssertEqual(scrobbler.connection, .disconnected)
    XCTAssertFalse(scrobbler.scrobblingEnabled)
    XCTAssertFalse(scrobbler.isActive)
  }

  func test_rejectedSession_stopsAndAsksToReconnect() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    api.scrobbleFailures = [LastFMError.api(LastFMErrorCode.invalidSessionKey, "Invalid session key")]
    let keys = InMemorySecrets("sk")
    let scrobbler = makeScrobbler(dbq: dbq, api: api, sessionKeys: keys)
    try play(Self.track("spotify:track:A", durationMs: 200_000), on: scrobbler, dbq: dbq, upTo: 120_000)

    await scrobbler.flush()

    XCTAssertEqual(scrobbler.connection, .needsReconnect)
    XCTAssertFalse(scrobbler.isActive)
    XCTAssertNil(try keys.load())
    XCTAssertEqual(scrobbler.pendingCount, 1, "the play waits for a reconnect")
  }

  // MARK: - Now playing and Loved

  func test_nowPlaying_sentOncePerTrackWhilePlaying() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)

    scrobbler.trackStarted(Self.track("spotify:track:A", durationMs: 200_000))
    scrobbler.paused()
    await settle()
    XCTAssertTrue(api.nowPlaying.isEmpty, "paused on launch: nothing to announce")

    scrobbler.resumed()
    scrobbler.paused()
    scrobbler.resumed()
    scrobbler.trackStarted(Self.track("spotify:track:A", durationMs: 200_000))
    scrobbler.trackStarted(Self.track("spotify:track:B", durationMs: 200_000))
    await settle()

    XCTAssertEqual(api.nowPlaying.map(\.track), ["Song A", "Song B"])
  }

  func test_like_marksLoved_unlikeUnmarks() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    let scrobbler = makeScrobbler(dbq: dbq, api: api)

    scrobbler.setLoved(true, artist: "Artist A", track: "Song A")
    scrobbler.setLoved(false, artist: "Artist A", track: "Song A")
    await scrobbler.lovesSent()

    XCTAssertEqual(api.loves.count, 2)
    XCTAssertEqual(api.loves.first?.loved, true)
    XCTAssertEqual(api.loves.last?.loved, false)
  }

  // MARK: - Connecting

  func test_connect_waitsForApproval_thenStoresSession() async throws {
    let dbq = try InMemoryDatabase.make()
    let api = FakeLastFM()
    api.sessionFailuresBeforeApproval = 2
    let keys = InMemorySecrets(nil)
    let defaults = freshDefaults()
    let scrobbler = LastFMScrobbler(
      dbq: dbq,
      api: api,
      credentials: { Self.credentials },
      sessionKeyStore: keys,
      defaults: defaults,
      clock: { [unowned self] in self.now },
      sleep: { _ in await Task.yield() },
      autoFlush: false)
    var opened: [URL] = []

    scrobbler.connect { opened.append($0) }
    XCTAssertEqual(scrobbler.connection, .waitingForApproval)
    for _ in 0..<200 where scrobbler.connection != .connected { await Task.yield() }

    XCTAssertEqual(scrobbler.connection, .connected)
    XCTAssertEqual(scrobbler.username, "listener")
    XCTAssertEqual(try keys.load(), "session-key")
    XCTAssertTrue(scrobbler.scrobblingEnabled, "connecting turns scrobbling on")
    XCTAssertEqual(api.sessionCalls, 3)
    XCTAssertEqual(opened.first?.absoluteString, "https://www.last.fm/api/auth/?api_key=key&token=token")

    scrobbler.disconnect()
    XCTAssertEqual(scrobbler.connection, .disconnected)
    XCTAssertFalse(scrobbler.scrobblingEnabled)
    XCTAssertNil(try keys.load())
  }

  // MARK: - Web client

  func test_signature_sortsParamsAndAppendsSecret() {
    let sig = LastFMSignature.sign([
      "method": "track.scrobble",
      "track[0]": "Jóga",
      "artist[0]": "Björk",
      "timestamp[0]": "1700000000",
      "api_key": "xx",
      "sk": "SK",
      "format": "json"
    ], secret: "secret")
    XCTAssertEqual(sig, "49daadb372208501df3cd2007bb41eb6")
  }

  func test_webClient_postsSignedBatch_andDecodesSingleResult() async throws {
    var body = ""
    StubURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "POST")
      body = Self.readBody(req)
      let json = #"""
        {"scrobbles":{"scrobble":{"artist":{"#text":"Björk"},"track":{"#text":"Jóga"},
         "ignoredMessage":{"code":"0","#text":""}},"@attr":{"accepted":1,"ignored":0}}}
      """#
      return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!, Data(json.utf8))
    }
    let client = LastFMWebClient(session: StubURLProtocol.session())
    let session = LastFMSession(credentials: LastFMCredentials(apiKey: "xx", sharedSecret: "secret"), key: "SK")

    let results = try await client.scrobble(
      [LastFMScrobbleEntry(artist: "Björk", track: "Jóga", album: nil, durationMs: nil, timestamp: 1_700_000_000)],
      session: session)

    XCTAssertEqual(results, [.acceptedResult])
    let params = Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair -> (String, String) in
      let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
      return (parts[0], parts.count > 1 ? parts[1] : "")
    })
    XCTAssertEqual(params["method"], "track.scrobble")
    XCTAssertEqual(params["artist[0]"], "Björk")
    XCTAssertEqual(params["track[0]"], "Jóga")
    XCTAssertEqual(params["format"], "json")
    XCTAssertEqual(params["api_sig"], "49daadb372208501df3cd2007bb41eb6")
  }

  func test_webClient_surfacesLastFMErrorBody() async throws {
    StubURLProtocol.handler = { req in
      let json = #"{"error":9,"message":"Invalid session key - Please re-authenticate"}"#
      return (HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: [:])!, Data(json.utf8))
    }
    let client = LastFMWebClient(session: StubURLProtocol.session())
    let session = LastFMSession(credentials: Self.credentials, key: "SK")

    do {
      try await client.setLoved(true, artist: "A", track: "T", session: session)
      XCTFail("expected an error")
    } catch let LastFMError.api(code, _) {
      XCTAssertEqual(code, LastFMErrorCode.invalidSessionKey)
    }
  }

  // MARK: - Helpers

  private static let credentials = LastFMCredentials(apiKey: "key", sharedSecret: "secret")

  private static func track(_ uri: String, durationMs: Int) -> ScrobbleTracker.Track {
    let letter = uri.split(separator: ":").last.map(String.init) ?? "?"
    return ScrobbleTracker.Track(
      uri: uri, artist: "Artist \(letter)", name: "Song \(letter)", album: "Album", durationMs: durationMs)
  }

  private func makeScrobbler(
    dbq: DatabaseQueue,
    api: FakeLastFM,
    defaults: UserDefaults? = nil,
    sessionKeys: InMemorySecrets = InMemorySecrets("sk")
  ) -> LastFMScrobbler {
    let defaults = defaults ?? freshDefaults()
    if defaults.object(forKey: LastFMScrobbler.Key.enabled) == nil {
      defaults.set(true, forKey: LastFMScrobbler.Key.enabled)
    }
    return LastFMScrobbler(
      dbq: dbq,
      api: api,
      credentials: { Self.credentials },
      sessionKeyStore: sessionKeys,
      defaults: defaults,
      clock: { [unowned self] in self.now },
      autoFlush: false)
  }

  /// Plays `track` the way the coordinator reports it: started, playing,
  /// counted by Dial at 30 s (recorded by PetEngine), then moving to `upTo`.
  private func play(_ track: ScrobbleTracker.Track, on scrobbler: LastFMScrobbler, dbq: DatabaseQueue, upTo positionMs: Int) throws {
    scrobbler.trackStarted(track)
    scrobbler.resumed()
    scrobbler.progress(ms: 30_000)
    let startedAt = now - 30
    XCTAssertTrue(try PetEngine(dbq: dbq).recordPlay(
      .init(playedAt: startedAt, trackUri: track.uri, msPlayed: 30_000, source: "live")))
    scrobbler.livePlayRecorded(uri: track.uri, playedAt: startedAt, msPlayed: 30_000)
    scrobbler.progress(ms: positionMs)
  }

  private func insertPlay(dbq: DatabaseQueue, uri: String, at: Int64, source: String) throws -> Int64 {
    var row = Play(id: nil, playedAt: at, trackUri: uri, msPlayed: 200_000, source: source)
    try dbq.write { try row.insert($0) }
    return try XCTUnwrap(row.id)
  }

  private func queueRowCount(_ dbq: DatabaseQueue) throws -> Int {
    try dbq.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM lastfm_scrobbles") ?? 0 }
  }

  private func playIds(_ dbq: DatabaseQueue) throws -> [Int64] {
    try dbq.read { try Int64.fetchAll($0, sql: "SELECT id FROM plays") }
  }

  private func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }

  private func freshDefaults() -> UserDefaults {
    let suiteName = "Dial.LastFMScrobblerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private static func readBody(_ request: URLRequest) -> String {
    if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return String(decoding: data, as: UTF8.self)
  }
}

// MARK: - Fakes

private final class FakeLastFM: LastFMScrobbleAPI {
  var scrobbleBatches: [[LastFMScrobbleEntry]] = []
  var scrobbleFailures: [Error] = []
  var scrobbleResults: [[LastFMScrobbleResult]] = []
  var nowPlaying: [LastFMScrobbleEntry] = []
  var loves: [(loved: Bool, artist: String, track: String)] = []
  var sessionFailuresBeforeApproval = 0
  var sessionCalls = 0

  func getToken(credentials: LastFMCredentials) async throws -> String { "token" }

  func getSession(token: String, credentials: LastFMCredentials) async throws -> (username: String, key: String) {
    sessionCalls += 1
    if sessionCalls <= sessionFailuresBeforeApproval {
      throw LastFMError.api(LastFMErrorCode.tokenNotAuthorized, "Unauthorized Token")
    }
    return ("listener", "session-key")
  }

  func updateNowPlaying(_ entry: LastFMScrobbleEntry, session: LastFMSession) async throws {
    nowPlaying.append(entry)
  }

  func scrobble(_ entries: [LastFMScrobbleEntry], session: LastFMSession) async throws -> [LastFMScrobbleResult] {
    XCTAssertLessThanOrEqual(entries.count, 50)
    scrobbleBatches.append(entries)
    if !scrobbleFailures.isEmpty { throw scrobbleFailures.removeFirst() }
    if !scrobbleResults.isEmpty { return scrobbleResults.removeFirst() }
    return entries.map { _ in .acceptedResult }
  }

  func setLoved(_ loved: Bool, artist: String, track: String, session: LastFMSession) async throws {
    loves.append((loved, artist, track))
  }
}

private final class InMemorySecrets: SecretStringStore {
  private var value: String?
  init(_ value: String?) { self.value = value }
  func save(_ value: String) throws { self.value = value }
  func load() throws -> String? { value }
  func clear() throws { value = nil }
}
