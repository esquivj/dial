// Dial/ViewModels/SettingsViewModel.swift
import Observation
import GRDB

@Observable
final class SettingsViewModel {
  let auth: SpotifyAuthService
  let dbq: DatabaseQueue
  var signedIn: Bool = false
  var importProgress: Double = 0
  var lastImport: ImportLogEntry?
  init(auth: SpotifyAuthService, dbq: DatabaseQueue) {
    self.auth = auth
    self.dbq = dbq
  }
}
