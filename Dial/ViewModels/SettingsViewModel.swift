// Dial/ViewModels/SettingsViewModel.swift
import Observation
import GRDB

@Observable
final class SettingsViewModel {
  let auth: SpotifyAuthService
  let dbq: DatabaseQueue
  private let tokenStore: TokenStore
  var signedIn: Bool
  var importProgress: Double = 0
  var lastImport: ImportLogEntry?

  init(auth: SpotifyAuthService, dbq: DatabaseQueue, tokenStore: TokenStore) {
    self.auth = auth
    self.dbq = dbq
    self.tokenStore = tokenStore
    // Read keychain once on launch so the UI reflects sign-in state immediately.
    self.signedIn = ((try? tokenStore.load()) ?? nil) != nil
  }

  /// Flip after a successful `auth.signIn()`.
  func markSignedIn() { signedIn = true }

  /// Clear the keychain token and flip the flag. Used by the Disconnect button.
  func markSignedOut() {
    try? tokenStore.clear()
    signedIn = false
  }
}
