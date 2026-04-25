// DialTests/Spotify/SpotifyClientTests.swift
import XCTest
@testable import Dial

final class SpotifyClientTests: XCTestCase {
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
}
