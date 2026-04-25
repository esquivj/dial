// Dial/Auth/TokenStore.swift
import Foundation
import KeychainAccess

struct SpotifyToken: Codable, Equatable, Sendable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Int64   // unix seconds
}

protocol TokenStore {
  func save(_ token: SpotifyToken) throws
  func load() throws -> SpotifyToken?
  func clear() throws
}

final class KeychainTokenStore: TokenStore {
  private let keychain = Keychain(service: "com.dial.spotify").accessibility(.afterFirstUnlockThisDeviceOnly)
  private let key = "spotify-token"
  func save(_ token: SpotifyToken) throws {
    let data = try JSONEncoder().encode(token)
    try keychain.set(data, key: key)
  }
  func load() throws -> SpotifyToken? {
    guard let data = try keychain.getData(key) else { return nil }
    return try JSONDecoder().decode(SpotifyToken.self, from: data)
  }
  func clear() throws { try keychain.remove(key) }
}
