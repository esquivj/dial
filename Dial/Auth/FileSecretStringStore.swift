// Dial/Auth/FileSecretStringStore.swift
import Foundation

/// Owner-only (0o600) file storage for a single secret string, used in DEBUG
/// builds for the same reason as `FileTokenStore`: keychain items created by an
/// app without an Apple team ID are tied to that exact binary, so every rebuild
/// triggers a keychain password prompt on the next read.
///
/// `fallback` is read once, only while the file has never been written, so a
/// secret saved to the keychain by an older build moves over with one final
/// prompt. After that the keychain is never touched. Clearing writes an empty
/// file rather than deleting it, so a cleared secret can't resurface from the
/// fallback.
final class FileSecretStringStore: SecretStringStore {
  private let url: URL
  private let fallback: SecretStringStore?

  init(filename: String, directory: URL? = nil, fallback: SecretStringStore? = nil) {
    let base = directory ?? Self.defaultDirectory()
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = base.appendingPathComponent(filename)
    self.fallback = fallback
  }

  func save(_ value: String) throws {
    try Data(value.utf8).write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  func load() throws -> String? {
    if FileManager.default.fileExists(atPath: url.path) {
      let value = try String(contentsOf: url, encoding: .utf8)
      return value.isEmpty ? nil : value
    }
    guard let migrated = (try? fallback?.load()) ?? nil, !migrated.isEmpty else { return nil }
    try save(migrated)
    return migrated
  }

  func clear() throws {
    try save("")
  }

  private static func defaultDirectory() -> URL {
    let support = (try? FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("Dial", isDirectory: true)
  }
}
