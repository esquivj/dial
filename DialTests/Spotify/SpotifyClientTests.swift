// DialTests/Spotify/SpotifyClientTests.swift
import XCTest
@testable import Dial

final class SpotifyClientTests: XCTestCase {
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: "spotify.rateLimit.cooldownUntil")
    UserDefaults.standard.removeObject(forKey: "spotify.rateLimit.lastHitAt")
  }

  func test_currentlyPlaying_decodes() async throws {
    let json = #"""
      {"is_playing":true,"progress_ms":12345,
       "item":{"uri":"spotify:track:A","name":"T","duration_ms":200000,
               "artists":[{"name":"X","uri":"spotify:artist:X"}],
               "album":{"name":"Al","images":[{"url":"http://a"}]}}}
    """#
    StubURLProtocol.handler = { req in
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, json.data(using: .utf8)!)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "valid", refreshToken: "r",
                         expiresAt: Int64(Date().timeIntervalSince1970) + 3600))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })
    let cp = try await client.currentlyPlaying()
    XCTAssertEqual(cp?.item?.uri, "spotify:track:A")
    XCTAssertEqual(cp?.is_playing, true)
  }

  func test_on401_triggersRefreshThenRetries() async throws {
    var callCount = 0
    StubURLProtocol.handler = { req in
      callCount += 1
      let status = callCount == 1 ? 401 : 200
      let body = status == 200 ? #"{"is_playing":false,"progress_ms":0,"item":null}"# : "{}"
      let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
      return (r, body.data(using: .utf8)!)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "expired", refreshToken: "r", expiresAt: 1))
    var refreshed = false
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: {
      refreshed = true
      let t = SpotifyToken(accessToken: "fresh", refreshToken: "r", expiresAt: Int64.max)
      try store.save(t)
      return t
    })
    _ = try await client.currentlyPlaying()
    XCTAssertTrue(refreshed)
    XCTAssertEqual(callCount, 2)
  }

  func test_tracksBatch_returnsDecoded() async throws {
    let json = #"""
      {"tracks":[
        {"uri":"spotify:track:A","name":"T1","duration_ms":200000,
          "artists":[{"name":"X","uri":"spotify:artist:X"}],
          "album":{"name":"Al","images":[{"url":"http://a"}]}}
      ]}
    """#
    StubURLProtocol.handler = { req in
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, json.data(using: .utf8)!)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })
    let tracks = try await client.tracks(uris: ["spotify:track:A"])
    XCTAssertEqual(tracks.first?.uri, "spotify:track:A")
  }

  func test_artist_allowsMissingDeprecatedGenres() async throws {
    let json = #"""
      {"uri":"spotify:artist:A","name":"Artist","images":[{"url":"http://artist"}]}
    """#
    StubURLProtocol.handler = { req in
      XCTAssertEqual(req.url?.path, "/v1/artists/A")
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, json.data(using: .utf8)!)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })

    let artist = try await client.artist(uri: "spotify:artist:A")

    XCTAssertEqual(artist.uri, "spotify:artist:A")
    XCTAssertEqual(artist.genres, [])
    XCTAssertEqual(artist.images.first?.url, "http://artist")
  }

  func test_lastFMArtistTopTags_decodesFlexibleCounts() async throws {
    let json = #"""
      {"toptags":{"tag":[
        {"name":"corridos tumbados","count":"100","url":"https://last.fm/tag/corridos+tumbados"},
        {"name":"latin","count":42,"url":"https://last.fm/tag/latin"}
      ]}}
    """#
    StubURLProtocol.handler = { req in
      let comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
      XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "method" })?.value, "artist.getTopTags")
      XCTAssertEqual(comps?.queryItems?.first(where: { $0.name == "artist" })?.value, "Junior H")
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, json.data(using: .utf8)!)
    }

    let tags = try await LastFMClient(apiKey: "key", session: StubURLProtocol.session())
      .artistTopTags(name: "Junior H")

    XCTAssertEqual(tags.map(\.name), ["corridos tumbados", "latin"])
    XCTAssertEqual(tags.first?.count, 100)
  }

  func test_libraryContains_usesCurrentLibraryEndpoint() async throws {
    StubURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "GET")
      XCTAssertEqual(req.url?.path, "/v1/me/library/contains")
      XCTAssertEqual(URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == "uris" })?
        .value, "spotify:track:A")
      XCTAssertTrue(req.url!.absoluteString.contains("uris=spotify%3Atrack%3AA"))
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, #"[true]"#.data(using: .utf8)!)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })

    let contains = try await client.libraryContains(uri: "spotify:track:A")
    XCTAssertTrue(contains)
  }

  func test_saveAndRemoveLibrary_useCurrentLibraryEndpoint() async throws {
    var calls: [(method: String?, path: String, uri: String?, rawURL: String)] = []
    StubURLProtocol.handler = { req in
      calls.append((
        method: req.httpMethod,
        path: req.url!.path,
        uri: URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
          .queryItems?
          .first(where: { $0.name == "uris" })?
          .value,
        rawURL: req.url!.absoluteString))
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, Data())
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })

    try await client.saveToLibrary(uri: "spotify:track:A")
    try await client.removeFromLibrary(uri: "spotify:track:A")

    XCTAssertEqual(calls.map(\.method), ["PUT", "DELETE"])
    XCTAssertEqual(calls.map(\.path), ["/v1/me/library", "/v1/me/library"])
    XCTAssertEqual(calls.map(\.uri), ["spotify:track:A", "spotify:track:A"])
    XCTAssertTrue(calls.allSatisfy { $0.rawURL.contains("uris=spotify%3Atrack%3AA") })
  }

  func test_play_usesPreferredDeviceAndSendsExplicitEmptyBody() async throws {
    var calls: [(method: String?, path: String, deviceID: String?, contentLength: String?)] = []
    StubURLProtocol.handler = { req in
      calls.append((
        method: req.httpMethod,
        path: req.url!.path,
        deviceID: URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?
          .queryItems?
          .first(where: { $0.name == "device_id" })?
          .value,
        contentLength: req.value(forHTTPHeaderField: "Content-Length")))

      let status = req.url!.path == "/v1/me/player/devices" ? 200 : 204
      let body = req.url!.path == "/v1/me/player/devices"
        ? #"{"devices":[{"id":"desktop-device","is_active":true,"is_restricted":false}]}"#.data(using: .utf8)!
        : Data()
      let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
      return (r, body)
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })

    try await client.play()

    XCTAssertEqual(calls.map(\.method), ["GET", "PUT"])
    XCTAssertEqual(calls.map(\.path), ["/v1/me/player/devices", "/v1/me/player/play"])
    XCTAssertEqual(calls.last?.deviceID, "desktop-device")
    XCTAssertEqual(calls.last?.contentLength, "0")
  }

  func test_play_fallsBackToImplicitDeviceWhenDeviceLookupFails() async throws {
    var calls: [(method: String?, path: String)] = []
    StubURLProtocol.handler = { req in
      calls.append((method: req.httpMethod, path: req.url!.path))
      let status = req.url!.path == "/v1/me/player/devices" ? 500 : 204
      let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
      return (r, Data())
    }
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(session: StubURLProtocol.session(),
                               tokenStore: store,
                               refresh: { try store.load()! })

    try await client.play()

    XCTAssertEqual(calls.map(\.method), ["GET", "PUT"])
    XCTAssertEqual(calls.map(\.path), ["/v1/me/player/devices", "/v1/me/player/play"])
  }

  func test_transportControlsBypassBackgroundRateLimitCooldown() async throws {
    var calls: [(method: String?, path: String)] = []
    StubURLProtocol.handler = { req in
      calls.append((method: req.httpMethod, path: req.url!.path))
      let status = req.url!.path == "/v1/me/player/devices" ? 200 : 204
      let body = req.url!.path == "/v1/me/player/devices"
        ? #"{"devices":[{"id":"desktop-device","is_active":true,"is_restricted":false}]}"#.data(using: .utf8)!
        : Data()
      let r = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
      return (r, body)
    }
    let suiteName = "Dial.SpotifyClientTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let gate = SpotifyRateLimitGate(defaults: defaults)
    await gate.recordRateLimit(retryAfter: 3_600)

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(
      session: StubURLProtocol.session(),
      tokenStore: store,
      rateLimitGate: gate,
      refresh: { try store.load()! })

    try await withTimeout(seconds: 0.3) {
      try await client.play()
      try await client.next()
    }

    XCTAssertEqual(calls.map(\.method), ["GET", "PUT", "POST"])
    XCTAssertEqual(calls.map(\.path), [
      "/v1/me/player/devices",
      "/v1/me/player/play",
      "/v1/me/player/next",
    ])
  }

  func test_currentlyPlayingBypassesBackgroundRateLimitCooldown() async throws {
    var calls: [String] = []
    let json = #"""
      {"is_playing":true,"progress_ms":1200,
       "item":{"uri":"spotify:track:A","name":"T","duration_ms":200000,
               "artists":[{"name":"X","uri":"spotify:artist:X"}],
               "album":{"name":"Al","images":[{"url":"http://art"}]}}}
    """#
    StubURLProtocol.handler = { req in
      calls.append(req.url!.path)
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, json.data(using: .utf8)!)
    }
    let suiteName = "Dial.SpotifyClientTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let gate = SpotifyRateLimitGate(defaults: defaults)
    await gate.recordRateLimit(retryAfter: 3_600)

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(
      session: StubURLProtocol.session(),
      tokenStore: store,
      rateLimitGate: gate,
      refresh: { try store.load()! })

    let cp = try await withTimeout(seconds: 0.3) {
      try await client.currentlyPlaying()
    }

    XCTAssertEqual(calls, ["/v1/me/player"])
    XCTAssertEqual(cp?.item?.album.images.first?.url, "http://art")
  }

  func test_foregroundSpotifyCallsBypassBackgroundRateLimitCooldown() async throws {
    var calls: [(method: String?, path: String)] = []
    StubURLProtocol.handler = { req in
      calls.append((method: req.httpMethod, path: req.url!.path))
      let body: Data
      switch req.url!.path {
      case "/v1/audio-features/A":
        body = #"{"tempo":122.5}"#.data(using: .utf8)!
      case "/v1/me/library/contains":
        body = #"[true]"#.data(using: .utf8)!
      default:
        body = Data()
      }
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, body)
    }
    let suiteName = "Dial.SpotifyClientTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let gate = SpotifyRateLimitGate(defaults: defaults)
    await gate.recordRateLimit(retryAfter: 3_600)

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(
      session: StubURLProtocol.session(),
      tokenStore: store,
      rateLimitGate: gate,
      refresh: { try store.load()! })

    try await withTimeout(seconds: 0.3) {
      _ = try await client.audioFeatures(trackId: "A")
      _ = try await client.libraryContains(uri: "spotify:track:A")
      try await client.saveToLibrary(uri: "spotify:track:A")
      try await client.removeFromLibrary(uri: "spotify:track:A")
    }

    XCTAssertEqual(calls.map(\.method), ["GET", "GET", "PUT", "DELETE"])
    XCTAssertEqual(calls.map(\.path), [
      "/v1/audio-features/A",
      "/v1/me/library/contains",
      "/v1/me/library",
      "/v1/me/library",
    ])
  }

  func test_backgroundCatalogCallsCanOptIntoCooldownWaiting() async throws {
    var calls: [String] = []
    StubURLProtocol.handler = { req in
      calls.append(req.url!.path)
      let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
      return (r, #"{"uri":"spotify:artist:A","name":"Artist","genres":[],"images":[]}"#.data(using: .utf8)!)
    }
    let suiteName = "Dial.SpotifyClientTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let gate = SpotifyRateLimitGate(defaults: defaults)
    await gate.recordRateLimit(retryAfter: 3_600)

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "v", refreshToken: "r", expiresAt: Int64.max))
    let client = SpotifyClient(
      session: StubURLProtocol.session(),
      tokenStore: store,
      rateLimitGate: gate,
      refresh: { try store.load()! })

    do {
      _ = try await withTimeout(seconds: 0.05) {
        try await client.artist(uri: "spotify:artist:A", respectRateLimitGate: true)
      }
      XCTFail("Background catalog call should wait for the cooldown")
    } catch is TimeoutError {
      XCTAssertTrue(calls.isEmpty)
    }
  }

  private func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimeoutError()
      }
      let value = try await group.next()!
      group.cancelAll()
      return value
    }
  }

  private struct TimeoutError: Error {}
}
