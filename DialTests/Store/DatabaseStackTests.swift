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
}
