// Dial/Hotkeys/HotkeyConflicts.swift
import Carbon.HIToolbox
import Foundation

/// Why a recorded shortcut can't be saved.
enum HotkeyConflict: Equatable {
  /// Plain keys (and Shift-only) would fire while typing. Function keys
  /// are fine on their own.
  case needsModifier
  /// Another Dial action already uses it.
  case dial(HotkeyAction)
  /// macOS uses it (Spotlight, app switcher, screenshots, …).
  case system(String)
  /// Another app registered it first, so macOS refused it.
  case otherApp

  var message: String {
    switch self {
    case .needsModifier:      "Add ⌘, ⌃ or ⌥ (function keys work alone)."
    case .dial(let action):   "Already used by \(action.title)."
    case .system(let name):   "macOS uses this for \(name)."
    case .otherApp:           "Another app is using this shortcut."
    }
  }
}

struct HotkeyConflictChecker {
  /// Shortcuts macOS owns, with a short name for the message.
  var systemShortcuts: [KeyShortcut: String]

  init(systemShortcuts: [KeyShortcut: String] = SystemShortcuts.current()) {
    self.systemShortcuts = systemShortcuts
  }

  func conflict(
    for candidate: KeyShortcut,
    assigningTo action: HotkeyAction,
    current bindings: [HotkeyAction: KeyShortcut]
  ) -> HotkeyConflict? {
    let anchors: KeyShortcut.Modifiers = [.command, .control, .option]
    if candidate.modifiers.isDisjoint(with: anchors), !candidate.isFunctionKey {
      return .needsModifier
    }
    if let owner = HotkeyAction.allCases.first(where: { $0 != action && bindings[$0] == candidate }) {
      return .dial(owner)
    }
    if let name = systemShortcuts[candidate] {
      return .system(name)
    }
    return nil
  }
}

enum SystemShortcuts {
  /// Shortcuts every Mac reserves whether or not they show up in the
  /// symbolic hot key table.
  static let reserved: [KeyShortcut: String] = [
    KeyShortcut(keyCode: kVK_Space, modifiers: [.command]): "Spotlight",
    KeyShortcut(keyCode: kVK_Space, modifiers: [.control]): "input sources",
    KeyShortcut(keyCode: kVK_Space, modifiers: [.control, .command]): "the emoji picker",
    KeyShortcut(keyCode: kVK_Tab, modifiers: [.command]): "the app switcher",
    KeyShortcut(keyCode: kVK_ANSI_Grave, modifiers: [.command]): "switching windows",
    KeyShortcut(keyCode: kVK_ANSI_Q, modifiers: [.command]): "Quit",
    KeyShortcut(keyCode: kVK_ANSI_W, modifiers: [.command]): "Close Window",
    KeyShortcut(keyCode: kVK_ANSI_H, modifiers: [.command]): "Hide",
    KeyShortcut(keyCode: kVK_ANSI_M, modifiers: [.command]): "Minimize",
    KeyShortcut(keyCode: kVK_ANSI_Comma, modifiers: [.command]): "Settings",
    KeyShortcut(keyCode: kVK_ANSI_Q, modifiers: [.control, .command]): "Lock Screen",
    KeyShortcut(keyCode: kVK_Escape, modifiers: [.option, .command]): "Force Quit",
    KeyShortcut(keyCode: kVK_ANSI_3, modifiers: [.shift, .command]): "screenshots",
    KeyShortcut(keyCode: kVK_ANSI_4, modifiers: [.shift, .command]): "screenshots",
    KeyShortcut(keyCode: kVK_ANSI_5, modifiers: [.shift, .command]): "screenshots",
  ]

  /// The reserved list plus every enabled shortcut in System Settings ›
  /// Keyboard › Keyboard Shortcuts (Mission Control, Spaces, Spotlight, …).
  static func current() -> [KeyShortcut: String] {
    var result = reserved
    for shortcut in enabledSymbolicHotKeys() where result[shortcut] == nil {
      result[shortcut] = "a system shortcut"
    }
    return result
  }

  private static func enabledSymbolicHotKeys() -> [KeyShortcut] {
    var unmanaged: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&unmanaged) == noErr,
          let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
    else { return [] }
    return entries.compactMap { entry in
      guard
        (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
        let code = (entry["kHISymbolicHotKeyCode"] as? NSNumber)?.intValue,
        let flags = (entry["kHISymbolicHotKeyModifiers"] as? NSNumber)?.uint32Value,
        code >= 0, code < 0xFFFF
      else { return nil }
      return KeyShortcut(keyCode: code, modifiers: .init(carbonFlags: flags))
    }
  }
}
