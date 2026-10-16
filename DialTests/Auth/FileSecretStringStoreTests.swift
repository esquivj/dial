// DialTests/Auth/FileSecretStringStoreTests.swift
import XCTest
@testable import Dial

final class FileSecretStringStoreTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  func test_migratesFromFallbackOnceThenStopsReadingIt() throws {
    let fallback = CountingStore(value: "legacy-key")
    let store = FileSecretStringStore(filename: "k", directory: dir, fallback: fallback)

    XCTAssertEqual(try store.load(), "legacy-key")
    XCTAssertEqual(try store.load(), "legacy-key")
    XCTAssertEqual(fallback.loads, 1, "Fallback (keychain) is read only until the file exists")

    let perms = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("k").path)[.posixPermissions] as? Int
    XCTAssertEqual(perms, 0o600)
  }

  func test_clearedSecretDoesNotResurfaceFromFallback() throws {
    let fallback = CountingStore(value: "legacy-key")
    let store = FileSecretStringStore(filename: "k", directory: dir, fallback: fallback)
    try store.save("new-key")
    try store.clear()

    XCTAssertNil(try store.load())
    XCTAssertEqual(fallback.loads, 0)
  }
}

private final class CountingStore: SecretStringStore {
  var value: String?
  var loads = 0
  init(value: String?) { self.value = value }
  func save(_ value: String) throws { self.value = value }
  func load() throws -> String? { loads += 1; return value }
  func clear() throws { value = nil }
}
