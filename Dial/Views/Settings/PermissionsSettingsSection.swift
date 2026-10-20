// Dial/Views/Settings/PermissionsSettingsSection.swift
import SwiftUI
import AppKit

/// PERMISSIONS in General settings: the two macOS privacy permissions Dial
/// needs, where each stands, and a way to change it in System Settings.
///
/// Reading a status never shows a macOS prompt. macOS asks only when Dial
/// first uses each one: the poller reading the Spotify app, and the spectrum
/// starting ScreenCaptureKit.
struct PermissionsSettingsSection: View {
  let coord: AppCoordinator

  @State private var automation: PermissionStatus?
  @State private var screenRecording: ScreenRecordingCheck?

  private struct ScreenRecordingCheck {
    var allowed: Bool
    var requested: Bool
  }

  var body: some View {
    SettingsSection("PERMISSIONS") {
      VStack(alignment: .leading, spacing: SettingsLayout.rowGap) {
        PermissionRow(
          title: "Spotify control",
          help: "macOS lists this under Privacy & Security › Automation. It lets Dial read the current track from the Spotify app, so the HUD updates instantly. Dial doesn't change anything in Spotify.",
          paneName: "Privacy & Security › Automation",
          status: automation,
          note: automationNote,
          open: { open(.spotifyAutomation) })

        PermissionRow(
          title: "Screen & audio recording",
          help: "macOS lists this under Privacy & Security › Screen & System Audio Recording. Dial uses only the system audio, to draw the spectrum. Audio never leaves your Mac.",
          paneName: "Privacy & Security › Screen & System Audio Recording",
          status: screenRecordingStatus,
          note: screenRecordingNote,
          open: { open(.screenRecording) })
      }
    }
    .task { await refreshWhileVisible() }
    // The poller re-checks Automation on its own; follow it right away.
    .onChange(of: coord.playbackSource) { _, _ in
      Task { await refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      Task { await refresh() }
    }
  }

  /// Reads the spectrum's live state too, so the row flips the moment
  /// capture starts or macOS refuses it.
  private var screenRecordingStatus: PermissionStatus? {
    guard let screenRecording else { return nil }
    return PermissionStatus(
      screenRecordingAllowed: screenRecording.allowed,
      captureRequested: screenRecording.requested,
      visualizer: coord.visualizer.state)
  }

  private var automationNote: String? {
    switch automation {
    case .notAllowed: "Without it, updates are slower."
    case .notAsked where coord.playbackSource == .webAPI(.accessPending):
      "macOS is asking you now."
    case .notAsked:   "macOS asks when Dial reads Spotify."
    case .unknown:    "Open Spotify so Dial can check."
    case .allowed, nil: nil
    }
  }

  private var screenRecordingNote: String? {
    switch screenRecordingStatus {
    case .notAllowed: "Without it, the spectrum stays off."
    case .notAsked:   "macOS asks when the spectrum starts."
    case .allowed, .unknown, nil: nil
    }
  }

  private func open(_ permission: DialPermission) {
    if permission == .screenRecording {
      // Same as the HUD's "ENABLE VISUALIZER" overlay: try the spectrum
      // again when the user comes back from System Settings.
      coord.visualizer.armActivationRetry()
    }
    SettingsWindowPresenter.shared.stopFloating()
    NSWorkspace.shared.open(permission.settingsURL)
  }

  /// System Settings can change either permission while this window stays
  /// visible, so re-check every few seconds while the section is on screen.
  private func refreshWhileVisible() async {
    while !Task.isCancelled {
      await refresh()
      try? await Task.sleep(for: .seconds(3))
    }
  }

  private func refresh() async {
    let automationCheck = await Task.detached(priority: .utility) {
      SpotifyAppleEventsSource.permissionStatus(askUserIfNeeded: false)
    }.value
    automation = PermissionStatus(automation: automationCheck)
    screenRecording = ScreenRecordingCheck(
      allowed: ScreenRecordingAccess.isAllowed,
      requested: ScreenRecordingAccess.wasRequested())
  }
}

/// One permission: name, status in words with an icon, an optional note on
/// what that status means, and the System Settings button.
struct PermissionRow: View {
  let title: String
  let help: String
  let paneName: String
  let status: PermissionStatus?
  let note: String?
  let open: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(title)
            .font(SettingsType.rowTitle)
            .foregroundStyle(SettingsPalette.text)
            .lineLimit(1)
          SettingsHelpMark(help)
        }
        statusLine
        if let note {
          Text(note)
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      .help(help)
      .accessibilityElement(children: .combine)

      Spacer(minLength: 0)

      Button("Open System Settings", action: open)
        .buttonStyle(SettingsButtonStyle(prominent: status == .notAllowed))
        .help("Opens \(paneName) in System Settings.")
    }
  }

  private var statusLine: some View {
    HStack(spacing: 5) {
      if let status {
        DialIcon(status.icon)
          .frame(width: 11, height: 11)
          .accessibilityHidden(true)
        Text(status.label)
          .font(SettingsType.mono)
      } else {
        Text("Checking…")
          .font(SettingsType.caption)
      }
    }
    .foregroundStyle(statusColor)
  }

  private var statusColor: Color {
    switch status {
    case .allowed:          SettingsPalette.accent
    case .notAllowed:       SettingsPalette.text
    case .notAsked, .unknown, nil: SettingsPalette.muted
    }
  }
}
