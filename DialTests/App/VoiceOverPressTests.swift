import AppKit
import XCTest
@testable import Dial

/// The desktop memory object and the memory pop-up are buttons to VoiceOver
/// ("Opens Dial."), but their AppKit host views take every mouse event. So
/// each needs an accessibility hit test that reaches the SwiftUI element
/// under the pointer, and a press action on that element. These tests go
/// through the real controllers the way VoiceOver does: hit test the
/// window, then press what comes back.
@MainActor
final class VoiceOverPressTests: XCTestCase {
  private var shownWindows: [NSWindow] = []
  private var defaultsSuites: [String] = []

  override func tearDown() async throws {
    shownWindows.forEach { $0.orderOut(nil) }
    shownWindows = []
    defaultsSuites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
    defaultsSuites = []
  }

  func test_desktopMemoryObjectIsAButtonVoiceOverCanPress() throws {
    var opens = 0
    let controller = DesktopMemoryController(coord: try makeCoordinator(), openHUD: { opens += 1 })
    let panel = try XCTUnwrap(visibleWindow(sized: DesktopMemoryMetrics.windowSize))

    let button = try XCTUnwrap(element(atCenterOf: panel))
    XCTAssertEqual(button.value(forKey: "accessibilityRole") as? String, NSAccessibility.Role.button.rawValue)
    XCTAssertEqual(button.value(forKey: "accessibilityHelp") as? String, "Opens Dial.")
    XCTAssertTrue(press(button))
    XCTAssertEqual(opens, 1)
    withExtendedLifetime(controller) {}
  }

  func test_memoryPopupIsAButtonVoiceOverCanPress() throws {
    var opens = 0
    let controller = MemoryPopupController()
    controller.onClick = { opens += 1 }
    let content = MemoryPopupContent(
      kind: .rediscovered,
      label: "REDISCOVERED",
      line: "Last played Mar 2023",
      trackName: "Kiss Me Thru the Phone",
      artistName: "Soulja Boy")
    // Far off screen: the strip only needs a frame to hit test.
    controller.show(content, theme: .classic, below: NSRect(x: -10_000, y: -10_000, width: 30, height: 22), on: nil)
    let panel = try XCTUnwrap(visibleWindow(sized: MemoryPopupView.size))

    let button = try XCTUnwrap(element(atCenterOf: panel))
    XCTAssertEqual(button.value(forKey: "accessibilityRole") as? String, NSAccessibility.Role.button.rawValue)
    XCTAssertEqual(
      button.value(forKey: "accessibilityLabel") as? String,
      "Rediscovered: Last played Mar 2023. Kiss Me Thru the Phone · Soulja Boy")
    XCTAssertTrue(press(button))
    XCTAssertEqual(opens, 1)
    XCTAssertFalse(controller.isVisible, "Pressing the strip puts it away, like a click.")
  }

  // MARK: - Helpers

  private func makeCoordinator() throws -> AppCoordinator {
    let suite = "Dial.VoiceOverPressTests.\(UUID().uuidString)"
    defaultsSuites.append(suite)
    let tokenStore = InMemoryTokenStore()
    return AppCoordinator(
      dbq: try InMemoryDatabase.make(),
      client: SpotifyClient(tokenStore: tokenStore, refresh: { throw SpotifyAuthError.missingStoredToken }),
      auth: SpotifyAuthService(clientID: "voiceover", tokenStore: tokenStore),
      tokenStore: tokenStore,
      defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
  }

  /// The controllers keep their panels private; find the one just shown.
  private func visibleWindow(sized size: CGSize) -> NSWindow? {
    let window = NSApp.windows.first { $0.isVisible && $0.frame.size == size }
    if let window {
      shownWindows.append(window)
      window.contentView?.layoutSubtreeIfNeeded()
    }
    return window
  }

  // SwiftUI's accessibility nodes answer the NSAccessibility methods
  // without adopting the protocol in a way Swift can cast to, so they are
  // read by key and pressed by selector.

  /// What VoiceOver lands on when the pointer is over the middle of `window`.
  private func element(atCenterOf window: NSWindow) -> NSObject? {
    window.accessibilityHitTest(NSPoint(x: window.frame.midX, y: window.frame.midY)) as? NSObject
  }

  /// What VoiceOver's VO-Space sends: `accessibilityPerformPress`.
  private func press(_ element: NSObject) -> Bool {
    typealias Press = @convention(c) (NSObject, Selector) -> ObjCBool
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard element.responds(to: selector) else { return false }
    return unsafeBitCast(element.method(for: selector), to: Press.self)(element, selector).boolValue
  }
}
