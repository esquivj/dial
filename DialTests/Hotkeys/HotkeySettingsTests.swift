import Carbon.HIToolbox
import XCTest
@testable import Dial

final class HotkeySettingsTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "HotkeySettingsTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private let custom = KeyShortcut(keyCode: kVK_ANSI_K, modifiers: [.control, .option, .command])

  func test_freshInstallUsesDefaultsAndIsOn() {
    let settings = HotkeySettings(defaults: defaults)
    XCTAssertTrue(settings.enabled)
    for action in HotkeyAction.allCases {
      XCTAssertEqual(settings.shortcut(for: action), action.defaultShortcut)
    }
    XCTAssertEqual(settings.activeBindings.count, HotkeyAction.allCases.count)
  }

  func test_customShortcutSurvivesRelaunch() {
    HotkeySettings(defaults: defaults).set(custom, for: .like)

    let reloaded = HotkeySettings(defaults: defaults)
    XCTAssertEqual(reloaded.shortcut(for: .like), custom)
    XCTAssertEqual(reloaded.shortcut(for: .next), HotkeyAction.next.defaultShortcut)
  }

  func test_clearedShortcutStaysClearedAfterRelaunch() {
    HotkeySettings(defaults: defaults).set(nil, for: .openHUD)

    let reloaded = HotkeySettings(defaults: defaults)
    XCTAssertNil(reloaded.shortcut(for: .openHUD))
    XCTAssertNil(reloaded.activeBindings[.openHUD])
    XCTAssertEqual(reloaded.activeBindings.count, HotkeyAction.allCases.count - 1)
  }

  func test_settingTheDefaultAgainDropsTheOverride() {
    let settings = HotkeySettings(defaults: defaults)
    settings.set(custom, for: .like)
    settings.set(HotkeyAction.like.defaultShortcut, for: .like)

    XCTAssertNil(defaults.object(forKey: HotkeySettings.bindingsKey))
    XCTAssertEqual(HotkeySettings(defaults: defaults).shortcut(for: .like), HotkeyAction.like.defaultShortcut)
  }

  func test_disabledSurvivesRelaunch() {
    HotkeySettings(defaults: defaults).enabled = false
    XCTAssertFalse(HotkeySettings(defaults: defaults).enabled)
  }

  func test_resetRestoresEveryDefaultAndTurnsShortcutsOn() {
    let settings = HotkeySettings(defaults: defaults)
    settings.enabled = false
    settings.set(nil, for: .playPause)
    settings.set(custom, for: .like)

    settings.resetToDefaults()

    let reloaded = HotkeySettings(defaults: defaults)
    XCTAssertTrue(reloaded.enabled)
    XCTAssertEqual(reloaded.shortcut(for: .playPause), HotkeyAction.playPause.defaultShortcut)
    XCTAssertEqual(reloaded.shortcut(for: .like), HotkeyAction.like.defaultShortcut)
  }

  func test_unknownStoredActionsAreIgnored() throws {
    let stored: [String: HotkeySettings.Binding] = ["retired": .cleared, "like": .shortcut(custom)]
    defaults.set(try JSONEncoder().encode(stored), forKey: HotkeySettings.bindingsKey)

    let settings = HotkeySettings(defaults: defaults)
    XCTAssertEqual(settings.shortcut(for: .like), custom)
    XCTAssertEqual(settings.activeBindings.count, HotkeyAction.allCases.count)
  }

  func test_carbonModifierFlagsRoundTrip() {
    let all: KeyShortcut.Modifiers = [.control, .option, .shift, .command]
    XCTAssertEqual(KeyShortcut.Modifiers(carbonFlags: all.carbonFlags), all)
    XCTAssertEqual(KeyShortcut.Modifiers(carbonFlags: UInt32(cmdKey)), [.command])
  }

  func test_defaultShortcutDisplayUsesAppleModifierOrder() {
    XCTAssertTrue(HotkeyAction.playPause.defaultShortcut.displayString.hasPrefix("⌃⌥⌘"))
    XCTAssertEqual(
      HotkeyAction.playPause.defaultShortcut.accessibilityName,
      "Control Option Command P")
  }
}
