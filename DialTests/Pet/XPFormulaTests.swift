// DialTests/Pet/XPFormulaTests.swift
import XCTest
@testable import Dial

final class XPFormulaTests: XCTestCase {
  func test_baseXP_isOneXPPerMinute() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 60_000, variety: .none, streakDays: 0), 1)
    XCTAssertEqual(XPFormula.compute(msPlayed: 300_000, variety: .none, streakDays: 0), 5)
  }

  func test_countedPlayAlwaysGetsAtLeastOneXP() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 30_000, variety: .none, streakDays: 0), 1)
  }

  func test_baseXP_roundsToNearestMinute() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 89_000, variety: .none, streakDays: 0), 1)
    XCTAssertEqual(XPFormula.compute(msPlayed: 90_000, variety: .none, streakDays: 0), 2)
  }

  func test_newArtistBonus_adds50() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 60_000, variety: .newArtist, streakDays: 0), 51)
  }
  func test_newAlbumBonus_adds25() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 60_000, variety: .newAlbum, streakDays: 0), 26)
  }
  func test_streakMultiplier_startsAt3Days() {
    // 2 days → no multiplier
    XCTAssertEqual(XPFormula.compute(msPlayed: 60_000, variety: .none, streakDays: 2), 1)
    // 3 days → ×1.25 → floor(1.25) = 1
    XCTAssertEqual(XPFormula.compute(msPlayed: 60_000, variety: .none, streakDays: 3), 1)
    // 100 minutes, 3-day streak → 100 × 1.25 = 125
    XCTAssertEqual(XPFormula.compute(msPlayed: 100 * 60_000, variety: .none, streakDays: 3), 125)
  }
  func test_streakCapsAt2x() {
    XCTAssertEqual(XPFormula.compute(msPlayed: 100 * 60_000, variety: .none, streakDays: 14), 200)
    XCTAssertEqual(XPFormula.compute(msPlayed: 100 * 60_000, variety: .none, streakDays: 30), 200)
  }
}
