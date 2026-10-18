// Dial/Hotkeys/CarbonHotkeyCenter.swift
import Carbon.HIToolbox
import Foundation
import os.log

private let hotkeyLog = Logger(subsystem: "com.dial.Dial", category: "Hotkeys")

protocol HotkeyRegistering: AnyObject {
  var onPress: ((HotkeyAction) -> Void)? { get set }
  /// Replaces every registration with `bindings`. Returns the actions macOS
  /// refused because another app already holds that shortcut.
  @discardableResult
  func register(_ bindings: [HotkeyAction: KeyShortcut]) -> Set<HotkeyAction>
  func unregisterAll()
}

/// Global shortcuts through Carbon's `RegisterEventHotKey`.
///
/// Why Carbon and not a package: it's the API the popular Swift wrappers
/// (KeyboardShortcuts, HotKey) call underneath, it needs no Accessibility
/// or Input Monitoring permission because it only hears the exact chords it
/// registered, and it keeps Dial free of a dependency whose recorder UI and
/// storage we'd have to restyle and work around anyway. The whole surface
/// is one handler and one register/unregister pair.
final class CarbonHotkeyCenter: HotkeyRegistering {
  var onPress: ((HotkeyAction) -> Void)?

  private static let signature: OSType = 0x4449_414C  // 'DIAL'
  private var refs: [HotkeyAction: EventHotKeyRef] = [:]
  private var handler: EventHandlerRef?

  deinit {
    unregisterAll()
    if let handler { RemoveEventHandler(handler) }
  }

  @discardableResult
  func register(_ bindings: [HotkeyAction: KeyShortcut]) -> Set<HotkeyAction> {
    unregisterAll()
    guard !bindings.isEmpty else { return [] }
    installHandlerIfNeeded()

    var refused: Set<HotkeyAction> = []
    for (action, shortcut) in bindings {
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(
        shortcut.keyCode,
        shortcut.modifiers.carbonFlags,
        EventHotKeyID(signature: Self.signature, id: Self.id(for: action)),
        GetApplicationEventTarget(),
        0,
        &ref)
      if status == noErr, let ref {
        refs[action] = ref
      } else {
        refused.insert(action)
        hotkeyLog.notice("\(action.rawValue, privacy: .public) \(shortcut.displayString, privacy: .public) refused: \(status)")
      }
    }
    return refused
  }

  func unregisterAll() {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    refs.removeAll()
  }

  private func installHandlerIfNeeded() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var hotKeyID = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID)
      guard status == noErr, hotKeyID.signature == CarbonHotkeyCenter.signature,
            let action = CarbonHotkeyCenter.action(for: hotKeyID.id)
      else { return OSStatus(eventNotHandledErr) }
      let center = Unmanaged<CarbonHotkeyCenter>.fromOpaque(context).takeUnretainedValue()
      center.onPress?(action)
      return noErr
    }, 1, &spec, context, &handler)
  }

  private static func id(for action: HotkeyAction) -> UInt32 {
    UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1)
  }

  private static func action(for id: UInt32) -> HotkeyAction? {
    let index = Int(id) - 1
    return HotkeyAction.allCases.indices.contains(index) ? HotkeyAction.allCases[index] : nil
  }
}
