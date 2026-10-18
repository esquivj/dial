// Dial/Views/Settings/LastFMSettingsSection.swift
import SwiftUI
import AppKit

/// LAST.FM in General settings: API account, connection, scrobbling.
struct LastFMSettingsSection: View {
  @Bindable var vm: SettingsViewModel
  let lastFM: LastFMScrobbler

  @State private var showDisconnectAlert = false

  var body: some View {
    SettingsSection("LAST.FM") {
      VStack(alignment: .leading, spacing: SettingsLayout.rowGap) {
        connectionRow

        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
          LastFMSecretField(
            title: "API key",
            placeholder: "API key",
            help: "From your Last.fm API account (last.fm/api/account/create). Used for tags and scrobbling. Dial stores it in Keychain.",
            text: $vm.lastFMAPIKey)
          LastFMSecretField(
            title: "Shared secret",
            placeholder: "Shared secret",
            help: "Shown next to the API key on your Last.fm API account. Needed only for scrobbling. Dial stores it in Keychain.",
            text: $vm.lastFMSharedSecret)

          SettingsToggle(
            title: "Scrobble plays",
            detail: "Sends a play to Last.fm once you've heard half the song or 4 minutes. Songs you like in Dial are marked Loved.",
            isOn: Binding(
              get: { lastFM.scrobblingEnabled },
              set: { lastFM.scrobblingEnabled = $0 }))
            .disabled(lastFM.connection != .connected)
            .opacity(lastFM.connection == .connected ? 1 : 0.5)

          if lastFM.connection == .connected || lastFM.pendingCount > 0 || lastFM.lastScrobble != nil {
            statusLines
          }
        }
      }
    }
  }

  private var connectionRow: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(connectionTitle)
          .font(SettingsType.rowTitle)
          .foregroundStyle(SettingsPalette.text)
        Text(connectionDetail)
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      Spacer()
      connectionButton
    }
  }

  @ViewBuilder
  private var connectionButton: some View {
    switch lastFM.connection {
    case .connected:
      Button("Disconnect") { showDisconnectAlert = true }
        .buttonStyle(SettingsButtonStyle())
        .help("Stop scrobbling and forget this Last.fm account.")
        .alert("Disconnect from Last.fm?", isPresented: $showDisconnectAlert) {
          Button("Cancel", role: .cancel) {}
          Button("Disconnect", role: .destructive) { lastFM.disconnect() }
        } message: {
          Text("Dial will stop scrobbling. Plays already on Last.fm stay there.")
        }
    case .waitingForApproval:
      Button("Cancel") { lastFM.cancelConnect() }
        .buttonStyle(SettingsButtonStyle())
        .help("Stop waiting for Last.fm.")
    case .disconnected, .needsReconnect:
      Button("Connect") {
        lastFM.connect { NSWorkspace.shared.open($0) }
      }
      .buttonStyle(SettingsButtonStyle(prominent: true))
      .disabled(vm.lastFMCredentials == nil)
      .help("Opens Last.fm in your browser so you can allow Dial to scrobble.")
    }
  }

  private var connectionTitle: String {
    switch lastFM.connection {
    case .connected:          "Last.fm connected"
    case .waitingForApproval: "Waiting for Last.fm"
    case .needsReconnect:     "Last.fm disconnected"
    case .disconnected:       "Last.fm not connected"
    }
  }

  private var connectionDetail: String {
    switch lastFM.connection {
    case .connected:
      if let name = lastFM.username, !name.isEmpty { return "Signed in as \(name)." }
      return "Signed in."
    case .waitingForApproval:
      return "Allow Dial in your browser, then come back here."
    case .needsReconnect:
      return lastFM.problem ?? "Connect again to keep scrobbling."
    case .disconnected:
      if let problem = lastFM.problem { return problem }
      return vm.lastFMCredentials == nil
        ? "Add your API key and shared secret to connect."
        : "Connect to scrobble what you play."
    }
  }

  private var statusLines: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      VStack(alignment: .leading, spacing: 3) {
        Text(lastScrobbledLine(now: context.date))
        if lastFM.pendingCount > 0 {
          Text(lastFM.pendingCount == 1
               ? "1 play waiting to send."
               : "\(lastFM.pendingCount.formatted()) plays waiting to send.")
        }
        if lastFM.connection == .connected, let problem = lastFM.problem {
          Text(problem)
        }
      }
      .font(SettingsType.caption)
      .foregroundStyle(SettingsPalette.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func lastScrobbledLine(now: Date) -> String {
    guard let last = lastFM.lastScrobble else { return "Nothing scrobbled yet." }
    let when = Self.relative(Date(timeIntervalSince1970: TimeInterval(last.sentAt)), now: now)
    return "Last scrobbled: \(last.track) by \(last.artist), \(when)."
  }

  static func relative(_ date: Date, now: Date) -> String {
    let elapsed = max(0, now.timeIntervalSince(date))
    if elapsed < 60 { return "just now" }
    if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
    if elapsed < 86_400 { return "\(Int(elapsed / 3600))h ago" }
    return "\(Int(elapsed / 86_400))d ago"
  }
}

/// A labeled secure field, styled like the other Settings text fields.
private struct LastFMSecretField: View {
  let title: String
  let placeholder: String
  let help: String
  @Binding var text: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      HStack(spacing: 6) {
        Text(title)
          .font(SettingsType.rowTitle)
        SettingsHelpMark(help)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      Spacer()
      SecureField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(SettingsType.mono)
        .foregroundStyle(SettingsPalette.text)
        .padding(.horizontal, 9)
        .frame(width: SettingsLayout.textFieldWidth, height: 28)
        .background(SettingsPalette.control)
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
            .stroke(SettingsPalette.rule, lineWidth: 1))
        .help(help)
    }
    .frame(minHeight: 32)
    .help(help)
  }
}
