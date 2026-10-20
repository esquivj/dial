import AppKit
import GRDB
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Dial

@MainActor
final class VisualRegressionTests: XCTestCase {
  func test_exportCurrentHUDThemeScreensForMarketing() async throws {
    let outputDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("MarketingAssets/XReady/generated", isDirectory: true)
    let exportFlag = outputDirectory
      .deletingLastPathComponent()
      .appendingPathComponent(".export-current-hud")
    guard FileManager.default.fileExists(atPath: exportFlag.path) else {
      throw XCTSkip("Create MarketingAssets/XReady/.export-current-hud to export transparent HUD screens.")
    }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for themeID in DialThemeID.allCases {
      let coord = try makeMarketingCoordinator(themeID: themeID)
      _ = await coord.artworkCache.load(coord.nowPlaying.track?.artUrl)
      let visibility = DropdownVisibility()
      visibility.isVisible = true
      let view = DropdownView(coord: coord, visibility: visibility)
        .preferredColorScheme(.dark)

      let image = try render(view, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height))
      let data = try pngData(for: image)
      try data.write(
        to: outputDirectory.appendingPathComponent("dial-hud-\(themeID.rawValue)-transparent.png"),
        options: .atomic)
    }

    for config in marketingMenubarConfigs {
      let coord = try makeMarketingCoordinator(themeID: config.themeID)
      _ = await coord.artworkCache.load(coord.nowPlaying.track?.artUrl)
      coord.settings.menuBarDisplayMode = config.mode
      coord.settings.showProgressInMenuBar = config.showProgress
      coord.settings.menuBarTitleWidth = config.titleWidth
      coord.pet.stage = config.petStage
      coord.menubar.playsYTD = config.plays
      coord.nowPlaying.playsYTD = config.plays
      let view = MenubarStripView(
        vm: coord.menubar,
        settings: coord.settings,
        pet: coord.pet,
        nowPlaying: coord.nowPlaying,
        artworkCache: coord.artworkCache)
        .frame(width: 360, height: 44, alignment: .leading)
        .preferredColorScheme(.dark)

      let image = try render(view, size: CGSize(width: 360, height: 44))
      let data = try pngData(for: image)
      try data.write(
        to: outputDirectory.appendingPathComponent("dial-menubar-\(config.name)-transparent.png"),
        options: .atomic)
    }
  }

  func test_mainHUDScreenshotsRenderForEveryThemeCartridge() async throws {
    for themeID in DialThemeID.allCases {
      let context = try makeSnapshotContext(themeID: themeID)
      let theme = DialTheme.palette(for: themeID)
      let view = MainHUDSnapshotHarness(context: context)
        .environment(\.dialTheme, theme)
        .preferredColorScheme(.dark)

      let image = try render(view, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height))
      let snapshotName = "dial-hud-\(themeID.rawValue)"
      try attach(image, name: snapshotName)
      try assertMatchesBaseline(image, name: snapshotName)

      XCTAssertGreaterThan(opaquePixelCount(in: image), 40_000, "\(themeID.rawValue) HUD rendered blank.")
      XCTAssertGreaterThan(
        accentPixelCount(in: image, expected: expectedAccent(for: themeID)),
        700,
        "\(themeID.rawValue) HUD lost its cartridge accent.")
    }
  }

  func test_menuBarSettingsSurfaceRendersSelectedPreviewState() throws {
    let context = try makeSnapshotContext(themeID: .aqua)
    context.settings.menuBarDisplayMode = .albumArtTrackArtist
    context.settings.showAlbumArtInMenuBar = true
    context.settings.showProgressInMenuBar = true
    context.settings.menuBarTitleWidth = 168

    let view = SettingsMenuBarSnapshotHarness(settings: context.settings)
      .preferredColorScheme(.dark)
    let image = try render(view, size: CGSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight))
    let snapshotName = "dial-settings-menubar"
    try attach(image, name: snapshotName)
    try assertMatchesBaseline(image, name: snapshotName)

    XCTAssertGreaterThan(opaquePixelCount(in: image), 70_000, "Menu bar settings screen rendered blank.")
  }

  func test_transportButtonGeometryKeepsButtonsCenteredInsidePNGWells() {
    let regular = TransportHardware.buttonSize(prominent: false)
    let play = TransportHardware.buttonSize(prominent: true)

    XCTAssertEqual((TransportHardware.transportSize.width - regular.width) / 2, 1.25, accuracy: 0.001)
    XCTAssertEqual((TransportHardware.transportSize.height - regular.height) / 2, 1.25, accuracy: 0.001)
    XCTAssertEqual((TransportHardware.playSize.width - play.width) / 2, 1.25, accuracy: 0.001)
    XCTAssertEqual((TransportHardware.playSize.height - play.height) / 2, 1.25, accuracy: 0.001)

    let innerRowWidth: CGFloat = 318
    let clusterWidth = TransportHardware.transportSize.width
      + TransportHardware.centralSpacing
      + TransportHardware.playSize.width
      + TransportHardware.centralSpacing
      + TransportHardware.transportSize.width
    let clusterMinX = (innerRowWidth - clusterWidth) / 2
    let previousCenter = clusterMinX + TransportHardware.transportSize.width / 2
    let playCenter = clusterMinX + TransportHardware.transportSize.width
      + TransportHardware.centralSpacing
      + TransportHardware.playSize.width / 2
    let nextCenter = clusterMinX + TransportHardware.transportSize.width
      + TransportHardware.centralSpacing
      + TransportHardware.playSize.width
      + TransportHardware.centralSpacing
      + TransportHardware.transportSize.width / 2

    XCTAssertEqual(playCenter, innerRowWidth / 2, accuracy: 0.001)
    XCTAssertEqual(playCenter - previousCenter, nextCenter - playCenter, accuracy: 0.001)
  }

  /// The track-change memory pop-up in the default Smoke Gel theme, on a
  /// light desktop so the bezel edge is checked where it's hardest to see.
  func test_memoryPopupRendersReadoutStrip() throws {
    let content = MemoryPopupContent(
      kind: .rediscovered,
      label: "REDISCOVERED",
      line: "Last played Mar 2023",
      trackName: "Kiss Me Thru the Phone",
      artistName: "Soulja Boy")
    let size = CGSize(width: MemoryPopupView.size.width + 40, height: MemoryPopupView.size.height + 40)
    let view = ZStack {
      Color(red: 0.86, green: 0.87, blue: 0.89)
      MemoryPopupView(content: content, onOpen: {})
    }
    .environment(\.dialTheme, .classic)
    .preferredColorScheme(.dark)

    let image = try render(view, size: size)
    let snapshotName = "dial-memory-popup"
    try attach(image, name: snapshotName)
    try assertMatchesBaseline(image, name: snapshotName)
  }

  /// The hotkey confirmation flash: the memory pop-up's strip on one line.
  /// Play (primary), liked (memory pink) and volume (accent + meter) cover
  /// every tone and both layouts.
  func test_hotkeyFlashRendersOneLineStrip() throws {
    let flash = HotkeyFlashView.size
    let size = CGSize(width: flash.width + 40, height: flash.height * 3 + 16 + 40)
    let view = ZStack {
      Color(red: 0.86, green: 0.87, blue: 0.89)
      VStack(spacing: 8) {
        HotkeyFlashView(content: .play)
        HotkeyFlashView(content: .liked)
        HotkeyFlashView(content: .volume(45))
      }
    }
    .environment(\.dialTheme, .classic)
    .preferredColorScheme(.dark)

    let image = try render(view, size: size)
    let snapshotName = "dial-hotkey-flash"
    try attach(image, name: snapshotName)
    try assertMatchesBaseline(image, name: snapshotName)
  }

  /// Every desktop memory state from docs/design/desktop-memory.md. The top
  /// row sits on a light desktop, the bottom on a dark one, so the chassis
  /// edge and contact shadow are checked on both.
  func test_desktopMemoryRendersStates() throws {
    let art = NSImage(contentsOf: try StateGridFixtures.makeArtworkFile())
    let soulja = DesktopMemoryContent.Track(
      uri: "spotify:track:soulja", name: "Kiss Me Thru the Phone", artistName: "Soulja Boy", artUrl: "fixture")
    let frank = DesktopMemoryContent.Track(
      uri: "spotify:track:frank", name: "Pink + White", artistName: "Frank Ocean", artUrl: "fixture")
    let long = DesktopMemoryContent.Track(
      uri: "spotify:track:long", name: "Everything In Its Right Place (Live in Paris, 2001)",
      artistName: "Radiohead", artUrl: nil)
    let rediscovered = DesktopMemoryContent.Stamp.memory(
      kind: .rediscovered, label: "REDISCOVERED", line: "Last played Mar 2023")

    typealias Cell = (content: DesktopMemoryContent, artwork: NSImage?, theme: DialTheme)
    let light: [Cell] = [
      (.init(playback: .playing, stamp: rediscovered, track: soulja), art, .classic),
      (.init(playback: .playing,
             stamp: .memory(kind: .firstListen, label: "FIRST LISTEN", line: "New to your history"),
             track: frank), art, .classic),
      (.init(playback: .playing, stamp: .yearToDate(plays: 12), track: soulja), art, .classic),
      (.init(playback: .paused,
             stamp: .memory(kind: .play50, label: "50TH PLAY", line: "50th lifetime play today"),
             track: soulja), art, .classic),
    ]
    let dark: [Cell] = [
      (.init(playback: .notPlaying, stamp: .notPlaying, track: soulja), art, .classic),
      (.init(playback: .notPlaying, stamp: .notPlaying, track: nil), nil, .classic),
      (.init(playback: .playing, stamp: .yearToDate(plays: 0), track: long), nil, .classic),
      (.init(playback: .playing, stamp: rediscovered, track: soulja), art, .aqua),
    ]

    let cell = DesktopMemoryMetrics.windowSize
    func row(_ cells: [Cell], desktop: Color) -> some View {
      HStack(spacing: 0) {
        ForEach(cells.indices, id: \.self) { index in
          DesktopMemoryView(content: cells[index].content, artwork: cells[index].artwork, onOpen: {})
            .environment(\.dialTheme, cells[index].theme)
            .frame(width: cell.width, height: cell.height)
        }
      }
      .background(desktop)
    }
    let view = VStack(spacing: 0) {
      row(light, desktop: Color(red: 0.86, green: 0.87, blue: 0.89))
      row(dark, desktop: Color(red: 0.11, green: 0.12, blue: 0.14))
    }
    .preferredColorScheme(.dark)

    let size = CGSize(width: cell.width * 4, height: cell.height * 2)
    let image = try render(view, size: size)
    let snapshotName = "dial-desktop-memory"
    try attach(image, name: snapshotName)
    try assertMatchesBaseline(image, name: snapshotName)
  }

  func test_petScreenRendersCompactLivingMemoryLog() throws {
    let context = try makeSnapshotContext(themeID: .slime)
    let memories = try seedWeeklyMemoryLog(in: context.dbq)
    let artifacts = try ArtifactsDAO(dbq: context.dbq).syncFromMemoriesAndTricks()
    let petState = PetState(
      id: 1,
      xp: 36_800,
      stage: .companion,
      hatchedAt: nil,
      lastPlayAt: Int64(Date().timeIntervalSince1970) - 480,
      streakDays: 9,
      streakAnchorDate: nil,
      elderUnlockedAt: nil,
      installedAt: Int64(Date().timeIntervalSince1970) - 18 * 86_400)

    context.settings.livingMemoriesEnabled = true
    context.pet.stage = .companion
    context.pet.xp = petState.xp
    context.pet.streakDays = petState.streakDays
    context.pet.behavior = .beatSync(bpm: 126)
    context.menubar.state = .playing
    context.agg.currentBadgeInsight = BadgeInsight(
      kind: .rediscovered,
      detail: "REDISCOVERED",
      explanation: "Fixture keeps the room action and badge response visible.")

    let view = PetScreenSnapshotHarness(
      context: context,
      memories: memories,
      artifacts: artifacts,
      petState: petState)
      .preferredColorScheme(.dark)

    let image = try render(view, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height))
    let snapshotName = "dial-pet-memory-log"
    try attach(image, name: snapshotName)
    try assertMatchesBaseline(image, name: snapshotName)

    XCTAssertGreaterThan(opaquePixelCount(in: image), 40_000, "Pet screen rendered blank.")
    XCTAssertGreaterThan(
      accentPixelCount(in: image, expected: expectedAccent(for: .slime)),
      600,
      "Pet screen lost its slime memory accent.")
  }

  func test_petScreenLivingMemoryStackStaysInsideHardwareShellPlate() {
    let contentPadding = Dial.Layout.PetScreen.contentPadding.top
      + Dial.Layout.PetScreen.contentPadding.bottom
    let visibleRows = Dial.Layout.PetScreen.companionPanelHeight
      + Dial.Layout.PetScreen.weeklyMemoryHeight
      + Dial.Layout.PetScreen.memoryShelfHeight
      + Dial.Layout.PetScreen.evolutionHeight
    let visibleGaps = Dial.Layout.PetScreen.contentSpacing * 3
    let requiredHeight = contentPadding + visibleRows + visibleGaps
    let availableHeight = Dial.Layout.SecondaryShell.plateHeight
      - Dial.Layout.PetScreen.shellSafetyInset

    XCTAssertLessThanOrEqual(
      requiredHeight,
      availableHeight,
      "Pet screen overfills the hardware-shell plate. Merge or remove a row instead of stacking another shelf."
    )
  }

  func test_statsScreenRendersWeeklyMemorySignal() throws {
    let context = try makeSnapshotContext(themeID: .classic)
    let now = Int64(Date().timeIntervalSince1970)
    let bounds = StatsQueries.weekBounds(containing: now)
    let memory = StatsQueries.WeeklyMemorySnapshot(
      weekStart: bounds.start,
      weekEnd: bounds.end,
      trait: "Pulsebound",
      memento: "Signal Cube",
      recapLine: "The week leaned into electronic pressure.",
      roomObjectName: "stereo",
      dominantGenre: "electronic",
      theme: .slime,
      playCount: 12,
      listeningMs: 2_160_000,
      uniqueArtists: 4,
      newArtists: 1)
    try WeeklyMemoriesDAO(dbq: context.dbq, now: { now }).upsert(memory, now: now)
    let snapshot = StatsViewSnapshot(
      totals: StatsQueries.Totals(
        plays: 12,
        listeningMs: 2_160_000,
        uniqueTracks: 8,
        uniqueArtists: 4),
      topTracks: [],
      topArtists: [],
      topGenres: [],
      weeklyMemory: memory,
      rhythmBuckets: [],
      badgeSummaries: [],
      recentBadges: [])

    let view = StatsView(
      dbq: context.dbq,
      artworkCache: context.artworkCache,
      initialSnapshot: snapshot,
      onBack: {},
      placement: .hardwareShell)
      .environment(\.dialTheme, DialTheme.classic)
      .preferredColorScheme(.dark)

    let image = try render(view, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height))

    XCTAssertNotNil(snapshot.weeklyMemory)
    XCTAssertGreaterThan(opaquePixelCount(in: image), 35_000, "Stats screen rendered blank.")
  }

  /// Renders every HUD and menu bar state in `StateGridFixtures` to
  /// `.build/state-grid/` plus a full-size contact sheet. Skipped unless
  /// `.build/state-grid/.render` exists; `scripts/dev.sh grid` creates it.
  func test_renderStateGrid() async throws {
    let outputDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/state-grid", isDirectory: true)
    guard FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent(".render").path) else {
      throw XCTSkip("Run scripts/dev.sh grid to render the state grid.")
    }
    let fixtures = StateGridFixtures(
      artworkURL: try StateGridFixtures.makeArtworkFile().absoluteString,
      now: fixtureNow)

    var hudTiles: [StateGridTile] = []
    for state in StateGridFixtures.hudStates {
      let coord = try makeStateGridCoordinator()
      state.configure(coord, fixtures)
      _ = await coord.artworkCache.load(coord.nowPlaying.track?.artUrl)
      let visibility = DropdownVisibility()
      visibility.isVisible = true
      let view = DropdownView(coord: coord, visibility: visibility)
        .environment(\._accessibilityReduceMotion, state.reduceMotion)
        .preferredColorScheme(.dark)
      let size = CGSize(width: DropdownLayout.width, height: DropdownLayout.height)
      let image = state.needsHostingView ? try renderHosted(view, size: size) : try render(view, size: size)
      try pngData(for: image).write(to: outputDirectory.appendingPathComponent("\(state.name).png"), options: .atomic)
      hudTiles.append(StateGridTile(name: state.name, caption: state.caption, section: state.section, image: image))
    }

    var menubarTiles: [StateGridTile] = []
    for state in StateGridFixtures.menubarStates {
      let coord = try makeStateGridCoordinator()
      state.configure(coord, fixtures)
      coord.settings.menuBarDisplayMode = state.mode
      coord.settings.showAlbumArtInMenuBar = true
      coord.settings.showProgressInMenuBar = true
      coord.settings.menuBarTitleWidth = 220
      coord.nowPlaying.soundTheme = state.themeID
      _ = await coord.artworkCache.load(coord.nowPlaying.track?.artUrl)
      for scheme in [ColorScheme.dark, .light] {
        let view = MenubarGridBar(scheme: scheme) {
          MenubarStripView(
            vm: coord.menubar,
            settings: coord.settings,
            pet: coord.pet,
            nowPlaying: coord.nowPlaying,
            artworkCache: coord.artworkCache)
        }
        .environment(\._accessibilityReduceMotion, state.reduceMotion)
        // preferredColorScheme doesn't reach the environment inside
        // ImageRenderer; a real status item gets it from the menu bar.
        .environment(\.colorScheme, scheme)
        let image = try render(view, size: menubarGridBarSize)
        let name = "\(state.name)-\(scheme == .dark ? "dark" : "light")-bar"
        try pngData(for: image).write(to: outputDirectory.appendingPathComponent("\(name).png"), options: .atomic)
        menubarTiles.append(StateGridTile(
          name: name,
          caption: "\(state.caption) · \(scheme == .dark ? "dark" : "light") menu bar",
          section: "Menu bar strip",
          image: image))
      }
    }

    let sheet = StateGridSheet(hudTiles: hudTiles, menubarTiles: menubarTiles)
    let renderer = ImageRenderer(content: sheet)
    renderer.scale = 2
    guard let sheetImage = renderer.cgImage else {
      XCTFail("Could not render the state-grid contact sheet.")
      return
    }
    try pngData(for: sheetImage).write(to: outputDirectory.appendingPathComponent("contact-sheet.png"), options: .atomic)
  }

  /// Offscreen NSHostingView render at 2x. Slower than ImageRenderer but it
  /// draws ScrollView content, which ImageRenderer leaves blank on macOS.
  private func renderHosted<V: View>(_ view: V, size: CGSize) throws -> CGImage {
    let frozen = Date(timeIntervalSince1970: TimeInterval(fixtureNow))
    let hosting = NSHostingView(rootView: view
      .frame(width: size.width, height: size.height)
      .environment(\.dialFrozenDate, frozen))
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = hosting
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    for _ in 0..<5 {
      hosting.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw NSError(domain: "Dial.VisualRegression", code: 4) }
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let image = rep.cgImage else { throw NSError(domain: "Dial.VisualRegression", code: 5) }
    return image
  }

  /// AppCoordinator with an in-memory DB and throwaway defaults, so grid
  /// renders never write into the real app's settings.
  private func makeStateGridCoordinator() throws -> AppCoordinator {
    let dbq = try InMemoryDatabase.make()
    let tokenStore = SnapshotTokenStore()
    let auth = SpotifyAuthService(clientID: "state-grid", tokenStore: tokenStore)
    let client = SpotifyClient(tokenStore: tokenStore, refresh: { try tokenStore.requireToken() })
    return AppCoordinator(
      dbq: dbq,
      client: client,
      auth: auth,
      tokenStore: tokenStore,
      defaults: UserDefaults(suiteName: "Dial.StateGrid.\(UUID().uuidString)")!)
  }

  private func makeSnapshotContext(themeID: DialThemeID) throws -> SnapshotContext {
    let dbq = try InMemoryDatabase.make()
    let tokenStore = SnapshotTokenStore()
    let auth = SpotifyAuthService(clientID: "visual-regression", tokenStore: tokenStore)
    let client = SpotifyClient(tokenStore: tokenStore, refresh: { try tokenStore.requireToken() })
    let agg = AggregationsCache(agg: PlayAggregations(dbq: dbq))
    let nowPlaying = NowPlayingViewModel(agg: agg)
    let menubar = MenubarStripViewModel()
    let pet = PetViewModel()
    let settings = SettingsViewModel(
      auth: auth,
      dbq: dbq,
      tokenStore: tokenStore,
      defaults: UserDefaults(suiteName: "Dial.VisualRegression.\(UUID().uuidString)")!)
    let visualizer = VisualizerEngine()

    let track = NowPlayingViewModel.Track(
      uri: "spotify:track:visual-\(themeID.rawValue)",
      name: "Signal Drift",
      artistName: "Dial Test",
      artistUri: "spotify:artist:visual",
      artistUris: ["spotify:artist:visual"],
      albumName: "Hardware Memory",
      artUrl: nil)

    settings.signedIn = true
    settings.showReadoutsInHUD = true
    settings.showBadgesInHUD = true
    settings.showVisualizerInHUD = true
    settings.showTransportInHUD = true
    settings.showPetInHUD = true
    settings.petEnabled = true
    settings.animationLevel = .low
    settings.hudColorMode = .followSound

    nowPlaying.track = track
    nowPlaying.soundTheme = themeID
    nowPlaying.soundThemeDecision = SoundThemeDecision(
      theme: themeID,
      confidence: 0.92,
      source: .artistTags,
      reason: "Visual regression fixture")
    nowPlaying.playsYTD = 8
    menubar.track = track
    menubar.state = .playing
    menubar.durationMs = 212_000
    menubar.progressMs = 91_000
    menubar.lastProgressUpdate = nil
    menubar.likedTrackState = .notLiked
    menubar.playsYTD = 8
    pet.stage = .companion
    pet.behavior = .beatSync(bpm: 128)
    pet.reactionText = "Listening."
    visualizer.configure(style: .precise, density: .detailed, motion: .balanced, showPeakMarkers: true)
    visualizer.setPreviewSpectrum(bands: [
      0.82, 0.74, 0.69, 0.78, 0.62, 0.58, 0.66, 0.54,
      0.50, 0.47, 0.52, 0.49, 0.44, 0.46, 0.43, 0.41,
      0.39, 0.38, 0.37, 0.42, 0.40, 0.36, 0.34, 0.33,
      0.35, 0.31, 0.29, 0.30, 0.28, 0.27, 0.26, 0.25,
      0.24, 0.23, 0.22, 0.24, 0.20, 0.19, 0.18, 0.20,
      0.17, 0.16, 0.18, 0.15, 0.14, 0.13, 0.12, 0.11,
    ])

    return SnapshotContext(
      dbq: dbq,
      client: client,
      agg: agg,
      nowPlaying: nowPlaying,
      menubar: menubar,
      pet: pet,
      settings: settings,
      artworkCache: ArtworkCache(),
      visualizer: visualizer)
  }

  private func makeMarketingCoordinator(themeID: DialThemeID) throws -> AppCoordinator {
    let dbq = try InMemoryDatabase.make()
    let tokenStore = SnapshotTokenStore()
    let auth = SpotifyAuthService(clientID: "x-export", tokenStore: tokenStore)
    let client = SpotifyClient(tokenStore: tokenStore, refresh: { try tokenStore.requireToken() })
    let coord = AppCoordinator(dbq: dbq, client: client, auth: auth, tokenStore: tokenStore)

    let track = NowPlayingViewModel.Track(
      uri: "spotify:track:x-export-\(themeID.rawValue)",
      name: marketingTrackName(for: themeID),
      artistName: marketingArtistName(for: themeID),
      artistUri: "spotify:artist:x-export",
      artistUris: ["spotify:artist:x-export"],
      albumName: marketingAlbumName(for: themeID),
      artUrl: marketingArtworkURL)

    coord.settings.signedIn = true
    coord.settings.showReadoutsInHUD = true
    coord.settings.showBadgesInHUD = true
    coord.settings.showVisualizerInHUD = true
    coord.settings.showTransportInHUD = true
    coord.settings.showPetInHUD = true
    coord.settings.petEnabled = true
    coord.settings.animationLevel = .low
    coord.settings.hudColorMode = HUDColorMode(rawValue: themeID.rawValue) ?? .classic
    coord.dropdownScreen = .hud

    coord.nowPlaying.track = track
    coord.nowPlaying.soundTheme = themeID
    coord.nowPlaying.soundThemeDecision = SoundThemeDecision(
      theme: themeID,
      confidence: 0.94,
      source: .artistTags,
      reason: "Marketing export")
    coord.nowPlaying.playsYTD = marketingPlays(for: themeID)
    coord.aggCache.rank7d = marketingRank(for: themeID)
    coord.aggCache.lastPlayedAt = marketingLastPlayedAt(for: themeID)
    coord.aggCache.firstListen = false
    coord.aggCache.rediscovered = false
    coord.aggCache.currentBadgeInsight = marketingBadgeInsight(for: themeID)
    coord.menubar.track = track
    coord.menubar.state = .playing
    coord.menubar.durationMs = marketingDurationMs(for: themeID)
    coord.menubar.progressMs = marketingProgressMs(for: themeID)
    coord.menubar.lastProgressUpdate = nil
    coord.menubar.likedTrackState = .notLiked
    coord.menubar.playsYTD = marketingPlays(for: themeID)
    coord.pet.stage = marketingPetStage(for: themeID)
    coord.pet.behavior = .beatSync(bpm: 124)
    coord.pet.reactionText = "Listening."
    coord.visualizer.configure(style: .precise, density: .detailed, motion: .balanced, showPeakMarkers: true)
    coord.visualizer.setPreviewSpectrum(bands: marketingSpectrum(for: themeID))

    return coord
  }

  /// Fixed "now" for fixtures that render dates, so baselines don't drift with
  /// the calendar. Wed 2026-05-20 12:00 local time (the baselines' week of MAY 18).
  private var fixtureNow: Int64 {
    let components = DateComponents(year: 2026, month: 5, day: 20, hour: 12)
    return Int64(Calendar(identifier: .gregorian).date(from: components)!.timeIntervalSince1970)
  }

  private func seedWeeklyMemoryLog(in dbq: DatabaseQueue) throws -> [WeeklyMemoryRecord] {
    let now = fixtureNow
    let currentBounds = StatsQueries.weekBounds(containing: now)
    let dao = WeeklyMemoriesDAO(dbq: dbq, now: { now })
    let fixtures: [(String, String, String, String, String?, DialThemeID, Int, Int64, Int, Int)] = [
      (
        "Nocturnal",
        "Moonlit Tape",
        "Late-night plays kept the room awake.",
        "moonlit_tape",
        "electronic",
        .slime,
        42,
        6_840_000,
        18,
        4
      ),
      (
        "Loyal",
        "Repeat Charm",
        "One artist kept looping back into the week.",
        "repeat_charm",
        "latin",
        .classic,
        31,
        5_220_000,
        9,
        1
      ),
      (
        "Curious",
        "Fresh Sticker",
        "New artists left bright stickers on the shelf.",
        "fresh_sticker",
        "pop",
        .aqua,
        27,
        4_680_000,
        21,
        8
      ),
      (
        "Deep-Cut",
        "Signal Cube",
        "Rare tracks kept glowing under the screen.",
        "signal_cube",
        "underground",
        .ember,
        19,
        3_240_000,
        16,
        3
      ),
    ]

    for (index, fixture) in fixtures.enumerated() {
      let bounds = weekBounds(offset: index, from: currentBounds)
      let snapshot = StatsQueries.WeeklyMemorySnapshot(
        weekStart: bounds.start,
        weekEnd: bounds.end,
        trait: fixture.0,
        memento: fixture.1,
        recapLine: fixture.2,
        roomObjectName: fixture.3,
        dominantGenre: fixture.4,
        theme: fixture.5,
        playCount: fixture.6,
        listeningMs: fixture.7,
        uniqueArtists: fixture.8,
        newArtists: fixture.9)
      try dao.upsert(snapshot, now: now)
    }

    return try dao.recent(limit: fixtures.count)
  }

  private func weekBounds(
    offset: Int,
    from currentBounds: (start: Int64, end: Int64)
  ) -> (start: Int64, end: Int64) {
    guard offset > 0 else { return currentBounds }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let currentStart = Date(timeIntervalSince1970: TimeInterval(currentBounds.start))
    let shifted = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart) ?? currentStart
    return StatsQueries.weekBounds(containing: Int64(shifted.timeIntervalSince1970))
  }

  private func marketingTrackName(for themeID: DialThemeID) -> String {
    "Too Many Nights"
  }

  private func marketingArtistName(for themeID: DialThemeID) -> String {
    "Metro Boomin & Future"
  }

  private func marketingAlbumName(for themeID: DialThemeID) -> String {
    "HEROES & VILLAINS"
  }

  private func marketingPlays(for themeID: DialThemeID) -> Int {
    27
  }

  private func marketingRank(for themeID: DialThemeID) -> Int? {
    7
  }

  private func marketingLastPlayedAt(for themeID: DialThemeID) -> Int64? {
    Int64(Date().timeIntervalSince1970)
  }

  private func marketingBadgeInsight(for themeID: DialThemeID) -> BadgeInsight {
    BadgeInsight(kind: .deepCut, detail: "DEEP CUT", explanation: "A rare track in this listener's rotation.")
  }

  private func marketingDurationMs(for themeID: DialThemeID) -> Int {
    switch themeID {
    case .classic: 206_000
    case .slime:   184_000
    case .aqua:    212_000
    case .ember:   239_000
    }
  }

  private func marketingProgressMs(for themeID: DialThemeID) -> Int {
    switch themeID {
    case .classic: 87_000
    case .slime:   61_000
    case .aqua:    91_000
    case .ember:   146_000
    }
  }

  private func marketingPetStage(for themeID: DialThemeID) -> PetStage {
    .companion
  }

  private var marketingArtworkURL: String {
    "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/82/f7/2b/82f72ba4-524c-fc9d-cb8c-5a96d2ddf536/22UM1IM35267.rgb.jpg/600x600bb.jpg"
  }

  private func marketingSpectrum(for themeID: DialThemeID) -> [Float] {
    let base: [Float]
    switch themeID {
    case .classic:
      base = [0.64, 0.58, 0.52, 0.48, 0.55, 0.50, 0.46, 0.42]
    case .slime:
      base = [0.78, 0.82, 0.68, 0.71, 0.58, 0.62, 0.53, 0.49]
    case .aqua:
      base = [0.82, 0.74, 0.69, 0.78, 0.62, 0.58, 0.66, 0.54]
    case .ember:
      base = [0.48, 0.54, 0.76, 0.88, 0.70, 0.62, 0.57, 0.51]
    }
    return (0..<48).map { index in
      let decay = max(0.16, 1.0 - Float(index) * 0.016)
      let pulse = base[index % base.count]
      return min(0.92, max(0.10, pulse * decay))
    }
  }

  private var marketingMenubarConfigs: [MarketingMenubarConfig] {
    [
      .init(
        name: "track",
        themeID: .classic,
        mode: .albumArtTrackArtist,
        titleWidth: 190,
        showProgress: false,
        petStage: .companion,
        plays: 3),
      .init(
        name: "pet",
        themeID: .slime,
        mode: .petTitle,
        titleWidth: 132,
        showProgress: false,
        petStage: .juvenile,
        plays: 12),
      .init(
        name: "icon",
        themeID: .aqua,
        mode: .iconOnly,
        titleWidth: 80,
        showProgress: false,
        petStage: .hatchling,
        plays: 8),
      .init(
        name: "plays",
        themeID: .ember,
        mode: .titlePlayCount,
        titleWidth: 150,
        showProgress: false,
        petStage: .elder,
        plays: 27),
    ]
  }

  private func render<V: View>(_ view: V, size: CGSize) throws -> CGImage {
    let frozen = Date(timeIntervalSince1970: TimeInterval(fixtureNow))
    let renderer = ImageRenderer(content: view
      .frame(width: size.width, height: size.height)
      .environment(\.dialFrozenDate, frozen))
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 2
    renderer.isOpaque = false
    guard let cgImage = renderer.cgImage else {
      throw NSError(domain: "Dial.VisualRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render snapshot."])
    }
    return cgImage
  }

  private func attach(_ image: CGImage, name: String) throws {
    let data = try pngData(for: image)
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func pngData(for image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else {
      throw NSError(domain: "Dial.VisualRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination."])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "Dial.VisualRegression", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG."])
    }
    return data as Data
  }

  private func assertMatchesBaseline(
    _ image: CGImage,
    name: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let directory = snapshotDirectory
    let url = directory.appendingPathComponent("\(name).png")
    let data = try pngData(for: image)

    if shouldRecordVisualSnapshots {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      return
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
      XCTFail("Missing visual baseline: \(url.path). Re-record with DIAL_RECORD_VISUAL_SNAPSHOTS=1.", file: file, line: line)
      return
    }
    let baselineData = try Data(contentsOf: url)
    guard let baseline = cgImage(from: baselineData) else {
      XCTFail("Could not decode visual baseline: \(url.path)", file: file, line: line)
      return
    }

    guard image.width == baseline.width, image.height == baseline.height else {
      XCTFail(
        "\(name) size drifted from \(baseline.width)x\(baseline.height) to \(image.width)x\(image.height).",
        file: file,
        line: line
      )
      return
    }
    guard let actualBytes = rgbaBytes(from: image),
          let baselineBytes = rgbaBytes(from: baseline),
          actualBytes.count == baselineBytes.count
    else {
      XCTFail("Could not read pixels for \(name).", file: file, line: line)
      return
    }

    var differentPixels = 0
    var totalDelta = 0
    let pixelCount = image.width * image.height
    for idx in stride(from: 0, to: actualBytes.count, by: 4) {
      let redDelta = abs(Int(actualBytes[idx]) - Int(baselineBytes[idx]))
      let greenDelta = abs(Int(actualBytes[idx + 1]) - Int(baselineBytes[idx + 1]))
      let blueDelta = abs(Int(actualBytes[idx + 2]) - Int(baselineBytes[idx + 2]))
      let alphaDelta = abs(Int(actualBytes[idx + 3]) - Int(baselineBytes[idx + 3]))
      let delta = redDelta + greenDelta + blueDelta + alphaDelta
      totalDelta += delta
      if delta > 12 {
        differentPixels += 1
      }
    }

    let differentRatio = Double(differentPixels) / Double(pixelCount)
    let meanChannelDelta = Double(totalDelta) / Double(pixelCount * 4)
    if differentRatio > 0.002 || meanChannelDelta > 0.15 {
      writeFailureArtifacts(actual: data, baseline: baselineData, name: name)
    }
    XCTAssertLessThanOrEqual(
      differentRatio,
      0.002,
      "\(name) drifted: \(differentPixels) pixels differ (\(differentRatio)).",
      file: file,
      line: line
    )
    XCTAssertLessThanOrEqual(
      meanChannelDelta,
      0.15,
      "\(name) drifted: mean channel delta \(meanChannelDelta).",
      file: file,
      line: line
    )
  }

  private var snapshotDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Snapshots/VisualRegression", isDirectory: true)
  }

  /// Drops the rendered and expected PNGs into `.build/snapshot-failures/` so a
  /// failing snapshot can be inspected without digging through the .xcresult.
  private func writeFailureArtifacts(actual: Data, baseline: Data, name: String) {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/snapshot-failures", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? actual.write(to: directory.appendingPathComponent("\(name).actual.png"), options: .atomic)
    try? baseline.write(to: directory.appendingPathComponent("\(name).baseline.png"), options: .atomic)
  }

  private var shouldRecordVisualSnapshots: Bool {
    ProcessInfo.processInfo.environment["DIAL_RECORD_VISUAL_SNAPSHOTS"] == "1"
      || FileManager.default.fileExists(atPath: snapshotDirectory.appendingPathComponent(".record").path)
  }

  private func cgImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private func opaquePixelCount(in image: CGImage) -> Int {
    guard let bytes = rgbaBytes(from: image) else { return 0 }
    return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 20 ? 1 : 0) }
  }

  private func accentPixelCount(in image: CGImage, expected: RGB) -> Int {
    guard let bytes = rgbaBytes(from: image) else { return 0 }
    var count = 0
    for idx in stride(from: 0, to: bytes.count, by: 4) {
      let r = Int(bytes[idx])
      let g = Int(bytes[idx + 1])
      let b = Int(bytes[idx + 2])
      let a = bytes[idx + 3]
      guard a > 80 else { continue }
      let distance = abs(r - expected.r) + abs(g - expected.g) + abs(b - expected.b)
      if distance < 95 { count += 1 }
    }
    return count
  }

  private func rgbaBytes(from image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
      data: &bytes,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
  }

  private func expectedAccent(for themeID: DialThemeID) -> RGB {
    switch themeID {
    case .slime: return RGB(184, 255, 56)
    case .aqua: return RGB(37, 199, 255)
    case .ember: return RGB(255, 77, 210)
    case .classic: return RGB(242, 242, 238)
    }
  }
}

private struct SnapshotContext {
  let dbq: DatabaseQueue
  let client: SpotifyClient
  let agg: AggregationsCache
  let nowPlaying: NowPlayingViewModel
  let menubar: MenubarStripViewModel
  let pet: PetViewModel
  let settings: SettingsViewModel
  let artworkCache: ArtworkCache
  let visualizer: VisualizerEngine
}

private struct MarketingMenubarConfig {
  let name: String
  let themeID: DialThemeID
  let mode: MenuBarDisplayMode
  let titleWidth: Double
  let showProgress: Bool
  let petStage: PetStage
  let plays: Int
}

private struct StateGridTile {
  let name: String
  let caption: String
  let section: String
  let image: CGImage
}

/// A slice of menu bar: the strip sits on a dark or light bar the way it
/// would on a dark or light desktop.
private let menubarGridBarSize = CGSize(width: 440, height: 28)

private struct MenubarGridBar<Content: View>: View {
  let scheme: ColorScheme
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: 0) {
      content()
        .fixedSize()
      Spacer(minLength: 0)
    }
    .padding(.leading, 12)
    .frame(width: menubarGridBarSize.width, height: menubarGridBarSize.height)
    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
  }
}

/// Light-background contact sheet. Tiles render at 1:1 point size (2x pixels).
private struct StateGridSheet: View {
  let hudTiles: [StateGridTile]
  let menubarTiles: [StateGridTile]

  private let columns = 4
  private let gap: CGFloat = 28

  private var sections: [(String, [StateGridTile])] {
    var order: [String] = []
    var bySection: [String: [StateGridTile]] = [:]
    for tile in hudTiles {
      if bySection[tile.section] == nil { order.append(tile.section) }
      bySection[tile.section, default: []].append(tile)
    }
    return order.map { ($0, bySection[$0] ?? []) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 36) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Dial · state grid")
          .font(.system(size: 30, weight: .semibold))
        Text("Rendered by scripts/dev.sh grid · fixture date Wed 2026-05-20 · every tile at 1:1 size")
          .font(.system(size: 15))
          .foregroundStyle(Color.black.opacity(0.55))
      }
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        sectionView(title: section.0) {
          let rows = stride(from: 0, to: section.1.count, by: columns).map {
            Array(section.1[$0..<min($0 + columns, section.1.count)])
          }
          VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
              HStack(alignment: .top, spacing: gap) {
                ForEach(row, id: \.name) { tile in
                  tileView(tile, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height))
                }
              }
            }
          }
        }
      }
      sectionView(title: "Menu bar strip") {
        let pairs = stride(from: 0, to: menubarTiles.count, by: 2).map {
          Array(menubarTiles[$0..<min($0 + 2, menubarTiles.count)])
        }
        VStack(alignment: .leading, spacing: 18) {
          ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
            HStack(alignment: .top, spacing: gap) {
              ForEach(pair, id: \.name) { tile in
                tileView(tile, size: menubarGridBarSize)
              }
            }
          }
        }
      }
    }
    .padding(40)
    .frame(width: CGFloat(columns) * DropdownLayout.width + CGFloat(columns - 1) * gap + 80, alignment: .leading)
    .background(Color(red: 0.965, green: 0.96, blue: 0.95))
    .foregroundStyle(Color.black.opacity(0.86))
    .environment(\.colorScheme, .light)
  }

  private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title.uppercased())
        .font(.system(size: 15, weight: .bold))
        .tracking(1.2)
        .foregroundStyle(Color.black.opacity(0.6))
      content()
    }
  }

  private func tileView(_ tile: StateGridTile, size: CGSize) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(tile.caption)
        .font(.system(size: 14, weight: .medium))
      Text(tile.name + ".png")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.black.opacity(0.45))
      Image(decorative: tile.image, scale: 2)
        .frame(width: size.width, height: size.height)
    }
  }
}

private struct SettingsMenuBarSnapshotHarness: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(selection: .constant(.menuBar)) { _ in }

      Rectangle()
        .fill(SettingsPalette.rule)
        .frame(width: 1)

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
          SettingsSection("PREVIEW") {
            MenuBarSettingsPreview(
              mode: settings.menuBarDisplayMode,
              showAlbumArt: settings.showAlbumArtInMenuBar,
              maxWidth: settings.menuBarTitleWidth,
              showProgress: settings.showProgressInMenuBar)
          }

          SettingsSection("SWITCHES") {
            VStack(spacing: SettingsLayout.controlGap) {
              SettingsToggle(
                title: "Show album art",
                detail: "Show the current cover in menu bar modes that include artwork.",
                isOn: $settings.showAlbumArtInMenuBar)

              SettingsToggle(
                title: "Show progress line",
                detail: "Show a tiny playback progress line under the menu bar item.",
                isOn: $settings.showProgressInMenuBar)

              SettingsToggle(
                title: "Flash on new track",
                detail: "Pulse the menu bar item when the track changes.",
                isOn: $settings.flashOnTrackChange)
            }
          }
        }
          .padding(EdgeInsets(
            top: SettingsLayout.contentTop,
            leading: SettingsLayout.sidePadding,
            bottom: SettingsLayout.contentBottom,
            trailing: SettingsLayout.sidePadding))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .foregroundStyle(SettingsPalette.text)
    .tint(SettingsPalette.accent)
    .background(SettingsPalette.canvas)
    .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
  }
}

private struct MainHUDSnapshotHarness: View {
  let context: SnapshotContext
  @State private var showingInfoPanel = false

  private var deviceShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Dial.Layout.Dropdown.cornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(spacing: Dial.Layout.Dropdown.shellSpacing) {
      StatusRail(
        vm: context.menubar,
        showingInfoPanel: $showingInfoPanel,
        onOpenHistory: {},
        onOpenStats: {},
        onOpenSettings: {}
      )

      VStack(spacing: 0) {
        TrackHero(
          vm: context.nowPlaying,
          pet: context.pet,
          menubar: context.menubar,
          settings: context.settings,
          artworkCache: context.artworkCache,
          client: context.client,
          onReconnect: {},
          badgeInsight: BadgeInsight(
            kind: .deepCut,
            detail: "Visual regression fixture",
            explanation: "Keeps badge geometry present."),
          showPet: true,
          onOpenPet: {},
          onOpenHistory: {},
          onOpenBadge: {}
        )
        ReadoutsRow(vm: context.nowPlaying, onOpenStats: {}, onOpenHistory: {})
        PixelGridVisualizer(engine: context.visualizer)
      }
      .padding(.top, Dial.Layout.Dropdown.hudContentTopPadding)
      .padding(.bottom, Dial.Layout.Dropdown.hudContentBottomPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .overlay(LCDScanlines())
      .lcdPanel()
      .padding(.horizontal, Dial.Layout.Dropdown.panelHorizontalPadding)

      ControlsBar(menubar: context.menubar, client: context.client)
        .transportPanel()
        .padding(.horizontal, Dial.Layout.Transport.panelHorizontalPadding)
    }
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.outerBottomPadding)
    .frame(width: DropdownLayout.width, height: DropdownLayout.height)
    .dialChassisPlastic(shape: deviceShape)
  }
}

private struct PetScreenSnapshotHarness: View {
  let context: SnapshotContext
  let memories: [WeeklyMemoryRecord]
  let artifacts: [Artifact]
  let petState: PetState

  private var theme: DialTheme { DialTheme.palette(for: .slime) }
  private var deviceShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Dial.Layout.Dropdown.cornerRadius, style: .continuous)
  }

  var body: some View {
    PetView(
      pet: context.pet,
      aggCache: context.agg,
      menubar: context.menubar,
      dbq: context.dbq,
      livingMemoriesEnabled: true,
      initialTodayListeningMs: 7_380_000,
      initialBadgeCounts: [.discovery: 3, .pattern: 2, .milestone: 1],
      initialUnlockedTricks: [
        PetTrickUnlock(trick: .beatBounce, unlockedAt: petState.lastPlayAt ?? petState.installedAt, sourceBadge: BadgeMemoryKind.onStreak.rawValue),
      ],
      initialArtifacts: artifacts,
      initialWeeklyMemory: memories.first.map(StatsQueries.WeeklyMemorySnapshot.init(record:)),
      initialWeeklyMemoryLog: memories,
      initialPetState: petState,
      placement: .hardwareShell,
      onBack: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .frame(width: DropdownLayout.contentWidth, height: DropdownLayout.contentHeight)
    .frame(width: DropdownLayout.width, height: DropdownLayout.height)
    .contentShape(Rectangle())
    .background {
      ZStack {
        DialHardwareImage(name: "shell-slime-chassis")
        DialHardwareImage(name: "shell-slime-wells-full")
          .opacity(0.34)
      }
      .allowsHitTesting(false)
    }
    .clipShape(deviceShape)
    .overlay {
      ZStack {
        DialHardwareImage(name: "shell-slime-apertures-full")
        DialHardwareImage(name: "shell-slime-reflections")
      }
      .allowsHitTesting(false)
    }
    .environment(\.dialTheme, theme)
  }
}

private final class SnapshotTokenStore: TokenStore {
  private var token = SpotifyToken(accessToken: "snapshot-token", refreshToken: "snapshot-refresh", expiresAt: 4_102_444_800)

  func save(_ token: SpotifyToken) throws { self.token = token }
  func load() throws -> SpotifyToken? { token }
  func clear() throws {}
  func requireToken() throws -> SpotifyToken { token }
}

private struct RGB {
  let r: Int
  let g: Int
  let b: Int

  init(_ r: Int, _ g: Int, _ b: Int) {
    self.r = r
    self.g = g
    self.b = b
  }
}
