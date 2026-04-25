// Dial/App/AppDelegate.swift
import AppKit
import Foundation
import GRDB

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var coordinator: AppCoordinator?
  private var statusBar: StatusBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let url = try DatabaseStack.defaultURL()
      let dbq = try DatabaseStack(url: url).dbq
      let clientID = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
      // DEBUG builds use a flat-file token store to avoid the macOS keychain
      // permission prompt that fires on every Xcode re-signed binary.
      // Release builds keep the keychain path (stable signature, real security).
      #if DEBUG
      let tokens: TokenStore = FileTokenStore()
      #else
      let tokens: TokenStore = KeychainTokenStore()
      #endif
      let auth = SpotifyAuthService(clientID: clientID, tokenStore: tokens)
      let client = SpotifyClient(tokenStore: tokens, refresh: { try await auth.refresh() })
      let coord = AppCoordinator(dbq: dbq, client: client, auth: auth, tokenStore: tokens)
      self.coordinator = coord
      self.statusBar = StatusBarController(coord: coord)

      // If a token's already in the keychain, start polling immediately.
      // Otherwise present Settings so the user can sign in — without a token,
      // polling would just churn 401s every 3 seconds.
      if coord.settings.signedIn {
        coord.start()
      } else {
        openSettings()
      }
    } catch {
      NSLog("[Dial] bootstrap failed: \(error)")
    }
  }

  /// Opens (or focuses) the SwiftUI Settings scene.
  private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    // macOS 14+: the Settings selector is `showSettingsWindow:`. On older macOS it's `showPreferencesWindow:`.
    let primary = Selector(("showSettingsWindow:"))
    let fallback = Selector(("showPreferencesWindow:"))
    if NSApp.responds(to: primary) {
      NSApp.sendAction(primary, to: nil, from: nil)
    } else {
      NSApp.sendAction(fallback, to: nil, from: nil)
    }
  }
}
