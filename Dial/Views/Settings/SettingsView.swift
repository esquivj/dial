import SwiftUI
import AppKit

/// Hosted by the SwiftUI `Settings` scene in `DialApp` (added in Task 43).
/// `onImport` is invoked after the user picks a folder via `NSOpenPanel`;
/// the caller (DialApp) does the actual EndsongFile parsing + Importer call.
struct SettingsView: View {
  @Bindable var vm: SettingsViewModel
  let onImport: (URL) -> Void

  var body: some View {
    Form {
      Section("Spotify account") {
        if vm.signedIn {
          Button("Disconnect") { /* hooked up in Task 43 — wires KeychainTokenStore.clear */ }
        } else {
          Button("Connect Spotify") { Task { try? await vm.auth.signIn() } }
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
