// DialTests/Store/PetStateDAOTests.swift
import XCTest
import GRDB
@testable import Dial

final class PetStateDAOTests: XCTestCase {
  func test_get_returnsSingleton() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = PetStateDAO(dbq: dbq)
    let s = try dao.get()
    XCTAssertEqual(s.id, 1)
    XCTAssertEqual(s.stage, .egg)
  }
  func test_update_persists() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = PetStateDAO(dbq: dbq)
    try dao.update { state in
      state.xp = 750
      state.stage = .hatching
    }
    let s = try dao.get()
    XCTAssertEqual(s.xp, 750)
    XCTAssertEqual(s.stage, .hatching)
  }
}
