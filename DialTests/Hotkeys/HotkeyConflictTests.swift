import Carbon.HIToolbox
import XCTest
@testable import Dial

final class HotkeyConflictTests: XCTestCase {
  private let chord: KeyShortcut.Modifiers = [.control, .option, .command]
  private var defaults: [HotkeyAction: KeyShortcut] {
    Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, $0.defaultShortcut) })
  }

  private func checker(system: [KeyShortcut: String] = SystemShortcuts.reserved) -> HotkeyConflictChecker {
    HotkeyConflictChecker(systemShortcuts: system)
  }

  func test_defaultsAreDistinct() {
    XCTAssertEqual(Set(defaults.values).count, HotkeyAction.allCases.count)
  }

  func test_defaultsAvoidFunctionKeysSpaceAndReservedShortcuts() {
    for (action, shortcut) in defaults {
      XCTAssertFalse(shortcut.isFunctionKey, "\(action) uses a function key")
      XCTAssertNotEqual(Int(shortcut.keyCode), kVK_Space, "\(action) uses Space")
      XCTAssertNil(SystemShortcuts.reserved[shortcut], "\(action) clashes with macOS")
      XCTAssertNil(checker().conflict(for: shortcut, assigningTo: action, current: defaults))
    }
  }

  func test_defaultsDontClashWithThisMacsSystemShortcuts() {
    let live = checker(system: SystemShortcuts.current())
    for (action, shortcut) in defaults {
      XCTAssertNil(live.conflict(for: shortcut, assigningTo: action, current: defaults), "\(action)")
    }
  }

  func test_plainKeysAndShiftOnlyNeedAModifier() {
    let plain = KeyShortcut(keyCode: kVK_ANSI_P, modifiers: [])
    let shifted = KeyShortcut(keyCode: kVK_ANSI_P, modifiers: [.shift])
    XCTAssertEqual(checker().conflict(for: plain, assigningTo: .playPause, current: [:]), .needsModifier)
    XCTAssertEqual(checker().conflict(for: shifted, assigningTo: .playPause, current: [:]), .needsModifier)
  }

  func test_functionKeysAndSpaceAreAllowedWhenFree() {
    let f13 = KeyShortcut(keyCode: kVK_F13, modifiers: [])
    let hyperSpace = KeyShortcut(keyCode: kVK_Space, modifiers: chord)
    XCTAssertNil(checker().conflict(for: f13, assigningTo: .playPause, current: [:]))
    XCTAssertNil(checker().conflict(for: hyperSpace, assigningTo: .playPause, current: [:]))
  }

  func test_shortcutUsedByAnotherActionIsRejected() {
    let taken = HotkeyAction.next.defaultShortcut
    XCTAssertEqual(
      checker().conflict(for: taken, assigningTo: .like, current: defaults),
      .dial(.next))
  }

  func test_reassigningAnActionItsOwnShortcutIsFine() {
    let own = HotkeyAction.like.defaultShortcut
    XCTAssertNil(checker().conflict(for: own, assigningTo: .like, current: defaults))
  }

  func test_shortcutFreedByClearingIsAvailable() {
    var bindings = defaults
    bindings[.next] = nil
    XCTAssertNil(checker().conflict(
      for: HotkeyAction.next.defaultShortcut, assigningTo: .like, current: bindings))
  }

  func test_macOSShortcutsAreRejectedWithTheirName() {
    let spotlight = KeyShortcut(keyCode: kVK_Space, modifiers: [.command])
    XCTAssertEqual(
      checker().conflict(for: spotlight, assigningTo: .playPause, current: [:]),
      .system("Spotlight"))

    let missionControl = KeyShortcut(keyCode: kVK_UpArrow, modifiers: [.control])
    let symbolic = checker(system: [missionControl: "a system shortcut"])
    XCTAssertEqual(
      symbolic.conflict(for: missionControl, assigningTo: .volumeUp, current: [:]),
      .system("a system shortcut"))
  }

  func test_conflictMessagesNameTheOwner() {
    XCTAssertEqual(HotkeyConflict.dial(.next).message, "Already used by Next track.")
    XCTAssertEqual(HotkeyConflict.system("Spotlight").message, "macOS uses this for Spotlight.")
  }
}
