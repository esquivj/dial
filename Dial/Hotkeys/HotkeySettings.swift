// Dial/Hotkeys/HotkeySettings.swift
import Carbon.HIToolbox
import Foundation
import Observation

enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
  case playPause
  case next
  case previous
  case like
  case volumeUp
  case volumeDown
  case openHUD
  case toggleDesktopMemory

  var id: String { rawValue }

  var title: String {
    switch self {
    case .playPause:           "Play / pause"
    case .next:                "Next track"
    case .previous:            "Previous track"
    case .like:                "Like / unlike"
    case .volumeUp:            "Volume up"
    case .volumeDown:          "Volume down"
    case .openHUD:             "Open HUD"
    case .toggleDesktopMemory: "Show / hide desktop memory"
    }
  }

  /// ⌃⌥⌘ plus a letter or punctuation key: macOS ships nothing on that
  /// chord, and none of these are function keys or Space. M is for memory.
  var defaultShortcut: KeyShortcut {
    let chord: KeyShortcut.Modifiers = [.control, .option, .command]
    switch self {
    case .playPause:           return KeyShortcut(keyCode: kVK_ANSI_P, modifiers: chord)
    case .next:                return KeyShortcut(keyCode: kVK_ANSI_RightBracket, modifiers: chord)
    case .previous:            return KeyShortcut(keyCode: kVK_ANSI_LeftBracket, modifiers: chord)
    case .like:                return KeyShortcut(keyCode: kVK_ANSI_L, modifiers: chord)
    case .volumeUp:            return KeyShortcut(keyCode: kVK_ANSI_Equal, modifiers: chord)
    case .volumeDown:          return KeyShortcut(keyCode: kVK_ANSI_Minus, modifiers: chord)
    case .openHUD:             return KeyShortcut(keyCode: kVK_ANSI_D, modifiers: chord)
    case .toggleDesktopMemory: return KeyShortcut(keyCode: kVK_ANSI_M, modifiers: chord)
    }
  }
}

/// The user's global shortcuts. Each action is either untouched (uses its
/// default), set to a custom shortcut, or cleared. Cleared is stored
/// explicitly so a default never comes back on its own.
@Observable
final class HotkeySettings {
  enum Binding: Codable, Equatable {
    case shortcut(KeyShortcut)
    case cleared
  }

  var enabled: Bool {
    didSet { defaults.set(enabled, forKey: Self.enabledKey) }
  }

  /// True while Settings is listening for a new shortcut. Registrations
  /// pause meanwhile so pressing a taken chord reaches the recorder.
  var isRecording = false
  /// Actions macOS refused to register because another app holds the chord.
  var unavailable: Set<HotkeyAction> = []

  private var overrides: [HotkeyAction: Binding]
  @ObservationIgnored private let defaults: UserDefaults

  static let enabledKey = "settings.hotkeysEnabled"
  static let bindingsKey = "settings.hotkeyBindings"

  init(defaults: UserDefaults) {
    self.defaults = defaults
    self.enabled = defaults.object(forKey: Self.enabledKey) == nil
      ? true : defaults.bool(forKey: Self.enabledKey)
    self.overrides = Self.loadOverrides(defaults: defaults)
  }

  func shortcut(for action: HotkeyAction) -> KeyShortcut? {
    switch overrides[action] {
    case .shortcut(let shortcut): return shortcut
    case .cleared:                return nil
    case nil:                     return action.defaultShortcut
    }
  }

  /// Every action with a shortcut, ready to register.
  var activeBindings: [HotkeyAction: KeyShortcut] {
    var result: [HotkeyAction: KeyShortcut] = [:]
    for action in HotkeyAction.allCases {
      if let shortcut = shortcut(for: action) { result[action] = shortcut }
    }
    return result
  }

  func set(_ shortcut: KeyShortcut?, for action: HotkeyAction) {
    if let shortcut {
      overrides[action] = shortcut == action.defaultShortcut ? nil : .shortcut(shortcut)
    } else {
      overrides[action] = .cleared
    }
    save()
  }

  func resetToDefaults() {
    overrides = [:]
    enabled = true
    save()
  }

  private func save() {
    let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
    if stored.isEmpty {
      defaults.removeObject(forKey: Self.bindingsKey)
    } else if let data = try? JSONEncoder().encode(stored) {
      defaults.set(data, forKey: Self.bindingsKey)
    }
  }

  private static func loadOverrides(defaults: UserDefaults) -> [HotkeyAction: Binding] {
    guard
      let data = defaults.data(forKey: bindingsKey),
      let stored = try? JSONDecoder().decode([String: Binding].self, from: data)
    else { return [:] }
    var result: [HotkeyAction: Binding] = [:]
    for (raw, binding) in stored {
      if let action = HotkeyAction(rawValue: raw) { result[action] = binding }
    }
    return result
  }
}
