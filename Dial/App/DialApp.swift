// Dial/App/DialApp.swift
import SwiftUI

@main
struct DialApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      if let coord = appDelegate.coordinator {
        SettingsView(
          vm: coord.settings,
          onSignIn: { try? await coord.signIn() },
          onImport: { folder in
            Task { await runImport(coord: coord, from: folder) }
          }
        )
      } else {
        Text("Dial — initializing…")
          .padding(40)
      }
    }

    // History and Stats are opened programmatically via WindowsManager
    // (see AppCoordinator.windows). They can't be SwiftUI `Window` scenes
    // because the dropdown lives in an NSPopover, outside the scene tree
    // where `@Environment(\.openWindow)` resolves.
  }

  private func runImport(coord: AppCoordinator, from folder: URL) async {
    let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    let endsongs = urls.filter {
      let n = $0.lastPathComponent
      return n.hasPrefix("endsong_") || n.hasPrefix("Streaming_History_Audio_")
    }
    let importer = Importer(dbq: coord.dbq, engine: coord.engine)
    for f in endsongs {
      if let rows = try? EndsongFile.parse(at: f) {
        _ = try? importer.importBatch(rows, sourcePath: f.path)
      }
    }
  }
}
