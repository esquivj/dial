import XCTest
@testable import Dial

/// PLA-107: empty readouts read as states, not gaps.
final class ReadoutValuesTests: XCTestCase {
  func test_rankValue() {
    XCTAssertEqual(ReadoutsRow.rankValue(12), "#12")
    XCTAssertEqual(ReadoutsRow.rankValue(nil), "UNRANKED")
  }

  func test_firstPlayWord() {
    XCTAssertEqual(ReadoutsRow.firstPlay, "FIRST")
  }
}
