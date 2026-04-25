// DialTests/Auth/TokenStoreTests.swift
import XCTest
@testable import Dial

final class TokenStoreTests: XCTestCase {
  func test_saveAndLoad_roundTrip() throws {
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "a", refreshToken: "r", expiresAt: 123))
    let t = try store.load()
    XCTAssertEqual(t?.accessToken, "a")
    XCTAssertEqual(t?.refreshToken, "r")
    XCTAssertEqual(t?.expiresAt, 123)
  }
  func test_clear_removes() throws {
    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "a", refreshToken: "r", expiresAt: 1))
    try store.clear()
    XCTAssertNil(try store.load())
  }
}

final class InMemoryTokenStore: TokenStore {
  private var token: SpotifyToken?
  func save(_ t: SpotifyToken) throws { token = t }
  func load() throws -> SpotifyToken? { token }
  func clear() throws { token = nil }
}
