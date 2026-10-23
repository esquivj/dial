// DialTests/Store/DatabaseStackTests.swift
import XCTest
import GRDB
@testable import Dial

final class DatabaseStackTests: XCTestCase {
  func test_migration_createsAllTables() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.read { db in
      for table in ["plays", "tracks", "artists", "imports_log", "pet_state", "badge_events", "pet_trick_unlocks", "artifacts", "weekly_memories"] {
        XCTAssertTrue(try db.tableExists(table), "missing table \(table)")
      }
    }
  }

  func test_migration_initialPetState_isSingleton() throws {
    let dbq = try InMemoryDatabase.make()
    let count = try dbq.read { try PetState.fetchCount($0) }
    XCTAssertEqual(count, 1, "pet_state should seed a singleton row")
  }

  func test_v19_addsPlayOriginAndMergeLog() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.read { db in
      XCTAssertTrue(try db.columns(in: "plays").map(\.name).contains("origin"))
      XCTAssertTrue(try db.tableExists("archive_merges"))
    }

    // Plays recorded the normal way belong to this Mac.
    try PlaysDAO(dbq: dbq).insert(.init(playedAt: 1_700_000_000, trackUri: "T", msPlayed: 60_000, source: "live"))
    let row = try XCTUnwrap(try dbq.read { try Row.fetchOne($0, sql: "SELECT origin FROM plays") })
    XCTAssertNil(row["origin"] as String?)
  }

  func test_fileDatabase_isOwnerOnly() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Dial.DatabaseStackTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755])
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("dial.sqlite")
    _ = try DatabaseStack(url: url)

    XCTAssertEqual(try posixPermissions(at: url), 0o600)
    for suffix in ["-wal", "-shm"] {
      let sidecar = URL(fileURLWithPath: "\(url.path)\(suffix)")
      if FileManager.default.fileExists(atPath: sidecar.path) {
        XCTAssertEqual(try posixPermissions(at: sidecar), 0o600, "bad permissions for \(sidecar.lastPathComponent)")
      }
    }
  }

  private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
    return value.intValue & 0o777
  }
}
