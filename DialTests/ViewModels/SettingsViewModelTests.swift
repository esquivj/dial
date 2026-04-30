import XCTest
@testable import Dial

final class SettingsViewModelTests: XCTestCase {
  func test_hudColorModeDefaultsToSmokeGel() throws {
    let defaults = freshDefaults()
    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .classic)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.classic.rawValue)
    XCTAssertTrue(defaults.bool(forKey: "settings.didMigrateSmokeGelDefault"))
  }

  func test_hudColorModeMigratesOldFollowSoundDefaultToSmokeGelOnce() throws {
    let defaults = freshDefaults()
    defaults.set(HUDColorMode.followSound.rawValue, forKey: "settings.hudColorMode")

    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .classic)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.classic.rawValue)
    XCTAssertTrue(defaults.bool(forKey: "settings.didMigrateSmokeGelDefault"))
  }

  func test_hudColorModePreservesFollowSoundAfterMigrationRan() throws {
    let defaults = freshDefaults()
    defaults.set(true, forKey: "settings.didMigrateSmokeGelDefault")
    defaults.set(HUDColorMode.followSound.rawValue, forKey: "settings.hudColorMode")

    let vm = try makeSettings(defaults: defaults)

    XCTAssertEqual(vm.hudColorMode, .followSound)
    XCTAssertEqual(defaults.string(forKey: "settings.hudColorMode"), HUDColorMode.followSound.rawValue)
  }

  private func makeSettings(defaults: UserDefaults) throws -> SettingsViewModel {
    let tokenStore = InMemoryTokenStore()
    let auth = SpotifyAuthService(clientID: "settings-tests", tokenStore: tokenStore)
    return SettingsViewModel(
      auth: auth,
      dbq: try InMemoryDatabase.make(),
      tokenStore: tokenStore,
      defaults: defaults)
  }

  private func freshDefaults() -> UserDefaults {
    let suiteName = "Dial.SettingsViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
