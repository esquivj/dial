import SwiftUI

enum DropdownScreen: Equatable { case hud, history, stats, pet }

enum DropdownLayout {
  static let width = Dial.Layout.Dropdown.width
  static let height = Dial.Layout.Dropdown.height
  static let contentWidth = Dial.Layout.Dropdown.contentWidth
  static let contentHeight = Dial.Layout.Dropdown.contentHeight
}

@Observable
final class DropdownVisibility {
  var isVisible = false
}

struct DropdownView: View {
  @Bindable var coord: AppCoordinator
  @Bindable var visibility: DropdownVisibility
  @State private var showingInfoPanel = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var deviceShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Dial.Layout.Dropdown.cornerRadius, style: .continuous)
  }

  // Screen state lives on the coordinator (`coord.dropdownScreen`) so the
  // status item's right-click menu can drive it from outside the view tree.
  // Persists across popover open/close cycles, same as the prior local
  // @State (NSPopover reuses the hosting controller).

  var body: some View {
    if visibility.isVisible {
      visibleBody
    } else {
      Color.clear
        .frame(width: DropdownLayout.width, height: DropdownLayout.height)
    }
  }

  private var visibleBody: some View {
    Group {
      if coord.settings.signedIn {
        signedInView
      } else {
        connectView
      }
    }
    .frame(width: DropdownLayout.contentWidth, height: DropdownLayout.contentHeight)
    .frame(width: DropdownLayout.width, height: DropdownLayout.height)
    .contentShape(Rectangle())
    .background {
      ZStack {
        DialHardwareImage(name: shellChassisAssetName)
        DialHardwareImage(name: shellWellsAssetName)
          .opacity(shellWellsOpacity)
        if !shellChromeAboveContent {
          shellChromeLayer
        }
      }
      .allowsHitTesting(false)
    }
    .clipShape(deviceShape)
    .overlay {
      if shellChromeAboveContent {
        shellChromeLayer
          .allowsHitTesting(false)
      }
    }
    .environment(\.dialTheme, activeTheme)
    .animation(.easeOut(duration: 0.22), value: activeThemeID)
  }

  private var activeThemeID: DialThemeID {
    coord.settings.hudColorMode.resolvedTheme(soundTheme: coord.nowPlaying.soundTheme)
  }

  private var activeTheme: DialTheme {
    DialTheme.palette(for: activeThemeID)
  }

  private var shellChromeAboveContent: Bool {
    true
  }

  private var shellChromeLayer: some View {
    ZStack {
      DialHardwareImage(name: shellApertureAssetName)
      DialHardwareImage(name: shellReflectionsAssetName)
    }
  }

  private var shellSkinID: String {
    switch activeThemeID {
    case .classic: "smoke"
    case .slime:   "slime"
    case .aqua:    "aqua"
    case .ember:   "ember"
    }
  }

  private var shellChassisAssetName: String {
    "shell-\(shellSkinID)-chassis"
  }

  private var shellReflectionsAssetName: String {
    "shell-\(shellSkinID)-reflections"
  }

  private var shellApertureAssetName: String {
    if !coord.settings.signedIn {
      return "shell-\(shellSkinID)-apertures-hud-no-transport"
    }
    if coord.dropdownScreen == .history || coord.dropdownScreen == .stats {
      return "shell-\(shellSkinID)-apertures-hud-no-transport"
    }
    if coord.settings.signedIn && !isHUDScreen {
      return "shell-\(shellSkinID)-apertures-full"
    }
    if isHUDScreen && !coord.settings.showTransportInHUD {
      return "shell-\(shellSkinID)-apertures-hud-no-transport"
    }
    return "shell-\(shellSkinID)-apertures-hud"
  }

  private var shellWellsAssetName: String {
    if !coord.settings.signedIn {
      return "shell-\(shellSkinID)-wells-hud-no-transport"
    }
    if coord.dropdownScreen == .history || coord.dropdownScreen == .stats {
      return "shell-\(shellSkinID)-wells-hud-no-transport"
    }
    if coord.settings.signedIn && !isHUDScreen {
      return "shell-\(shellSkinID)-wells-full"
    }
    if isHUDScreen && !coord.settings.showTransportInHUD {
      return "shell-\(shellSkinID)-wells-hud-no-transport"
    }
    return "shell-\(shellSkinID)-wells-hud"
  }

  private var shellWellsOpacity: Double {
    switch activeThemeID {
    case .classic: return 0.42
    case .slime:   return 0.34
    case .aqua:    return 0.30
    case .ember:   return 0.32
    }
  }

  private var screenTransitionAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.18)
  }

  private var topChromeTransition: AnyTransition {
    reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
  }

  private var bottomChromeTransition: AnyTransition {
    reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom))
  }

  // MARK: - Signed-in body (HUD / History / Stats / Glossary)

  @ViewBuilder
  private var signedInView: some View {
    if isHUDScreen {
      hudChromeLayout
    } else if coord.dropdownScreen == .history {
      historyChromeLayout
    } else if coord.dropdownScreen == .stats {
      statsChromeLayout
    } else if coord.dropdownScreen == .pet {
      petChromeLayout
    } else {
      fullScreenLayout
    }
  }

  private var hudChromeLayout: some View {
    VStack(spacing: 0) {
      topChromeSlot
        .frame(height: Dial.Layout.Dropdown.hudTopChromeHeight)

      screenPanel
        .frame(height: adjustedHudScreenHeight)
        .padding(.top, adjustedHudRailScreenGap)

      if coord.settings.showTransportInHUD {
        bottomChromeSlot
          .frame(height: Dial.Layout.Dropdown.hudTransportHeight)
          .padding(.top, adjustedHudScreenTransportGap)
      }
    }
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, hudBottomPadding)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private var fullScreenLayout: some View {
    screenPanel
      .padding(.vertical, Dial.Layout.Dropdown.fullScreenVerticalPadding)
      .frame(maxHeight: .infinity, alignment: .top)
  }

  private var historyChromeLayout: some View {
    HistoryView(
      dbq: coord.dbq,
      artworkCache: coord.artworkCache,
      initialSnapshot: coord.cachedHistorySnapshot,
      onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } },
      onSnapshot: { coord.cachedHistorySnapshot = $0 },
      placement: .hardwareShell
    )
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }

  private var statsChromeLayout: some View {
    StatsView(
      dbq: coord.dbq,
      artworkCache: coord.artworkCache,
      initialSnapshot: coord.cachedStatsSnapshotYTD,
      onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } },
      onSnapshot: { coord.cachedStatsSnapshotYTD = $0 },
      placement: .hardwareShell
    )
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }

  private var petChromeLayout: some View {
    PetView(
      pet: coord.pet,
      aggCache: coord.aggCache,
      menubar: coord.menubar,
      dbq: coord.dbq,
      livingMemoriesEnabled: coord.settings.livingMemoriesEnabled,
      initialSnapshot: coord.cachedPetSnapshot,
      onSnapshot: { coord.cachedPetSnapshot = $0 },
      placement: .hardwareShell,
      onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } }
    )
    .transition(.move(edge: .trailing).combined(with: .opacity))
  }

  private var hudScreenHeight: CGFloat {
    coord.settings.showTransportInHUD
      ? Dial.Layout.Dropdown.hudScreenHeightWithTransport
      : Dial.Layout.Dropdown.hudScreenHeightWithoutTransport
  }

  private var adjustedHudScreenHeight: CGFloat {
    hudScreenHeight + infoScreenHeightBonus
  }

  private var adjustedHudRailScreenGap: CGFloat {
    Dial.Layout.Dropdown.hudRailScreenGap + infoScreenTopNudge
  }

  private var adjustedHudScreenTransportGap: CGFloat {
    max(0, Dial.Layout.Dropdown.hudScreenTransportGap - infoScreenTopNudge - infoScreenHeightBonus)
  }

  private var infoScreenTopNudge: CGFloat {
    showingInfoPanel && isHUDScreen ? 6 : 0
  }

  private var infoScreenHeightBonus: CGFloat {
    showingInfoPanel && isHUDScreen ? 6 : 0
  }

  private var hudBottomPadding: CGFloat {
    coord.settings.showTransportInHUD
      ? Dial.Layout.Dropdown.hudBottomPaddingWithTransport
      : Dial.Layout.Dropdown.hudBottomPaddingWithoutTransport
  }

  @ViewBuilder
  private var topChromeSlot: some View {
    if isHUDScreen {
      StatusRail(
        vm: coord.menubar,
        showingInfoPanel: $showingInfoPanel,
        onOpenHistory: openHistory,
        onOpenStats: openStats,
        onOpenSettings: openSettings
      )
      .offset(y: Dial.Layout.Dropdown.hudRailContentYOffset)
      .transition(topChromeTransition)
      .zIndex(2)
    }
  }

  @ViewBuilder
  private var bottomChromeSlot: some View {
    if isHUDScreen && coord.settings.showTransportInHUD {
      ControlsBar(
        menubar: coord.menubar,
        client: coord.client)
        .frame(height: Dial.Layout.Dropdown.hudTransportHeight)
        .id(showingInfoPanel ? "transport-info" : "transport-hud")
        .background { transportTrayBacking }
        .padding(.horizontal, Dial.Layout.Transport.panelHorizontalPadding)
        .modifier(EntranceAppear(enabled: entranceMotionEnabled, delay: 0.20))
        .transition(bottomChromeTransition)
        .zIndex(1)
    }
  }

  private var transportTrayBacking: some View {
    Color.clear
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private var screenPanel: some View {
    if isHUDScreen {
      screenContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
          if screenUsesScanlines {
            LCDScanlines()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
        .padding(.horizontal, Dial.Layout.Dropdown.hudScreenHorizontalPadding)
    } else {
      fullScreenPanel(
        screenContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      )
        .padding(.horizontal, Dial.Layout.Dropdown.panelHorizontalPadding)
    }
  }

  @ViewBuilder
  private func fullScreenPanel<Content: View>(_ content: Content) -> some View {
    content
      .lcdPanel(fill: screenPanelFill, strokeOpacity: 0.08)
  }

  private var screenPanelFill: Color {
    let opacity: Double = isHUDScreen ? 0.28 : 0.58
    return activeTheme.subtle.opacity(opacity)
  }

  private var screenUsesScanlines: Bool {
    coord.dropdownScreen == .hud && !showingInfoPanel
  }

  /// What lives inside the "screen" area — glossary overlay or one of the
  /// three top-level screens. Extracted so the LCD overlays apply uniformly.
  @ViewBuilder
  private var screenContent: some View {
    if showingInfoPanel && isHUDScreen {
      infoViewport
        .transition(.opacity.combined(with: .move(edge: .leading)))
    } else {
      switch coord.dropdownScreen {
      case .hud:
        hudBody
          .transition(.opacity)
      case .history:
        HistoryView(
          dbq: coord.dbq,
          artworkCache: coord.artworkCache,
          initialSnapshot: coord.cachedHistorySnapshot,
          onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } },
          onSnapshot: { coord.cachedHistorySnapshot = $0 })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .stats:
        StatsView(
          dbq: coord.dbq,
          artworkCache: coord.artworkCache,
          initialSnapshot: coord.cachedStatsSnapshotYTD,
          onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } },
          onSnapshot: { coord.cachedStatsSnapshotYTD = $0 })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .pet:
        PetView(
          pet: coord.pet,
          aggCache: coord.aggCache,
          menubar: coord.menubar,
          dbq: coord.dbq,
          livingMemoriesEnabled: coord.settings.livingMemoriesEnabled,
          initialSnapshot: coord.cachedPetSnapshot,
          onSnapshot: { coord.cachedPetSnapshot = $0 },
          onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
  }

  private var glossaryViewport: some View {
    GlossaryPanel()
      .padding(.top, infoScrollViewportTopInset)
  }

  @ViewBuilder
  private var infoViewport: some View {
    if coord.nowPlaying.track != nil {
      CurrentTrackWhyPanel(
        vm: coord.nowPlaying,
        badgeInsight: coord.settings.showBadgesInHUD ? activeBadgeInsight : nil,
        onOpenStats: openStats,
        onOpenHistory: openHistory
      )
      .padding(.top, infoScrollViewportTopInset)
    } else {
      glossaryViewport
    }
  }

  private var infoScrollViewportTopInset: CGFloat {
    showingInfoPanel && isHUDScreen ? 24 : 0
  }

  private var hudBody: some View {
    VStack(spacing: 0) {
      if isIdleHUD {
        IdleHUDView(
          pet: coord.pet,
          showPet: coord.settings.petEnabled,
          onOpenHistory: openHistory,
          onOpenStats: openStats,
          onOpenPet: openPet)
          .modifier(EntranceAppear(enabled: entranceMotionEnabled, delay: 0))
      } else {
        TrackHero(
          vm: coord.nowPlaying,
          pet: coord.pet,
          menubar: coord.menubar,
          settings: coord.settings,
          artworkCache: coord.artworkCache,
          client: coord.client,
          onReconnect: { try await coord.reconnectForLibraryAccess() },
          badgeInsight: coord.settings.showBadgesInHUD ? activeBadgeInsight : nil,
          showPet: coord.settings.petEnabled && coord.settings.showPetInHUD,
          onOpenPet: openPet,
          onOpenHistory: openHistory,
          onOpenBadge: openStats
        )
        .modifier(EntranceAppear(enabled: entranceMotionEnabled, delay: 0))
        if coord.settings.showReadoutsInHUD {
          ReadoutsRow(
            vm: coord.nowPlaying,
            onOpenStats: openStats,
            onOpenHistory: openHistory)
            .modifier(EntranceAppear(enabled: entranceMotionEnabled, delay: entranceAnimationDelay(1)))
        }
        // ArtistContext (artist rank + lifetime plays) used to live here as a
        // 4th data row, but stacking three numeric rows (Readouts + Badge +
        // Artist) before the visualizer was the AI-slop "metric grid" tell —
        // every individual row was well-designed but the stack read as
        // dashboard-template. Artist data is still surfaced in StatsView for
        // anyone who wants the breakdown.
        //
        // Replaces the old SessionTimeline ("plays in last 60 min" bars).
        // That row encoded recency through three redundant channels (width,
        // height, opacity) and didn't represent the song. The visualizer
        // shows the actual audio in real time via ScreenCaptureKit + FFT.
        // The 60-min play log still lives in HistoryView for users who want it.
        //
        // `.task` fires start() every appear; the engine is idempotent and
        // restarts a stream it parked while the dropdown was closed.
        //
        // Visibility throttle: attach/detach gate FFT processing on whether
        // the view is mounted, and the engine stops the SCStream once the
        // dropdown has been closed for a few seconds.
        if coord.settings.showVisualizerInHUD {
          PixelGridVisualizer(engine: coord.visualizer)
            .modifier(EntranceAppear(enabled: entranceMotionEnabled, delay: entranceAnimationDelay(2)))
            .task {
              configureSpectrum()
              await coord.visualizer.start()
            }
            .onAppear {
              configureSpectrum()
              coord.visualizer.attach()
            }
            .onChange(of: spectrumSettingsFingerprint) { _, _ in
              configureSpectrum()
            }
            .onDisappear { coord.visualizer.detach() }
        }
      }
    }
    // Match the info/glossary screen's optical placement: content should sit
    // inside the LCD glass, not start flush at y=0. Kept at 6pt (not the
    // glossary's 16pt) because the player has more fixed-height hardware.
    .padding(.top, Dial.Layout.Dropdown.hudContentTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.hudContentBottomPadding)
    .frame(maxWidth: .infinity, alignment: .top)
  }

  private var isIdleHUD: Bool {
    coord.menubar.state == .nothingPlaying || coord.nowPlaying.track == nil
  }

  private var isHUDScreen: Bool {
    coord.dropdownScreen == .hud
  }

  // MARK: - Pre-auth (Connect button)

  private var connectView: some View {
    ConnectSetupView(
      showingGlossary: $showingInfoPanel,
      onConnect: { Task { try? await coord.signIn() } },
      onOpenSettings: openSettings)
  }

  private func openSettings() {
    SettingsWindowPresenter.shared.show(coord: coord)
  }

  private func openHistory() {
    withAnimation(screenTransitionAnimation) {
      showingInfoPanel = false
      coord.dropdownScreen = .history
    }
  }

  private func openStats() {
    withAnimation(screenTransitionAnimation) {
      showingInfoPanel = false
      coord.dropdownScreen = .stats
    }
  }

  private func openPet() {
    withAnimation(screenTransitionAnimation) {
      showingInfoPanel = false
      coord.dropdownScreen = .pet
    }
  }

  // MARK: - Badge resolution

  private var activeBadgeInsight: BadgeInsight? {
    guard let insight = coord.aggCache.currentBadgeInsight else { return nil }
    switch insight.kind.category {
    case .discovery:
      return coord.settings.discoveryBadgesEnabled ? insight : nil
    case .pattern:
      return coord.settings.patternBadgesEnabled ? insight : nil
    case .milestone:
      return coord.settings.milestoneBadgesEnabled ? insight : nil
    }
  }

  private var entranceMotionEnabled: Bool {
    coord.settings.animationLevel == .extra
  }

  private func entranceAnimationDelay(_ index: Int) -> Double {
    Double(index) * 0.05
  }

  private var spectrumSettingsFingerprint: String {
    [
      coord.settings.spectrumStyle.rawValue,
      coord.settings.spectrumDensity.rawValue,
      coord.settings.spectrumMotion.rawValue,
      coord.settings.spectrumPeakMarkers ? "peaks" : "no-peaks",
    ].joined(separator: ":")
  }

  private func configureSpectrum() {
    coord.visualizer.configure(
      style: coord.settings.spectrumStyle,
      density: coord.settings.spectrumDensity,
      motion: coord.settings.spectrumMotion,
      showPeakMarkers: coord.settings.spectrumPeakMarkers)
  }

}

/// Keep normal dropdown opens instant. The only HUD entrance cascade left is
/// behind the explicit "Extra" motion setting; default motion should not hide
/// first paint behind a decorative fade.
private struct EntranceAppear: ViewModifier {
  let enabled: Bool
  let delay: Double
  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if enabled && !reduceMotion {
      content
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(.easeOut(duration: 0.22).delay(delay), value: appeared)
        .onAppear { appeared = true }
    } else {
      content
        .onAppear { appeared = true }
    }
  }
}

private struct IdleHUDView: View {
  @Bindable var pet: PetViewModel
  let showPet: Bool
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void
  let onOpenPet: () -> Void
  @Environment(\.dialTheme) private var theme

  var body: some View {
    VStack {
      Spacer(minLength: 0)

      HStack(alignment: .center, spacing: 12) {
        idleGlyph

        VStack(alignment: .leading, spacing: 9) {
          VStack(alignment: .leading, spacing: 3) {
            Text("READY")
              .font(.custom("GeistMono-Medium", size: 17))
              .tracking(1.4)
              .foregroundStyle(theme.accent)
              .lineLimit(1)
            Text("Start a track in Spotify. Dial will catch it.")
              .font(Dial.Typography.sansCaption)
              .foregroundStyle(theme.textMuted)
              .lineLimit(2)
              .minimumScaleFactor(0.86)
          }

          HStack(spacing: 6) {
            idleAction("HISTORY", icon: "clock.arrow.circlepath", action: onOpenHistory)
            idleAction("STATS", icon: "chart.bar.fill", action: onOpenStats)
            if showPet {
              idleAction("PET", icon: "sparkles", action: onOpenPet)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
      .dialRaisedGel(
        shape: RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous),
        fill: theme.surface.opacity(0.38),
        edgeOpacity: 0.20,
        fillTopOpacity: 0.06,
        fillBottomOpacity: 0.015,
        sheenOpacity: 0.22,
        sheenLineWidth: 0.55,
        contactShadowOpacity: 0.12,
        contactShadowRadius: 1.5,
        contactShadowY: 0.75,
        innerShadowOpacity: 0.10)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var idleGlyph: some View {
    if showPet {
      Button(action: onOpenPet) {
        BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 54)
          .frame(width: 66, height: 66)
          .dialRaisedGel(
            shape: RoundedRectangle(cornerRadius: Dial.Radius.lcd, style: .continuous),
            fill: theme.lcd,
            edgeOpacity: 0.34,
            fillTopOpacity: 0.07,
            fillBottomOpacity: 0.025,
            sheenOpacity: 0.40,
            sheenLineWidth: 1.0,
            contactShadowOpacity: 0,
            innerShadowOpacity: 0.18)
      }
      .buttonStyle(.pressable)
      .help("Open pet")
      .accessibilityLabel("Open pet")
    } else {
      DialIcon("music.note")
        .frame(width: 30, height: 30)
        .foregroundStyle(theme.accent)
        .frame(width: 66, height: 66)
        .dialRaisedGel(
          shape: RoundedRectangle(cornerRadius: Dial.Radius.lcd, style: .continuous),
          fill: theme.surface.opacity(0.28),
          edgeOpacity: 0.22,
          fillTopOpacity: 0.06,
          fillBottomOpacity: 0.015,
          sheenOpacity: 0.24,
          sheenLineWidth: 0.8,
          contactShadowOpacity: 0,
          innerShadowOpacity: 0.12)
        .accessibilityLabel("No track playing")
    }
  }

  private func idleAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        DialIcon(icon)
          .frame(width: 10, height: 10)
        Text(label)
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(theme.textPrimary.opacity(0.82))
      .frame(width: 62, height: 22)
      .dialPrintedChip(
        shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
        color: theme.textMuted,
        fillOpacity: 0.045,
        edgeOpacity: 0.16)
    }
    .buttonStyle(.pressable)
    .help(label.capitalized)
    .accessibilityLabel(label.capitalized)
  }
}
