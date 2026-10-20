// Dial/Hotkeys/KeyShortcut.swift
import AppKit
import Carbon.HIToolbox

/// One global key combination: a physical key (Carbon virtual key code) plus
/// modifiers. Stored by key code, not character, so a shortcut keeps working
/// when the keyboard layout changes; `displayString` asks the current layout
/// what the key prints.
struct KeyShortcut: Codable, Hashable {
  struct Modifiers: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let control = Modifiers(rawValue: 1 << 0)
    static let option  = Modifiers(rawValue: 1 << 1)
    static let shift   = Modifiers(rawValue: 1 << 2)
    static let command = Modifiers(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(_ flags: NSEvent.ModifierFlags) {
      var value: Modifiers = []
      if flags.contains(.control) { value.insert(.control) }
      if flags.contains(.option)  { value.insert(.option) }
      if flags.contains(.shift)   { value.insert(.shift) }
      if flags.contains(.command) { value.insert(.command) }
      self = value
    }

    /// The mask `RegisterEventHotKey` expects.
    var carbonFlags: UInt32 {
      var flags: UInt32 = 0
      if contains(.control) { flags |= UInt32(controlKey) }
      if contains(.option)  { flags |= UInt32(optionKey) }
      if contains(.shift)   { flags |= UInt32(shiftKey) }
      if contains(.command) { flags |= UInt32(cmdKey) }
      return flags
    }

    init(carbonFlags flags: UInt32) {
      var value: Modifiers = []
      if flags & UInt32(controlKey) != 0 { value.insert(.control) }
      if flags & UInt32(optionKey) != 0  { value.insert(.option) }
      if flags & UInt32(shiftKey) != 0   { value.insert(.shift) }
      if flags & UInt32(cmdKey) != 0     { value.insert(.command) }
      self = value
    }

    /// Apple's order: ⌃ ⌥ ⇧ ⌘.
    var symbols: String {
      (contains(.control) ? "⌃" : "")
        + (contains(.option) ? "⌥" : "")
        + (contains(.shift) ? "⇧" : "")
        + (contains(.command) ? "⌘" : "")
    }
  }

  let keyCode: UInt32
  let modifiers: Modifiers

  init(keyCode: Int, modifiers: Modifiers) {
    self.keyCode = UInt32(keyCode)
    self.modifiers = modifiers
  }

  var isFunctionKey: Bool { Self.functionKeyNames[Int(keyCode)] != nil }

  var displayString: String { modifiers.symbols + keyName }

  var keyName: String {
    if let name = Self.functionKeyNames[Int(keyCode)] ?? Self.specialKeyNames[Int(keyCode)] {
      return name
    }
    return Self.layoutCharacter(for: keyCode)?.uppercased() ?? "#\(keyCode)"
  }

  /// Spoken form for VoiceOver ("Control Option Command P").
  var accessibilityName: String {
    var parts: [String] = []
    if modifiers.contains(.control) { parts.append("Control") }
    if modifiers.contains(.option)  { parts.append("Option") }
    if modifiers.contains(.shift)   { parts.append("Shift") }
    if modifiers.contains(.command) { parts.append("Command") }
    parts.append(Self.spokenKeyNames[Int(keyCode)] ?? keyName)
    return parts.joined(separator: " ")
  }

  static let functionKeyNames: [Int: String] = [
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
    kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
    kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
    kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
  ]

  private static let specialKeyNames: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
    kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
    kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
    kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
  ]

  private static let spokenKeyNames: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Escape",
    kVK_Delete: "Delete", kVK_LeftArrow: "Left Arrow", kVK_RightArrow: "Right Arrow",
    kVK_UpArrow: "Up Arrow", kVK_DownArrow: "Down Arrow",
    kVK_ANSI_Equal: "Equals", kVK_ANSI_Minus: "Minus",
    kVK_ANSI_LeftBracket: "Left Bracket", kVK_ANSI_RightBracket: "Right Bracket",
  ]

  /// What the key types on the current keyboard layout, without modifiers.
  private static func layoutCharacter(for keyCode: UInt32) -> String? {
    guard
      let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return fallbackCharacters[Int(keyCode)] }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    let status = data.withUnsafeBytes { buffer -> OSStatus in
      guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return OSStatus(paramErr)
      }
      return UCKeyTranslate(
        layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState, chars.count, &length, &chars)
    }
    guard status == noErr, length > 0 else { return fallbackCharacters[Int(keyCode)] }
    let string = String(utf16CodeUnits: chars, count: length)
    return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? fallbackCharacters[Int(keyCode)] : string
  }

  /// US-layout names, for when the layout can't be read.
  private static let fallbackCharacters: [Int: String] = [
    kVK_ANSI_P: "P", kVK_ANSI_L: "L", kVK_ANSI_D: "D", kVK_ANSI_M: "M",
    kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
    kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-",
  ]
}
