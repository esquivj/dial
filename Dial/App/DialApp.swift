import SwiftUI

/// Bootstrap entry point. Replaced in Task 43 with the
/// `NSStatusItem` + `NSPopover` wiring driven by `AppCoordinator`.
@main
struct DialApp: App {
  var body: some Scene {
    Settings {
      VStack(spacing: 12) {
        Text("Dial")
          .font(.title)
        Text("Bootstrap build — menubar wiring lands in Task 43.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(32)
      .frame(width: 360, height: 160)
    }
  }
}
