import SwiftUI

enum DropdownScreen: Equatable { case hud, history, stats, pet }

enum DropdownLayout {
  static let width = Dial.Layout.Dropdown.width
  static let height = Dial.Layout.Dropdown.height
}

@Observable
final class DropdownVisibility {
  var isVisible = false
}

struct DropdownView: View {
  @Bindable var coord: AppCoordinator
  @Bindable var visibility: DropdownVisibility
  @State private var showingGlossary = false
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
    // Popover shell: calm continuous plastic. The transport cradle keeps
    // the custom hardware curve; the window itself should not compete.
    .frame(width: DropdownLayout.width, height: DropdownLayout.height)
    .dialChassisPlastic(shape: deviceShape)
    .environment(\.dialTheme, activeTheme)
    .animation(.easeOut(duration: 0.22), value: activeThemeID)
  }

  private var activeThemeID: DialThemeID {
    coord.settings.hudColorMode.resolvedTheme(soundTheme: coord.nowPlaying.soundTheme)
  }

  private var activeTheme: DialTheme {
    DialTheme.palette(for: activeThemeID)
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

  private var signedInView: some View {
    VStack(spacing: Dial.Layout.Dropdown.shellSpacing) {
      topChromeSlot
      screenPanel
      bottomChromeSlot
    }
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.outerBottomPadding)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var topChromeSlot: some View {
    if isHUDScreen {
      StatusRail(
        vm: coord.menubar,
        showingGlossary: $showingGlossary,
        onOpenHistory: openHistory,
        onOpenStats: openStats,
        onOpenSettings: openSettings
      )
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
        .id(showingGlossary ? "transport-glossary" : "transport-hud")
        .transportPanel()
        .padding(.horizontal, Dial.Layout.Transport.panelHorizontalPadding)
        .modifier(StaggeredAppear(delay: 0.20))
        .transition(bottomChromeTransition)
        .zIndex(1)
    }
  }

  @ViewBuilder
  private var screenPanel: some View {
    screenContent
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .overlay(LCDScanlines())
      .lcdPanel()
      .padding(.horizontal, Dial.Layout.Dropdown.panelHorizontalPadding)
  }

  /// What lives inside the "screen" area — glossary overlay or one of the
  /// three top-level screens. Extracted so the LCD overlays apply uniformly.
  @ViewBuilder
  private var screenContent: some View {
    if showingGlossary && isHUDScreen {
      GlossaryPanel()
        .transition(.opacity.combined(with: .move(edge: .leading)))
    } else {
      switch coord.dropdownScreen {
      case .hud:
        hudBody
          .transition(.opacity)
      case .history:
        HistoryView(dbq: coord.dbq, onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .stats:
        StatsView(
          dbq: coord.dbq,
          artworkCache: coord.artworkCache,
          onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .pet:
        PetView(
          pet: coord.pet,
          aggCache: coord.aggCache,
          menubar: coord.menubar,
          dbq: coord.dbq,
          onBack: { withAnimation(screenTransitionAnimation) { coord.dropdownScreen = .hud } }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
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
          .modifier(StaggeredAppear(delay: 0))
      } else {
        // Staggered entrance: each section fades + lifts in with a 50ms cascade.
        // Reads as deliberate composition rather than "everything appears at once,"
        // and is short enough (~250ms total) not to feel like a loading sequence.
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
        .modifier(StaggeredAppear(delay: 0.00))
        if coord.settings.showReadoutsInHUD {
          ReadoutsRow(
            vm: coord.nowPlaying,
            onOpenStats: openStats,
            onOpenHistory: openHistory)
            .modifier(StaggeredAppear(delay: animationDelay(1)))
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
        // Long-lived engine: `.task` fires start() every appear, but the engine
        // is idempotent and keeps the SCStream running across dropdown closes.
        // Avoids re-prompting for Screen Recording permission on every open.
        //
        // Visibility throttle: attach/detach gate FFT processing on whether
        // the view is mounted, so when the popover is closed the engine stops
        // burning CPU on FFT work nobody is observing. Stream stays alive
        // either way (permission stability > tiny capture cost).
        if coord.settings.showVisualizerInHUD {
          PixelGridVisualizer(engine: coord.visualizer)
            .modifier(StaggeredAppear(delay: animationDelay(2)))
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
      showingGlossary: $showingGlossary,
      onConnect: { Task { try? await coord.signIn() } },
      onOpenSettings: openSettings)
  }

  private func openSettings() {
    SettingsWindowPresenter.shared.show(coord: coord)
  }

  private func openHistory() {
    withAnimation(screenTransitionAnimation) {
      showingGlossary = false
      coord.dropdownScreen = .history
    }
  }

  private func openStats() {
    withAnimation(screenTransitionAnimation) {
      showingGlossary = false
      coord.dropdownScreen = .stats
    }
  }

  private func openPet() {
    withAnimation(screenTransitionAnimation) {
      showingGlossary = false
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

  private func animationDelay(_ index: Int) -> Double {
    switch coord.settings.animationLevel {
    case .low:    return 0
    case .normal: return Double(index) * 0.05
    case .extra:  return Double(index) * 0.08
    }
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

/// Subtle entrance animation for stacked HUD sections. Each section fades
/// from 0→1 opacity and lifts 6pt while it does, with a per-section delay
/// so the rows cascade rather than appearing simultaneously.
///
/// State lives at the modifier level (outside the wrapped view) so internal
/// id/transition swaps inside a section — e.g. TrackHero's track-change
/// crossfade — don't reset the cascade.
///
/// Respects `accessibilityReduceMotion`: when the user has macOS's "Reduce
/// motion" enabled (System Settings → Accessibility → Display), the cascade
/// is skipped — content appears instantly with no opacity/offset tween.
private struct StaggeredAppear: ViewModifier {
  let delay: Double
  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(appeared || reduceMotion ? 1 : 0)
      .offset(y: appeared || reduceMotion ? 0 : 6)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(delay), value: appeared)
      .onAppear { appeared = true }
  }
}
