// DialTests/Pet/StreakCalendarTests.swift
import XCTest
@testable import Dial

final class StreakCalendarTests: XCTestCase {
  func test_firstPlay_setsAnchor_and_streak1() {
    let cal = StreakCalendar()
    let r = cal.apply(playDate: "2026-04-24", priorAnchor: nil, priorDays: 0)
    XCTAssertEqual(r.anchor, "2026-04-24")
    XCTAssertEqual(r.days, 1)
  }
  func test_nextDayPlay_incrementsStreak() {
    let cal = StreakCalendar()
    let r = cal.apply(playDate: "2026-04-25", priorAnchor: "2026-04-24", priorDays: 1)
    XCTAssertEqual(r.days, 2)
  }
  func test_samedayPlay_doesNotChangeStreak() {
    let cal = StreakCalendar()
    let r = cal.apply(playDate: "2026-04-24", priorAnchor: "2026-04-24", priorDays: 1)
    XCTAssertEqual(r.days, 1)
  }
  func test_gapOfTwoDays_resetsStreakTo1() {
    let cal = StreakCalendar()
    let r = cal.apply(playDate: "2026-04-27", priorAnchor: "2026-04-24", priorDays: 1)
    XCTAssertEqual(r.days, 1)
    XCTAssertEqual(r.anchor, "2026-04-27")
  }
}
