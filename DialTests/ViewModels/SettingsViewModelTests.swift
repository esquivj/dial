import XCTest
@testable import Dial

final class SettingsViewModelTests: XCTestCase {
  func test_hudColorModeDefaultsToFollowSound() throws {
    let defaults = freshDefaults()
    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .followSound)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.followSound.rawValue)
  }

  func test_hudColorModePreservesFollowSoundOnLaunch() throws {
    let defaults = freshDefaults()
    defaults.set(HUDColorMode.followSound.rawValue, forKey: "settings.hudColorMode")

    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .followSound)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.followSound.rawValue)
  }

  func test_hudColorModePreservesExplicitFixedThemeOnLaunch() throws {
    let defaults = freshDefaults()
    defaults.set(HUDColorMode.classic.rawValue, forKey: "settings.hudColorMode")

    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .classic)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.classic.rawValue)
  }

  func test_resetHUDDefaultsRestoresFollowSound() throws {
    let defaults = freshDefaults()
    defaults.set(HUDColorMode.classic.rawValue, forKey: "settings.hudColorMode")
    let vm = try makeSettings(defaults: defaults)

    vm.resetHUDDefaults()

    XCTAssertEqual(vm.hudColorMode, .followSound)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.followSound.rawValue)
  }

  func test_menuBarModeDefaultsToTrackArtist() throws {
    let defaults = freshDefaults()
    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.menuBarDisplayMode, .albumArtTrackArtist)
    XCTAssertEqual(defaults.string(forKey: "settings.menuBarDisplayMode"), MenuBarDisplayMode.albumArtTrackArtist.rawValue)
  }

  func test_menuBarModeMigratesRemovedTitlePlayCountToTrackArtist() throws {
    let defaults = freshDefaults()
    defaults.set(MenuBarDisplayMode.titlePlayCount.rawValue, forKey: "settings.menuBarDisplayMode")

    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.menuBarDisplayMode, .albumArtTrackArtist)
    XCTAssertEqual(defaults.string(forKey: "settings.menuBarDisplayMode"), MenuBarDisplayMode.albumArtTrackArtist.rawValue)
  }

  func test_lastFMAPIKeyMigratesLegacyDefaultsIntoSecretStore() throws {
    let defaults = freshDefaults()
    defaults.set("legacy-lastfm-key", forKey: "settings.lastFMAPIKey")
    let keyStore = InMemorySecretStringStore()

    let vm = try makeSettings(defaults: defaults, lastFMAPIKeyStore: keyStore)

    XCTAssertEqual(vm.lastFMAPIKey, "legacy-lastfm-key")
    XCTAssertEqual(try keyStore.load(), "legacy-lastfm-key")
    XCTAssertNil(defaults.string(forKey: "settings.lastFMAPIKey"))
  }

  func test_lastFMAPIKeyWritesToSecretStoreNotDefaults() throws {
    let defaults = freshDefaults()
    let keyStore = InMemorySecretStringStore()
    let vm = try makeSettings(defaults: defaults, lastFMAPIKeyStore: keyStore)

    vm.lastFMAPIKey = "new-lastfm-key"

    XCTAssertEqual(try keyStore.load(), "new-lastfm-key")
    XCTAssertNil(defaults.string(forKey: "settings.lastFMAPIKey"))
  }

  func test_lastFMAPIKeyClearsSecretStoreWhenBlank() throws {
    let defaults = freshDefaults()
    let keyStore = InMemorySecretStringStore()
    let vm = try makeSettings(defaults: defaults, lastFMAPIKeyStore: keyStore)
    vm.lastFMAPIKey = "new-lastfm-key"

    vm.lastFMAPIKey = "   "

    XCTAssertNil(try keyStore.load())
    XCTAssertNil(defaults.string(forKey: "settings.lastFMAPIKey"))
  }

  func test_markConnectionNeedsAttentionPreservesStoredToken() throws {
    let defaults = freshDefaults()
    let tokenStore = InMemoryTokenStore()
    try tokenStore.save(.init(accessToken: "access", refreshToken: "refresh", expiresAt: 123))
    let vm = try makeSettings(defaults: defaults, tokenStore: tokenStore)

    vm.markConnectionNeedsAttention()

    XCTAssertFalse(vm.signedIn)
    XCTAssertEqual(try tokenStore.load()?.refreshToken, "refresh")
  }

  private func makeSettings(
    defaults: UserDefaults,
    tokenStore: TokenStore = InMemoryTokenStore(),
    lastFMAPIKeyStore: SecretStringStore = InMemorySecretStringStore()
  ) throws -> SettingsViewModel {
    let auth = SpotifyAuthService(clientID: "settings-tests", tokenStore: tokenStore)
    return SettingsViewModel(
      auth: auth,
      dbq: try InMemoryDatabase.make(),
      tokenStore: tokenStore,
      lastFMAPIKeyStore: lastFMAPIKeyStore,
      defaults: defaults)
  }

  private func freshDefaults() -> UserDefaults {
    let suiteName = "Dial.SettingsViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}

private final class InMemorySecretStringStore: SecretStringStore {
  private var value: String?

  func save(_ value: String) throws {
    self.value = value
  }

  func load() throws -> String? {
    value
  }

  func clear() throws {
    value = nil
  }
}
