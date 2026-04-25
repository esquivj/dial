// Dial/Auth/FileTokenStore.swift
import Foundation

/// Plain-file token storage used in DEBUG builds. Each Xcode rebuild re-signs
/// the binary with a new ad-hoc cert; macOS keychain treats each new signature
/// as an untrusted requester and prompts on every launch. The keychain prompt
/// loop makes dev miserable — we trade it for a 0o600 JSON file.
///
/// The file lives at `~/Library/Application Support/Dial/spotify-token.json`,
/// which is readable only by the owning user account. For a personal Mac app
/// shipped only to yourself, this is functionally equivalent security-wise.
///
/// `KeychainTokenStore` remains the right choice for Release / distributed
/// builds where the binary signature is stable.
final class FileTokenStore: TokenStore {
  private let url: URL

  init() {
    let base = (try? FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
      .appendingPathComponent("Dial", isDirectory: true)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dial", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = base.appendingPathComponent("spotify-token.json")
  }

  func save(_ token: SpotifyToken) throws {
    let data = try JSONEncoder().encode(token)
    try data.write(to: url, options: [.atomic])
    // Owner-only permissions; matches keychain's "available to this user only" intent.
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path)
  }

  func load() throws -> SpotifyToken? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(SpotifyToken.self, from: data)
  }

  func clear() throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
