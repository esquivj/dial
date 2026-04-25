import XCTest
@testable import Dial

final class DedupRuleTests: XCTestCase {
  func test_under30s_andUnder50pct_doesNotCount() {
    XCTAssertFalse(DedupRule.shouldCount(progressMs: 15_000, durationMs: 200_000))
  }
  func test_at30s_counts() {
    XCTAssertTrue(DedupRule.shouldCount(progressMs: 30_000, durationMs: 200_000))
  }
  func test_at50pctButShort_counts() {
    XCTAssertTrue(DedupRule.shouldCount(progressMs: 15_000, durationMs: 20_000))   // 75% of a 20s track
  }
}
