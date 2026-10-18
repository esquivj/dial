import XCTest
@testable import Dial

final class FocusFilterTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "Dial.FocusFilter.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private var status: SystemFocusStatus {
    SystemFocusStatus(state: FocusFilterState(defaults: defaults))
  }

  func test_noFocusUntilTheFilterRuns() {
    XCTAssertFalse(status.isFocusActive)
  }

  func test_focusWithFilterOnReportsActive() {
    status.state.apply(hideMemoryPopups: true)
    XCTAssertTrue(status.isFocusActive)
  }

  func test_focusTurningOffClearsIt() {
    status.state.apply(hideMemoryPopups: true)
    // The system re-runs the filter with its parameter unset when the Focus ends.
    status.state.apply(hideMemoryPopups: nil)
    XCTAssertFalse(status.isFocusActive)
  }

  func test_filterWithToggleOffDoesNotHidePopups() {
    status.state.apply(hideMemoryPopups: false)
    XCTAssertFalse(status.isFocusActive)
  }

  func test_stateSurvivesARelaunch() {
    status.state.apply(hideMemoryPopups: true)
    let relaunched = SystemFocusStatus(state: FocusFilterState(defaults: UserDefaults(suiteName: suiteName)!))
    XCTAssertTrue(relaunched.isFocusActive)
  }

  func test_parameterIsOptionalSoTheSystemCanSignalFocusOff() {
    XCTAssertNil(DialFocusFilter().hideMemoryPopups)
  }
}
