import AuthenticationServices
import GRDB
import XCTest
@testable import Dial

/// PLA-103: Settings says why a sign-in failed, and remembers the last
/// history import across relaunches.
final class SettingsSilentFailureTests: XCTestCase {
  // MARK: Sign-in errors

  func test_cancelledSignIn_saysNothing() {
    let cancel = ASWebAuthenticationSessionError(.canceledLogin)
    XCTAssertNil(SignInFailure.message(for: cancel))
  }

  func test_failureMessages_areShortAndSayWhy() {
    XCTAssertEqual(SignInFailure.message(for: SpotifyAuthError.tokenEndpointStatus(400)),
                   "Spotify turned down the sign-in (error 400). Try again.")
    XCTAssertEqual(SignInFailure.message(for: URLError(.notConnectedToInternet)),
                   "Couldn't reach Spotify. Check your connection and try again.")
    XCTAssertEqual(SignInFailure.message(for: NSError(domain: "Dial.Auth", code: 1)),
                   "Sign-in didn't finish. Try again.")
    XCTAssertEqual(SignInFailure.message(for: NSError(domain: "Other", code: 9)),
                   "Sign-in failed. Try again.")
  }

  func test_settingsKeepsTheReasonUntilTheNextSuccessfulSignIn() throws {
    let vm = try makeSettings(dbq: InMemoryDatabase.make())
    vm.recordSignInFailure(URLError(.timedOut))
    XCTAssertEqual(vm.signInError, "Couldn't reach Spotify. Check your connection and try again.")

    vm.recordSignInFailure(ASWebAuthenticationSessionError(.canceledLogin))
    XCTAssertNil(vm.signInError, "closing the window clears the old reason")

    vm.recordSignInFailure(SpotifyAuthError.invalidResponse)
    vm.markSignedIn()
    XCTAssertNil(vm.signInError)
  }

  // MARK: Import status

  func test_importSummary_nilWhenNothingWasImported() throws {
    XCTAssertNil(try ImportsLogDAO(dbq: InMemoryDatabase.make()).summary())
  }

  func test_importSummary_survivesARelaunch() throws {
    let dbq = try InMemoryDatabase.make()
    try seedImport(dbq, at: 1_777_313_372, plays: 3)

    // A fresh SettingsViewModel is what a relaunch builds.
    let vm = try makeSettings(dbq: dbq)
    let summary = try XCTUnwrap(vm.importSummary)
    XCTAssertEqual(summary.importedPlays, 3)
    XCTAssertEqual(summary.lastImportedAt, 1_777_313_372)
    XCTAssertEqual(summary.folderName, "Spotify Extended Streaming History")
  }

  func test_importSummary_countsImportedPlaysOnly() throws {
    let dbq = try InMemoryDatabase.make()
    try seedImport(dbq, at: 1_777_313_372, plays: 2)
    try dbq.write { db in
      try db.execute(sql: "INSERT INTO plays (played_at, track_uri, ms_played, source) VALUES (1, 'L', 200000, 'live')")
    }
    XCTAssertEqual(try ImportsLogDAO(dbq: dbq).summary()?.importedPlays, 2)
  }

  func test_importSubtitle() {
    let en = Locale(identifier: "en_US")
    let utc = TimeZone(identifier: "UTC")!
    XCTAssertEqual(GeneralSettingsTab.importSubtitle(nil, locale: en, timeZone: utc), "No history folder imported.")
    XCTAssertEqual(
      GeneralSettingsTab.importSubtitle(
        ImportSummary(lastImportedAt: 1_777_313_372, folderName: "History", importedPlays: 192_564),
        locale: en, timeZone: utc),
      "Last import Apr 27, 2026 · 192,564 plays")
    XCTAssertEqual(
      GeneralSettingsTab.importSubtitle(
        ImportSummary(lastImportedAt: nil, folderName: nil, importedPlays: 1), locale: en, timeZone: utc),
      "1 play imported")
  }

  // MARK: Helpers

  private func seedImport(_ dbq: DatabaseQueue, at: Int64, plays: Int) throws {
    try dbq.write { db in
      for i in 0..<plays {
        try db.execute(
          sql: "INSERT INTO plays (played_at, track_uri, ms_played, source) VALUES (?, ?, 200000, 'import')",
          arguments: [1_600_000_000 + i, "T\(i)"])
      }
      try db.execute(
        sql: "INSERT INTO imports_log (imported_at, source_path, rows_inserted) VALUES (?, ?, ?)",
        arguments: [at, "/Users/someone/Downloads/Spotify Extended Streaming History/Streaming_History_Audio_2026.json", plays])
    }
  }

  private func makeSettings(dbq: DatabaseQueue) throws -> SettingsViewModel {
    let tokenStore = InMemoryTokenStore()
    return SettingsViewModel(
      auth: SpotifyAuthService(clientID: "pla-103-tests", tokenStore: tokenStore),
      dbq: dbq,
      tokenStore: tokenStore,
      lastFMAPIKeyStore: MemorySecret(),
      lastFMSharedSecretStore: MemorySecret(),
      defaults: UserDefaults(suiteName: "Dial.PLA103.\(UUID().uuidString)")!)
  }
}

private final class MemorySecret: SecretStringStore {
  private var value: String?
  func save(_ value: String) throws { self.value = value }
  func load() throws -> String? { value }
  func clear() throws { value = nil }
}
