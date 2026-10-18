import XCTest
@testable import Dial

/// The flash debounce: repeated presses update one strip in place, and a
/// flash replaces a memory pop-up instead of stacking under it.
final class ReadoutStripScheduleTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)
  private let hold: TimeInterval = 1.0

  func test_firstFlashAppears() {
    var schedule = ReadoutStripSchedule()
    XCTAssertEqual(schedule.present(.flash, hold: hold, at: t0), .appear)
    XCTAssertTrue(schedule.isVisible(at: t0.addingTimeInterval(0.5)))
    XCTAssertFalse(schedule.isVisible(at: t0.addingTimeInterval(1.0)))
  }

  func test_repeatPressesUpdateInPlaceAndRestartTheHold() {
    var schedule = ReadoutStripSchedule()
    _ = schedule.present(.flash, hold: hold, at: t0)

    var now = t0
    for _ in 0..<5 {
      now = now.addingTimeInterval(0.3)
      XCTAssertEqual(schedule.present(.flash, hold: hold, at: now), .updateInPlace)
    }
    XCTAssertEqual(schedule.hideAt, now.addingTimeInterval(hold))
    XCTAssertTrue(schedule.isVisible(at: now.addingTimeInterval(0.9)))
  }

  func test_pressAfterTheFlashEndedAppearsAgain() {
    var schedule = ReadoutStripSchedule()
    _ = schedule.present(.flash, hold: hold, at: t0)
    XCTAssertEqual(schedule.present(.flash, hold: hold, at: t0.addingTimeInterval(1.2)), .appear)
  }

  func test_flashReplacesAMemoryPopupInsteadOfStacking() {
    var schedule = ReadoutStripSchedule()
    _ = schedule.present(.memory, hold: 4, at: t0)

    XCTAssertEqual(schedule.present(.flash, hold: hold, at: t0.addingTimeInterval(1)), .updateInPlace)
    XCTAssertEqual(schedule.visibleKind, .flash)
    // The flash's own short hold takes over from the pop-up's 4 s.
    XCTAssertFalse(schedule.isVisible(at: t0.addingTimeInterval(2.1)))
  }

  func test_memoryPopupReplacesAFlash() {
    var schedule = ReadoutStripSchedule()
    _ = schedule.present(.flash, hold: hold, at: t0)
    XCTAssertEqual(schedule.present(.memory, hold: 4, at: t0.addingTimeInterval(0.4)), .updateInPlace)
    XCTAssertEqual(schedule.visibleKind, .memory)
  }

  func test_dismissedStripAppearsFreshOnTheNextPress() {
    var schedule = ReadoutStripSchedule()
    _ = schedule.present(.flash, hold: hold, at: t0)
    schedule.hidden()
    XCTAssertNil(schedule.visibleKind)
    XCTAssertEqual(schedule.present(.flash, hold: hold, at: t0.addingTimeInterval(0.2)), .appear)
  }

  func test_flashTimingIsAboutOneSecond() {
    let flash = MemoryPopupController.Timing.flash
    let onScreen = flash.fadeIn + flash.hold + flash.fadeOut
    XCTAssertEqual(onScreen, 1.0, accuracy: 0.3)
  }

  func test_volumeFlashClampsAndLightsTheMeter() {
    XCTAssertEqual(HotkeyFlashContent.volume(45).label, "VOL 45%")
    XCTAssertEqual(HotkeyFlashContent.volume(140).label, "VOL 100%")
    XCTAssertEqual(HotkeyFlashContent.volume(-5).level, 0)
    XCTAssertEqual(HotkeyFlashView.litSegments(for: 0), 0)
    XCTAssertEqual(HotkeyFlashView.litSegments(for: 3), 1)
    XCTAssertEqual(HotkeyFlashView.litSegments(for: 45), 5)
    XCTAssertEqual(HotkeyFlashView.litSegments(for: 100), 10)
  }
}
