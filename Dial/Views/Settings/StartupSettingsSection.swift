// Dial/Views/Settings/StartupSettingsSection.swift
import SwiftUI
import AppKit
import ServiceManagement

/// STARTUP in General settings: launch at login. The switch shows macOS's
/// own login item status, so a change made in System Settings shows up here.
struct StartupSettingsSection: View {
  @State private var launchAtLogin: LaunchAtLogin

  /// Pass a `LaunchAtLogin` to show a fixed state; Settings uses the real one.
  @MainActor
  init(launchAtLogin: LaunchAtLogin? = nil) {
    _launchAtLogin = State(initialValue: launchAtLogin ?? LaunchAtLogin())
  }

  var body: some View {
    SettingsSection("STARTUP") {
      VStack(alignment: .leading, spacing: SettingsLayout.rowGap) {
        SettingsToggle(
          title: "Launch at login",
          detail: "Open Dial automatically when you log in to this Mac.",
          isOn: Binding(
            get: { launchAtLogin.isOn },
            set: { launchAtLogin.setOn($0) }))

        if launchAtLogin.needsApproval {
          approvalRow
        }

        if let problem = launchAtLogin.problem {
          Text(problem)
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .task { await refreshWhileVisible() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      launchAtLogin.refresh()
    }
  }

  private var approvalRow: some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(alignment: .top, spacing: 5) {
        // Top-aligned with a nudge so the icon stays on the first line if
        // the text wraps.
        DialIcon("exclamationmark.triangle")
          .frame(width: 11, height: 11)
          .padding(.top, 2)
          .accessibilityHidden(true)
        Text("Needs your approval in Login Items.")
          .font(SettingsType.caption)
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(SettingsPalette.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      .accessibilityElement(children: .combine)

      Spacer(minLength: 0)

      Button("Open Login Items") {
        SettingsWindowPresenter.shared.stopFloating()
        SMAppService.openSystemSettingsLoginItems()
      }
      .buttonStyle(SettingsButtonStyle(prominent: true))
      .help("Opens General › Login Items in System Settings, where you can allow Dial.")
    }
  }

  /// Someone can remove Dial from Login Items while this window stays
  /// visible, so re-read the status every few seconds while it's on screen.
  private func refreshWhileVisible() async {
    while !Task.isCancelled {
      launchAtLogin.refresh()
      try? await Task.sleep(for: .seconds(3))
    }
  }
}
