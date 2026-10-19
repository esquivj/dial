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

protocol SecretStringStore {
  func save(_ value: String) throws
  func load() throws -> String?
  func clear() throws
}

final class KeychainSecretStringStore: SecretStringStore {
  private let keychain: Keychain
  private let key: String

  init(service: String, key: String) {
    self.keychain = Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
    self.key = key
  }

  func save(_ value: String) throws {
    try keychain.set(value, key: key)
  }

  func load() throws -> String? {
    try keychain.get(key)
  }

  func clear() throws {
    try keychain.remove(key)
  }
}

enum LastFMAPIKeyStorage {
  static let legacyDefaultsKey = "settings.lastFMAPIKey"

  static func makeDefaultStore() -> SecretStringStore {
    LastFMSecretStorage.makeStore(filename: "lastfm-api-key", keychainKey: "api-key")
  }

  static func load(
    store: SecretStringStore = makeDefaultStore(),
    defaults: UserDefaults = .standard
  ) -> String {
    if let stored = (try? store.load()) ?? nil, !stored.isEmpty {
      defaults.removeObject(forKey: legacyDefaultsKey)
      return stored
    }

    let legacy = defaults.string(forKey: legacyDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !legacy.isEmpty else {
      defaults.removeObject(forKey: legacyDefaultsKey)
      return ""
    }

    try? store.save(legacy)
    defaults.removeObject(forKey: legacyDefaultsKey)
    return legacy
  }

  static func save(
    _ value: String,
    store: SecretStringStore = makeDefaultStore(),
    defaults: UserDefaults = .standard
  ) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      try? store.clear()
    } else {
      try? store.save(trimmed)
    }
    defaults.removeObject(forKey: legacyDefaultsKey)
  }
}

/// Where Last.fm secrets live: the shared secret (signs auth and scrobble
/// calls) and the session key (one per connected user).
enum LastFMSecretStorage {
  static func makeStore(filename: String, keychainKey: String) -> SecretStringStore {
    let keychain = KeychainSecretStringStore(service: "com.dial.lastfm", key: keychainKey)
    // DEBUG builds (what scripts/install.sh ships) use a file so rebuilds don't
    // re-trigger the keychain prompt; see FileSecretStringStore.
    #if DEBUG
    return FileSecretStringStore(filename: filename, fallback: keychain)
    #else
    return keychain
    #endif
  }

  static func makeSharedSecretStore() -> SecretStringStore {
    makeStore(filename: "lastfm-shared-secret", keychainKey: "shared-secret")
  }

  static func makeSessionKeyStore() -> SecretStringStore {
    makeStore(filename: "lastfm-session-key", keychainKey: "session-key")
  }
}
