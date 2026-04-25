// Dial/Views/Settings/SettingsView.swift
import SwiftUI
import AppKit

/// Hosted by the SwiftUI `Settings` scene in `DialApp`.
/// `onSignIn` runs the full coordinator-level sign-in (auth → mark signed in → start polling).
/// `onImport` is invoked after the user picks a folder via `NSOpenPanel`.
struct SettingsView: View {
  @Bindable var vm: SettingsViewModel
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  var body: some View {
    Form {
      Section("Spotify account") {
        if vm.signedIn {
          Button("Disconnect") { vm.markSignedOut() }
        } else {
          Button("Connect Spotify") { Task { await onSignIn() } }
        }
      }
      Section("History import") {
        if vm.importProgress > 0, vm.importProgress < 1 {
          ProgressView(value: vm.importProgress)
        }
        Button("Choose folder…") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          if panel.runModal() == .OK, let url = panel.url { onImport(url) }
        }
        if let last = vm.lastImport {
          Text("Last import: \(last.rowsInserted) rows")
            .font(Dial.Typography.sansCaption)
        }
      }
      Section("About") {
        Text("Dial 0.1").foregroundStyle(Dial.Palette.muted)
      }
    }
    .padding(20)
    .frame(width: 400)
  }
}
