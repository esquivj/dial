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

enum HUDSettingsPreset: String, CaseIterable, Identifiable {
  case balanced
  case minimal
  case dense
  case performance
  case showOff

  var id: String { rawValue }

  var label: String {
    switch self {
    case .balanced:    "Balanced"
    case .minimal:     "Minimal"
    case .dense:       "Dense"
    case .performance: "Performance"
    case .showOff:     "Show-off"
    }
  }

  var detail: String {
    switch self {
    case .balanced:    "Default Dial feel."
    case .minimal:     "Quieter Now Playing."
    case .dense:       "More data, less air."
    case .performance: "Less live motion."
    case .showOff:     "Maximum motion and detail."
    }
  }
}

enum HUDColorMode: String, CaseIterable, Identifiable {
  case followSound
  case classic
  case slime
  case aqua
  case ember

  var id: String { rawValue }

  var label: String {
    switch self {
    case .followSound: "Follow Sound"
    case .classic:     "Classic"
    case .slime:       "Slime"
    case .aqua:        "Aqua"
    case .ember:       "Magenta"
    }
  }

  var previewTheme: DialThemeID {
    switch self {
    case .followSound: .slime
    case .classic:     .classic
    case .slime:       .slime
    case .aqua:        .aqua
    case .ember:       .ember
    }
  }

  func resolvedTheme(soundTheme: DialThemeID) -> DialThemeID {
    switch self {
    case .followSound: soundTheme
    case .classic:     .classic
    case .slime:       .slime
    case .aqua:        .aqua
    case .ember:       .ember
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
    didSet {
      let clamped = MenuBarTextMetrics.clampedSettingWidth(menuBarTitleWidth)
      if clamped != menuBarTitleWidth {
        menuBarTitleWidth = clamped
        return
      }
      defaults.set(menuBarTitleWidth, forKey: Key.menuBarTitleWidth)
    }
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
  var hudColorMode: HUDColorMode {
    didSet { defaults.set(hudColorMode.rawValue, forKey: Key.hudColorMode) }
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
  var backgroundEnrichmentEnabled: Bool {
    didSet { defaults.set(backgroundEnrichmentEnabled, forKey: Key.backgroundEnrichmentEnabled) }
  }
  var lastFMTagEnrichmentEnabled: Bool {
    didSet { defaults.set(lastFMTagEnrichmentEnabled, forKey: Key.lastFMTagEnrichmentEnabled) }
  }
  var lastFMAPIKey: String {
    didSet { defaults.set(lastFMAPIKey, forKey: Key.lastFMAPIKey) }
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
    self.menuBarTitleWidth = MenuBarTextMetrics.clampedSettingWidth(Self.doubleValue(
      Key.menuBarTitleWidth, default: MenuBarTextMetrics.defaultMaxWidth, defaults: defaults))
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
    self.hudColorMode = Self.enumValue(
      HUDColorMode.self, key: Key.hudColorMode, default: .followSound, defaults: defaults)
    self.hudHeroTitleSize = Self.doubleValue(
      Key.hudHeroTitleSize, default: 15, defaults: defaults)
    self.hudHeroArtistSize = Self.doubleValue(
      Key.hudHeroArtistSize, default: 12, defaults: defaults)
    self.hudHeroAlbumSize = Self.doubleValue(
      Key.hudHeroAlbumSize, default: 11, defaults: defaults)
    self.hudBadgeScale = Self.doubleValue(
      Key.hudBadgeScale, default: 1.0, defaults: defaults)
    self.hudHeroMetadataGap = Self.doubleValue(
      Key.hudHeroMetadataGap, default: 2, defaults: defaults)
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
    self.backgroundEnrichmentEnabled = Self.boolValue(
      Key.backgroundEnrichmentEnabled, default: true, defaults: defaults)
    self.lastFMTagEnrichmentEnabled = Self.boolValue(
      Key.lastFMTagEnrichmentEnabled, default: false, defaults: defaults)
    self.lastFMAPIKey = defaults.string(forKey: Key.lastFMAPIKey) ?? ""

    // Read keychain once on launch so the UI reflects sign-in state immediately.
    self.signedIn = ((try? tokenStore.load()) ?? nil) != nil
    defaults.set(self.menuBarTitleWidth, forKey: Key.menuBarTitleWidth)
  }

  /// Flip after a successful `auth.signIn()`.
  func markSignedIn() { signedIn = true }

  /// Clear the keychain token and flip the flag. Used by the Disconnect button.
  func markSignedOut() {
    try? tokenStore.clear()
    signedIn = false
  }

  func resetMenuBarDefaults() {
    menuBarDisplayMode = .albumArtTrackArtist
    menuBarTitleWidth = MenuBarTextMetrics.defaultMaxWidth
    showAlbumArtInMenuBar = true
    showProgressInMenuBar = false
    flashOnTrackChange = true
    showDockArtwork = true
  }

  func resetHUDDefaults() {
    defaultDropdownScreen = .hud
    showReadoutsInHUD = true
    showBadgesInHUD = true
    showVisualizerInHUD = true
    showTransportInHUD = true
    animationLevel = .normal
    hudColorMode = .followSound
    discoveryBadgesEnabled = true
    patternBadgesEnabled = true
    milestoneBadgesEnabled = true
    spectrumStyle = .precise
    spectrumDensity = .detailed
    spectrumMotion = .balanced
    spectrumPeakMarkers = true
    resetHUDTuningDefaults()
  }

  func resetPetDefaults() {
    petEnabled = true
    showPetInHUD = true
    petFeedingAnimation = true
    petFirstListenAnimation = true
    petRediscoveryAnimation = true
    petLevelUpAnimation = true
  }

  func resetAllSettings() {
    resetMenuBarDefaults()
    resetHUDDefaults()
    resetPetDefaults()
  }

  func resetHUDTuningDefaults() {
    hudHeroTitleSize = 15
    hudHeroArtistSize = 12
    hudHeroAlbumSize = 11
    hudBadgeScale = 1.0
    hudHeroMetadataGap = 2
    hudHeroBadgeGap = 5
  }

  func applyHUDPreset(_ preset: HUDSettingsPreset) {
    switch preset {
    case .balanced:
      resetHUDDefaults()

    case .minimal:
      defaultDropdownScreen = .hud
      showReadoutsInHUD = true
      showBadgesInHUD = true
      showVisualizerInHUD = false
      showTransportInHUD = true
      animationLevel = .low
      discoveryBadgesEnabled = true
      patternBadgesEnabled = true
      milestoneBadgesEnabled = true
      spectrumStyle = .precise
      spectrumDensity = .compact
      spectrumMotion = .smooth
      spectrumPeakMarkers = false
      hudHeroTitleSize = 14
      hudHeroArtistSize = 11
      hudHeroAlbumSize = 10
      hudBadgeScale = 0.95
      hudHeroMetadataGap = 2
      hudHeroBadgeGap = 4

    case .dense:
      defaultDropdownScreen = .hud
      showReadoutsInHUD = true
      showBadgesInHUD = true
      showVisualizerInHUD = true
      showTransportInHUD = true
      animationLevel = .normal
      discoveryBadgesEnabled = true
      patternBadgesEnabled = true
      milestoneBadgesEnabled = true
      spectrumStyle = .precise
      spectrumDensity = .ultra
      spectrumMotion = .balanced
      spectrumPeakMarkers = true
      hudHeroTitleSize = 14
      hudHeroArtistSize = 11
      hudHeroAlbumSize = 10
      hudBadgeScale = 0.95
      hudHeroMetadataGap = 2
      hudHeroBadgeGap = 4

    case .performance:
      defaultDropdownScreen = .hud
      showReadoutsInHUD = true
      showBadgesInHUD = true
      showVisualizerInHUD = false
      showTransportInHUD = true
      animationLevel = .low
      discoveryBadgesEnabled = true
      patternBadgesEnabled = true
      milestoneBadgesEnabled = true
      spectrumStyle = .precise
      spectrumDensity = .compact
      spectrumMotion = .fast
      spectrumPeakMarkers = false
      hudHeroTitleSize = 15
      hudHeroArtistSize = 12
      hudHeroAlbumSize = 11
      hudBadgeScale = 1.0
      hudHeroMetadataGap = 2
      hudHeroBadgeGap = 5

    case .showOff:
      defaultDropdownScreen = .hud
      showReadoutsInHUD = true
      showBadgesInHUD = true
      showVisualizerInHUD = true
      showTransportInHUD = true
      animationLevel = .extra
      discoveryBadgesEnabled = true
      patternBadgesEnabled = true
      milestoneBadgesEnabled = true
      spectrumStyle = .punchy
      spectrumDensity = .ultra
      spectrumMotion = .fast
      spectrumPeakMarkers = true
      hudHeroTitleSize = 16
      hudHeroArtistSize = 13
      hudHeroAlbumSize = 12
      hudBadgeScale = 1.1
      hudHeroMetadataGap = 3
      hudHeroBadgeGap = 6
    }
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
    static let hudColorMode = "settings.hudColorMode"
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
    static let backgroundEnrichmentEnabled = "settings.backgroundEnrichmentEnabled"
    static let lastFMTagEnrichmentEnabled = "settings.lastFMTagEnrichmentEnabled"
    static let lastFMAPIKey = "settings.lastFMAPIKey"
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
