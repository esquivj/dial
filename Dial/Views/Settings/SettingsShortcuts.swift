// Dial/Views/Settings/SettingsShortcuts.swift
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// SHORTCUTS: the global-hotkey switch and one recorder row per action.
/// Only one row listens at a time. While it listens, Dial's own hotkeys are
/// paused so the press lands here instead of firing.
struct SettingsShortcutsSection: View {
  @Bindable var hotkeys: HotkeySettings

  @State private var recording: HotkeyAction?
  @State private var problem: (action: HotkeyAction, message: String)?
  @State private var monitor: Any?

  var body: some View {
    SettingsSection("SHORTCUTS") {
      VStack(spacing: SettingsLayout.controlGap) {
        SettingsToggle(
          title: "Global shortcuts",
          detail: "Control Spotify from any app. Each press shows a short readout under the menu bar item.",
          isOn: $hotkeys.enabled)

        if hotkeys.enabled {
          ForEach(HotkeyAction.allCases) { action in
            SettingsShortcutRow(
              action: action,
              shortcut: hotkeys.shortcut(for: action),
              isRecording: recording == action,
              message: message(for: action),
              onRecord: { toggleRecording(action) },
              onClear: { clear(action) })
          }

          SettingsActionRow {
            Button("Reset Shortcuts") {
              stopRecording()
              problem = nil
              hotkeys.resetToDefaults()
            }
            .buttonStyle(SettingsButtonStyle())
          }
        }
      }
    }
    .onDisappear { stopRecording() }
    .onChange(of: hotkeys.enabled) { _, _ in stopRecording() }
  }

  private func message(for action: HotkeyAction) -> String? {
    if let problem, problem.action == action { return problem.message }
    if recording == action { return "Press the new shortcut. Esc cancels, Delete clears." }
    if hotkeys.unavailable.contains(action) { return HotkeyConflict.otherApp.message }
    return nil
  }

  private func toggleRecording(_ action: HotkeyAction) {
    if recording == action {
      stopRecording()
      return
    }
    stopRecording()
    problem = nil
    recording = action
    hotkeys.isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handle(event, for: action)
      return nil
    }
  }

  private func handle(_ event: NSEvent, for action: HotkeyAction) {
    let modifiers = KeyShortcut.Modifiers(event.modifierFlags)
    switch Int(event.keyCode) {
    case kVK_Escape where modifiers.isEmpty:
      stopRecording()
      return
    case kVK_Delete where modifiers.isEmpty, kVK_ForwardDelete where modifiers.isEmpty:
      clear(action)
      return
    default:
      break
    }
    let candidate = KeyShortcut(keyCode: Int(event.keyCode), modifiers: modifiers)
    // Read the system table per press: the user may have changed it.
    if let conflict = HotkeyConflictChecker().conflict(
      for: candidate, assigningTo: action, current: hotkeys.activeBindings) {
      problem = (action, "\(candidate.displayString): \(conflict.message)")
      return
    }
    problem = nil
    hotkeys.set(candidate, for: action)
    stopRecording()
  }

  private func clear(_ action: HotkeyAction) {
    problem = nil
    hotkeys.set(nil, for: action)
    if recording == action { stopRecording() }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
    hotkeys.isRecording = false
  }
}

struct SettingsShortcutRow: View {
  let action: HotkeyAction
  let shortcut: KeyShortcut?
  let isRecording: Bool
  let message: String?
  let onRecord: () -> Void
  let onClear: () -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack(alignment: .center, spacing: 8) {
        Text(action.title)
          .font(SettingsType.rowTitle)
          .foregroundStyle(SettingsPalette.text)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: onRecord) {
          Text(keyLabel)
            .font(SettingsType.mono)
            .foregroundStyle(isRecording ? SettingsPalette.accent : (shortcut == nil ? SettingsPalette.faint : SettingsPalette.text))
            .lineLimit(1)
            .frame(width: SettingsLayout.pickerWidth - 30, height: 27)
            .background(
              RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                .fill(isRecording ? SettingsPalette.accent.opacity(0.10) : SettingsPalette.control))
            .overlay(
              RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                .stroke(isRecording ? SettingsPalette.accent.opacity(0.75) : SettingsPalette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(isRecording ? "Press the new shortcut" : "Click, then press a new shortcut")
        .accessibilityLabel("\(action.title) shortcut")
        .accessibilityValue(isRecording ? "Recording" : (shortcut?.accessibilityName ?? "None"))
        .accessibilityHint("Click, then press a new shortcut.")

        Button(action: onClear) {
          DialIcon("xmark.circle")
            .frame(width: 12, height: 12)
            .foregroundStyle(SettingsPalette.faint)
            .frame(width: 22, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(shortcut == nil)
        .opacity(shortcut == nil ? 0.35 : 1)
        .help("Clear shortcut")
        .accessibilityLabel("Clear \(action.title) shortcut")
      }
      .frame(minHeight: 31)

      if let message {
        Text(message)
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.muted)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var keyLabel: String {
    if isRecording { return "Press keys…" }
    return shortcut?.displayString ?? "None"
  }
}
