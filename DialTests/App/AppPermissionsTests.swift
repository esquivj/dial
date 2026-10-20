import CoreServices
import XCTest
@testable import Dial

final class AppPermissionsTests: XCTestCase {
  func test_automationAnswersBecomeStatuses() {
    XCTAssertEqual(PermissionStatus(automation: noErr), .allowed)
    XCTAssertEqual(PermissionStatus(automation: OSStatus(errAEEventNotPermitted)), .notAllowed)
    XCTAssertEqual(PermissionStatus(automation: OSStatus(errAEEventWouldRequireUserConsent)), .notAsked)
    XCTAssertEqual(PermissionStatus(automation: OSStatus(procNotFound)), .unknown, "Spotify isn't running")
    XCTAssertEqual(PermissionStatus(automation: OSStatus(errAETimeout)), .unknown)
  }

  func test_screenRecordingIsAllowedWhenMacOSSaysSoOrTheSpectrumRuns() {
    XCTAssertEqual(screen(allowed: true, requested: true, visualizer: .idle), .allowed)
    XCTAssertEqual(screen(allowed: true, requested: false, visualizer: .denied), .allowed)
    XCTAssertEqual(
      screen(allowed: false, requested: true, visualizer: .running), .allowed,
      "A live spectrum wins over a stale preflight")
  }

  func test_screenRecordingIsNotAllowedOnceDialHasAsked() {
    XCTAssertEqual(screen(allowed: false, requested: true, visualizer: .idle), .notAllowed)
    XCTAssertEqual(screen(allowed: false, requested: true, visualizer: .error), .notAllowed)
    XCTAssertEqual(screen(allowed: false, requested: false, visualizer: .denied), .notAllowed)
  }

  func test_screenRecordingIsNotAskedYetBeforeTheFirstCapture() {
    XCTAssertEqual(screen(allowed: false, requested: false, visualizer: .idle), .notAsked)
    XCTAssertEqual(screen(allowed: false, requested: false, visualizer: .error), .notAsked)
  }

  func test_everyStatusHasWordsAndABundledIcon() throws {
    let statuses: [PermissionStatus] = [.allowed, .notAllowed, .notAsked, .unknown]
    XCTAssertEqual(statuses.map(\.label), ["Allowed", "Not allowed", "Not asked yet", "Unknown"])
    XCTAssertEqual(
      Set([PermissionStatus.allowed, .notAllowed, .notAsked].map(\.icon)).count, 3,
      "Allowed, not allowed and not asked yet need different shapes, not just colors")
    for status in statuses {
      // Same lookup as DialIcon: the build flattens Icons/ into Resources/.
      let url = Bundle.main.url(forResource: status.icon, withExtension: "png", subdirectory: "Icons")
        ?? Bundle.main.url(forResource: status.icon, withExtension: "png")
      XCTAssertNotNil(url, "\(status.icon).png isn't in the app bundle")
    }
  }

  func test_theRequestedFlagRemembersTheFirstCapture() throws {
    let suite = "Dial.AppPermissionsTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertFalse(ScreenRecordingAccess.wasRequested(in: defaults))
    ScreenRecordingAccess.noteRequested(in: defaults)
    XCTAssertTrue(ScreenRecordingAccess.wasRequested(in: defaults))
  }

  private func screen(allowed: Bool, requested: Bool, visualizer: VisualizerEngine.State) -> PermissionStatus {
    PermissionStatus(screenRecordingAllowed: allowed, captureRequested: requested, visualizer: visualizer)
  }
}
