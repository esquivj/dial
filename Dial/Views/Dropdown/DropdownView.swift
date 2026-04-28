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
  }

  // MARK: - Signed-in body (HUD / History / Stats / Glossary)

  private var signedInView: some View {
    // Three-zone layout matching the mockup render:
    //   1. Status bar — floats directly on the device body
    //   2. LCD panel — inset rectangle with the main content
    //   3. Transport panel — inset rectangle with the controls
    //
    // Both panels use the shared `lcdPanel()` modifier which paints a
    // surface-fill + hairline + inner-top-shadow chrome. They're slightly
    // lighter than `ground` so they read as "the lit screen part of the
    // device" rather than as content sitting on the device chrome.
    // Three-zone layout matching the mockup render. Tighter spacing in
    // this pass — the prior 6pt VStack spacing + 8pt horizontal padding
    // left the LCD floating in too much surrounding margin. The render
    // is edge-to-edge dense; ours read loose by comparison.
    VStack(spacing: Dial.Layout.Dropdown.shellSpacing) {
      if coord.dropdownScreen == .hud {
        StatusRail(
          vm: coord.menubar,
          showingGlossary: $showingGlossary,
          onOpenHistory: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .history } },
          onOpenStats: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .stats } },
          onOpenSettings: openSettings
        )
      }

      screenPanel

      if coord.dropdownScreen == .hud && coord.settings.showTransportInHUD {
        // Transport panel uses the special capsule shape — horizontally
        // pill-shaped with fully rounded short edges. Distinct from the
        // rectangular LCD panel above so the eye reads it as the device's
        // dedicated playback-controls cradle.
        ControlsBar(
          menubar: coord.menubar,
          client: coord.client)
          .transportPanel()
          .padding(.horizontal, Dial.Layout.Transport.panelHorizontalPadding)
          .modifier(StaggeredAppear(delay: 0.20))
      }
    }
    // Vertical padding — 8pt top + 10pt bottom. Earlier 2pt top was
    // crowding the status bar against the body's upper corner curves;
    // 8pt gives "NOW PLAYING" and the time clear breathing room from
    // the top edge.
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.outerBottomPadding)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var screenPanel: some View {
    if hudScreenHugsContent {
      screenContent
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(LCDScanlines())
        .lcdPanel()
        .padding(.horizontal, Dial.Layout.Dropdown.panelHorizontalPadding)
    } else {
      screenContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(LCDScanlines())
        .lcdPanel()
        .padding(.horizontal, Dial.Layout.Dropdown.panelHorizontalPadding)
    }
  }

  private var hudScreenHugsContent: Bool {
    coord.dropdownScreen == .hud && !showingGlossary
  }

  /// What lives inside the "screen" area — glossary overlay or one of the
  /// three top-level screens. Extracted so the LCD overlays apply uniformly.
  @ViewBuilder
  private var screenContent: some View {
    if showingGlossary && coord.dropdownScreen == .hud {
      GlossaryPanel()
        .transition(.opacity.combined(with: .move(edge: .leading)))
    } else {
      switch coord.dropdownScreen {
      case .hud:
        hudBody
          .transition(.opacity)
      case .history:
        HistoryView(dbq: coord.dbq, onBack: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .hud } })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .stats:
        StatsView(
          dbq: coord.dbq,
          artworkCache: coord.artworkCache,
          onBack: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .hud } })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .pet:
        PetView(
          pet: coord.pet,
          aggCache: coord.aggCache,
          menubar: coord.menubar,
          dbq: coord.dbq,
          onBack: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .hud } }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
  }

  private var hudBody: some View {
    VStack(spacing: 0) {
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
        onOpenPet: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .pet } }
      )
      .modifier(StaggeredAppear(delay: 0.00))
      if coord.settings.showReadoutsInHUD {
        ReadoutsRow(vm: coord.nowPlaying)
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
    // Match the info/glossary screen's optical placement: content should sit
    // inside the LCD glass, not start flush at y=0. Kept at 6pt (not the
    // glossary's 16pt) because the player has more fixed-height hardware.
    .padding(.top, Dial.Layout.Dropdown.hudContentTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.hudContentBottomPadding)
    .frame(maxWidth: .infinity, alignment: .top)
  }

  // MARK: - Pre-auth (Connect button)

  private var connectView: some View {
    VStack(spacing: 0) {
      // Connect view's StatusRail is now pet-less too (pet display moved to
      // TrackHero, which the connect view doesn't render — the pet shows
      // up after auth via the signed-in HUD).
      StatusRail(
        vm: coord.menubar,
        showingGlossary: $showingGlossary,
        onOpenHistory: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .history } },
        onOpenStats: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .stats } },
        onOpenSettings: openSettings
      )

      if showingGlossary {
        GlossaryPanel()
      } else {
        Spacer(minLength: 12)

        VStack(alignment: .leading, spacing: 8) {
          Text("Welcome to Dial")
            .font(Dial.Typography.sansTitle)
            .foregroundStyle(Dial.Palette.textPrimary)
          Text("""
          A menubar companion for Spotify. Connect your account to start \
          tracking what you play and let the pet hatch.
          """)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textMuted)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)

        Spacer(minLength: 14)

        Button {
          Task { try? await coord.signIn() }
        } label: {
          Text("CONNECT SPOTIFY")
            .font(Dial.Typography.monoLabel)
            .tracking(1.4)
            .foregroundStyle(Dial.Palette.ground)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Dial.Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.32), radius: 3, x: 0, y: 1.5)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 18)

        Spacer(minLength: 12)

        Text("OAuth opens in your browser. Token stays in your Keychain.")
          .font(Dial.Typography.monoLabel)
          .tracking(0.6)
          .foregroundStyle(Dial.Palette.textMuted)
          .padding(.horizontal, 18)
          .padding(.bottom, 16)
      }
    }
  }

  private func openSettings() {
    SettingsWindowPresenter.shared.show(coord: coord)
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
