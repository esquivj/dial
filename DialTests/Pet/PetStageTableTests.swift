// DialTests/Pet/PetStageTableTests.swift
import XCTest
@testable import Dial

final class PetStageTableTests: XCTestCase {
  func test_stageForXP_boundaries() {
    XCTAssertEqual(PetStageTable.stage(forXP: 0), .egg)
    XCTAssertEqual(PetStageTable.stage(forXP: 499), .egg)
    XCTAssertEqual(PetStageTable.stage(forXP: 500), .hatching)
    XCTAssertEqual(PetStageTable.stage(forXP: 999), .hatching)
    XCTAssertEqual(PetStageTable.stage(forXP: 1_000), .hatchling)
    XCTAssertEqual(PetStageTable.stage(forXP: 5_000), .juvenile)
    XCTAssertEqual(PetStageTable.stage(forXP: 25_000), .companion)
    XCTAssertEqual(PetStageTable.stage(forXP: 100_000), .elder)
  }
  func test_elderGated_returnsCompanionIfNotUnlocked() {
    XCTAssertEqual(PetStageTable.stage(forXP: 120_000, elderUnlocked: false), .companion)
    XCTAssertEqual(PetStageTable.stage(forXP: 120_000, elderUnlocked: true), .elder)
  }
}
