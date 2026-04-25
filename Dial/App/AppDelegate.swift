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
      let tokens = KeychainTokenStore()
      let auth = SpotifyAuthService(clientID: clientID, tokenStore: tokens)
      let client = SpotifyClient(tokenStore: tokens, refresh: { try await auth.refresh() })
      let coord = AppCoordinator(dbq: dbq, client: client, auth: auth)
      coord.start()
      self.coordinator = coord
      self.statusBar = StatusBarController(coord: coord)
    } catch {
      NSLog("[Dial] bootstrap failed: \(error)")
    }
  }
}
