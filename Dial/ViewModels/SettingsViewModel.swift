// Dial/ViewModels/SettingsViewModel.swift
import Observation
import GRDB
import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
  case albumArtTitle
  case albumArtTrackArtist
  case iconOnly
  case petTitle
  case petOnly
  case titlePlayCount
  case tinyChaos

  static var allCases: [MenuBarDisplayMode] {
    [.albumArtTrackArtist, .albumArtTitle, .iconOnly]
  }

  var id: String { rawValue }

  var label: String {
    switch self {
    case .albumArtTitle:       "Album art + title"
    case .albumArtTrackArtist: "Art + track + artist"
    case .iconOnly:            "Icon only"
    case .petTitle:            "Pet + title"
    case .petOnly:             "Pet only"
    case .titlePlayCount:      "Title + plays"
    case .tinyChaos:           "Tiny chaos"
    }
  }

  var visiblePreset: MenuBarDisplayMode {
    switch self {
    case .petOnly, .tinyChaos:
      return .iconOnly
    case .petTitle, .titlePlayCount:
      return .albumArtTitle
    case .albumArtTitle, .albumArtTrackArtist, .iconOnly:
      return self
    }
  }
}

enum DefaultDropdownScreen: String, CaseIterable, Identifiable {
  case hud
  case pet
  case stats
  case history

  var id: String { rawValue }

  var label: String {
    switch self {
    case .hud:     "Now Playing"
    case .pet:     "Pet"
    case .stats:   "Stats"
    case .history: "History"
    }
  }

  var screen: DropdownScreen {
    switch self {
    case .hud:     .hud
    case .pet:     .pet
    case .stats:   .stats
    case .history: .history
    }
  }
}

enum DialAnimationLevel: String, CaseIterable, Identifiable {
  case low
  case normal
  case extra

  var id: String { rawValue }

  var label: String {
    switch self {
    case .low:    "Low"
    case .normal: "Normal"
    case .extra:  "Extra"
    }
  }
}

enum SpectrumStyle: String, CaseIterable, Identifiable {
  case precise
  case punchy

  var id: String { rawValue }

  var label: String {
    switch self {
    case .precise: "Precise"
    case .punchy:  "Punchy"
    }
  }
}

enum SpectrumDensity: String, CaseIterable, Identifiable {
  case compact
  case detailed
  case ultra

  var id: String { rawValue }

  var bandCount: Int {
    switch self {
    case .compact:  32
    case .detailed: 48
    case .ultra:    64
    }
  }

  var label: String {
    switch self {
    case .compact:  "32 bands"
    case .detailed: "48 bands"
    case .ultra:    "64 bands"
    }
  }
}

enum SpectrumMotion: String, CaseIterable, Identifiable {
  case fast
  case balanced
  case smooth

  var id: String { rawValue }

  var label: String {
    switch self {
    case .fast:     "Fast"
    case .balanced: "Balanced"
    case .smooth:   "Smooth"
    }
  }
}

@Observable
final class SettingsViewModel {
  let auth: SpotifyAuthService
  let dbq: DatabaseQueue
  private let tokenStore: TokenStore
  private let defaults: UserDefaults
  var signedIn: Bool
  var importProgress: Double = 0
  var lastImport: ImportLogEntry?

  var menuBarDisplayMode: MenuBarDisplayMode {
    didSet { defaults.set(menuBarDisplayMode.rawValue, forKey: Key.menuBarDisplayMode) }
  }
  var menuBarTitleWidth: Double {
    didSet { defaults.set(menuBarTitleWidth, forKey: Key.menuBarTitleWidth) }
  }
  var showAlbumArtInMenuBar: Bool {
    didSet { defaults.set(showAlbumArtInMenuBar, forKey: Key.showAlbumArtInMenuBar) }
  }
  var showProgressInMenuBar: Bool {
    didSet { defaults.set(showProgressInMenuBar, forKey: Key.showProgressInMenuBar) }
  }
  var flashOnTrackChange: Bool {
    didSet { defaults.set(flashOnTrackChange, forKey: Key.flashOnTrackChange) }
  }
  var showDockArtwork: Bool {
    didSet { defaults.set(showDockArtwork, forKey: Key.showDockArtwork) }
  }

  var defaultDropdownScreen: DefaultDropdownScreen {
    didSet { defaults.set(defaultDropdownScreen.rawValue, forKey: Key.defaultDropdownScreen) }
  }
  var showReadoutsInHUD: Bool {
    didSet { defaults.set(showReadoutsInHUD, forKey: Key.showReadoutsInHUD) }
  }
  var showBadgesInHUD: Bool {
    didSet { defaults.set(showBadgesInHUD, forKey: Key.showBadgesInHUD) }
  }
  var showVisualizerInHUD: Bool {
    didSet { defaults.set(showVisualizerInHUD, forKey: Key.showVisualizerInHUD) }
  }
  var showTransportInHUD: Bool {
    didSet { defaults.set(showTransportInHUD, forKey: Key.showTransportInHUD) }
  }
  var animationLevel: DialAnimationLevel {
    didSet { defaults.set(animationLevel.rawValue, forKey: Key.animationLevel) }
  }
  var hudHeroTitleSize: Double {
    didSet { defaults.set(hudHeroTitleSize, forKey: Key.hudHeroTitleSize) }
  }
  var hudHeroArtistSize: Double {
    didSet { defaults.set(hudHeroArtistSize, forKey: Key.hudHeroArtistSize) }
  }
  var hudHeroAlbumSize: Double {
    didSet { defaults.set(hudHeroAlbumSize, forKey: Key.hudHeroAlbumSize) }
  }
  var hudBadgeScale: Double {
    didSet { defaults.set(hudBadgeScale, forKey: Key.hudBadgeScale) }
  }
  var hudHeroMetadataGap: Double {
    didSet { defaults.set(hudHeroMetadataGap, forKey: Key.hudHeroMetadataGap) }
  }
  var hudHeroBadgeGap: Double {
    didSet { defaults.set(hudHeroBadgeGap, forKey: Key.hudHeroBadgeGap) }
  }

  var petEnabled: Bool {
    didSet { defaults.set(petEnabled, forKey: Key.petEnabled) }
  }
  var showPetInHUD: Bool {
    didSet { defaults.set(showPetInHUD, forKey: Key.showPetInHUD) }
  }
  var petFeedingAnimation: Bool {
    didSet { defaults.set(petFeedingAnimation, forKey: Key.petFeedingAnimation) }
  }
  var petFirstListenAnimation: Bool {
    didSet { defaults.set(petFirstListenAnimation, forKey: Key.petFirstListenAnimation) }
  }
  var petRediscoveryAnimation: Bool {
    didSet { defaults.set(petRediscoveryAnimation, forKey: Key.petRediscoveryAnimation) }
  }
  var petLevelUpAnimation: Bool {
    didSet { defaults.set(petLevelUpAnimation, forKey: Key.petLevelUpAnimation) }
  }

  var discoveryBadgesEnabled: Bool {
    didSet { defaults.set(discoveryBadgesEnabled, forKey: Key.discoveryBadgesEnabled) }
  }
  var patternBadgesEnabled: Bool {
    didSet { defaults.set(patternBadgesEnabled, forKey: Key.patternBadgesEnabled) }
  }
  var milestoneBadgesEnabled: Bool {
    didSet { defaults.set(milestoneBadgesEnabled, forKey: Key.milestoneBadgesEnabled) }
  }
  var spectrumStyle: SpectrumStyle {
    didSet { defaults.set(spectrumStyle.rawValue, forKey: Key.spectrumStyle) }
  }
  var spectrumDensity: SpectrumDensity {
    didSet { defaults.set(spectrumDensity.rawValue, forKey: Key.spectrumDensity) }
  }
  var spectrumMotion: SpectrumMotion {
    didSet { defaults.set(spectrumMotion.rawValue, forKey: Key.spectrumMotion) }
  }
  var spectrumPeakMarkers: Bool {
    didSet { defaults.set(spectrumPeakMarkers, forKey: Key.spectrumPeakMarkers) }
  }

  init(
    auth: SpotifyAuthService,
    dbq: DatabaseQueue,
    tokenStore: TokenStore,
    defaults: UserDefaults = .standard
  ) {
    self.auth = auth
    self.dbq = dbq
    self.tokenStore = tokenStore
    self.defaults = defaults
    self.menuBarDisplayMode = Self.enumValue(
      MenuBarDisplayMode.self, key: Key.menuBarDisplayMode, default: .albumArtTrackArtist, defaults: defaults
    ).visiblePreset
    self.menuBarTitleWidth = Self.doubleValue(
      Key.menuBarTitleWidth, default: MenuBarTextMetrics.defaultMaxWidth, defaults: defaults)
    self.showAlbumArtInMenuBar = Self.boolValue(Key.showAlbumArtInMenuBar, default: true, defaults: defaults)
    self.showProgressInMenuBar = Self.boolValue(Key.showProgressInMenuBar, default: false, defaults: defaults)
    self.flashOnTrackChange = Self.boolValue(Key.flashOnTrackChange, default: true, defaults: defaults)
    self.showDockArtwork = Self.boolValue(Key.showDockArtwork, default: true, defaults: defaults)

    self.defaultDropdownScreen = Self.enumValue(
      DefaultDropdownScreen.self, key: Key.defaultDropdownScreen, default: .hud, defaults: defaults)
    self.showReadoutsInHUD = Self.boolValue(Key.showReadoutsInHUD, default: true, defaults: defaults)
    self.showBadgesInHUD = Self.boolValue(Key.showBadgesInHUD, default: true, defaults: defaults)
    self.showVisualizerInHUD = Self.boolValue(Key.showVisualizerInHUD, default: true, defaults: defaults)
    self.showTransportInHUD = Self.boolValue(Key.showTransportInHUD, default: true, defaults: defaults)
    self.animationLevel = Self.enumValue(
      DialAnimationLevel.self, key: Key.animationLevel, default: .normal, defaults: defaults)
    self.hudHeroTitleSize = Self.doubleValue(
      Key.hudHeroTitleSize, default: 16, defaults: defaults)
    self.hudHeroArtistSize = Self.doubleValue(
      Key.hudHeroArtistSize, default: 13, defaults: defaults)
    self.hudHeroAlbumSize = Self.doubleValue(
      Key.hudHeroAlbumSize, default: 12, defaults: defaults)
    self.hudBadgeScale = Self.doubleValue(
      Key.hudBadgeScale, default: 1.0, defaults: defaults)
    self.hudHeroMetadataGap = Self.doubleValue(
      Key.hudHeroMetadataGap, default: 3, defaults: defaults)
    self.hudHeroBadgeGap = Self.doubleValue(
      Key.hudHeroBadgeGap, default: 5, defaults: defaults)

    self.petEnabled = Self.boolValue(Key.petEnabled, default: true, defaults: defaults)
    self.showPetInHUD = Self.boolValue(Key.showPetInHUD, default: true, defaults: defaults)
    self.petFeedingAnimation = Self.boolValue(Key.petFeedingAnimation, default: true, defaults: defaults)
    self.petFirstListenAnimation = Self.boolValue(Key.petFirstListenAnimation, default: true, defaults: defaults)
    self.petRediscoveryAnimation = Self.boolValue(Key.petRediscoveryAnimation, default: true, defaults: defaults)
    self.petLevelUpAnimation = Self.boolValue(Key.petLevelUpAnimation, default: true, defaults: defaults)

    self.discoveryBadgesEnabled = Self.boolValue(Key.discoveryBadgesEnabled, default: true, defaults: defaults)
    self.patternBadgesEnabled = Self.boolValue(Key.patternBadgesEnabled, default: true, defaults: defaults)
    self.milestoneBadgesEnabled = Self.boolValue(Key.milestoneBadgesEnabled, default: true, defaults: defaults)

    self.spectrumStyle = Self.enumValue(
      SpectrumStyle.self, key: Key.spectrumStyle, default: .precise, defaults: defaults)
    self.spectrumDensity = Self.enumValue(
      SpectrumDensity.self, key: Key.spectrumDensity, default: .detailed, defaults: defaults)
    self.spectrumMotion = Self.enumValue(
      SpectrumMotion.self, key: Key.spectrumMotion, default: .balanced, defaults: defaults)
    self.spectrumPeakMarkers = Self.boolValue(
      Key.spectrumPeakMarkers, default: true, defaults: defaults)

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

  func resetHUDTuningDefaults() {
    hudHeroTitleSize = 16
    hudHeroArtistSize = 13
    hudHeroAlbumSize = 12
    hudBadgeScale = 1.0
    hudHeroMetadataGap = 3
    hudHeroBadgeGap = 5
  }

  // MARK: - Defaults

  private enum Key {
    static let menuBarDisplayMode = "settings.menuBarDisplayMode"
    static let menuBarTitleWidth = "settings.menuBarTitleWidth"
    static let showAlbumArtInMenuBar = "settings.showAlbumArtInMenuBar"
    static let showProgressInMenuBar = "settings.showProgressInMenuBar"
    static let flashOnTrackChange = "settings.flashOnTrackChange"
    static let showDockArtwork = "settings.showDockArtwork"

    static let defaultDropdownScreen = "settings.defaultDropdownScreen"
    static let showReadoutsInHUD = "settings.showReadoutsInHUD"
    static let showBadgesInHUD = "settings.showBadgesInHUD"
    static let showVisualizerInHUD = "settings.showVisualizerInHUD"
    static let showTransportInHUD = "settings.showTransportInHUD"
    static let animationLevel = "settings.animationLevel"
    static let hudHeroTitleSize = "settings.hudHeroTitleSize"
    static let hudHeroArtistSize = "settings.hudHeroArtistSize"
    static let hudHeroAlbumSize = "settings.hudHeroAlbumSize"
    static let hudBadgeScale = "settings.hudBadgeScale"
    static let hudHeroMetadataGap = "settings.hudHeroMetadataGap"
    static let hudHeroBadgeGap = "settings.hudHeroBadgeGap"

    static let petEnabled = "settings.petEnabled"
    static let showPetInHUD = "settings.showPetInHUD"
    static let petFeedingAnimation = "settings.petFeedingAnimation"
    static let petFirstListenAnimation = "settings.petFirstListenAnimation"
    static let petRediscoveryAnimation = "settings.petRediscoveryAnimation"
    static let petLevelUpAnimation = "settings.petLevelUpAnimation"

    static let discoveryBadgesEnabled = "settings.discoveryBadgesEnabled"
    static let patternBadgesEnabled = "settings.patternBadgesEnabled"
    static let milestoneBadgesEnabled = "settings.milestoneBadgesEnabled"

    static let spectrumStyle = "settings.spectrumStyle"
    static let spectrumDensity = "settings.spectrumDensity"
    static let spectrumMotion = "settings.spectrumMotion"
    static let spectrumPeakMarkers = "settings.spectrumPeakMarkers"
  }

  private static func boolValue(
    _ key: String,
    default defaultValue: Bool,
    defaults: UserDefaults
  ) -> Bool {
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return defaults.bool(forKey: key)
  }

  private static func doubleValue(
    _ key: String,
    default defaultValue: Double,
    defaults: UserDefaults
  ) -> Double {
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return defaults.double(forKey: key)
  }

  private static func enumValue<T: RawRepresentable>(
    _ type: T.Type,
    key: String,
    default defaultValue: T,
    defaults: UserDefaults
  ) -> T where T.RawValue == String {
    guard
      let raw = defaults.string(forKey: key),
      let value = T(rawValue: raw)
    else { return defaultValue }
    return value
  }
}
