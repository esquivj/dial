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
