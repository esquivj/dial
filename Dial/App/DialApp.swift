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
          coord: coord,
          onSignIn: { try? await coord.signIn() },
          onImport: { folder in
            Task { await coord.importHistory(from: folder) }
          }
        )
      } else {
        ProgressView("Starting Dial…")
          .frame(width: 700, height: 540)
      }
    }
    .defaultSize(width: 700, height: 540)
    .windowResizability(.contentSize)

    // History and Stats are opened programmatically via WindowsManager
    // (see AppCoordinator.windows). They can't be SwiftUI `Window` scenes
    // because the dropdown lives in an NSPopover, outside the scene tree
    // where `@Environment(\.openWindow)` resolves.
  }
}
