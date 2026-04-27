import SwiftUI

enum DropdownScreen: Equatable { case hud, history, stats, pet }

struct DropdownView: View {
  @Bindable var coord: AppCoordinator
  @State private var showingGlossary = false

  // Screen state lives on the coordinator (`coord.dropdownScreen`) so the
  // status item's right-click menu can drive it from outside the view tree.
  // Persists across popover open/close cycles, same as the prior local
  // @State (NSPopover reuses the hosting controller).

  var body: some View {
    Group {
      if coord.settings.signedIn {
        signedInView
      } else {
        connectView
      }
    }
    // Device body: 360×380. Square-ish; the extra 20pt over a true
    // square gives the status bar more breathing room from the top
    // corner curves without bloating the body or reintroducing empty
    // Spacer below the spectrum.
    .frame(width: 360, height: 380)
    .background(
      // Layered device body, bottom to top:
      //   1. Solid ground (teal-shifted for material identity)
      //   2. Convex linear gradient — mint glow catching the upper curve,
      //      fading through clear, deepening to black at the underside.
      //   3. Radial vignette — darkens the corners, leaves the center
      //      neutral. The render's body reads as a 3D glass slab because
      //      its corners are visibly darker than its middle (light falls
      //      off as the curve recedes from the viewer). This single
      //      gradient does most of the "this is glass with depth" work.
      //   4. Dust texture stippling
      ZStack {
        Dial.Palette.ground
        LinearGradient(
          colors: [
            Dial.Palette.amber.opacity(0.12),
            Color.clear,
            Color.clear,
            Color.black.opacity(0.28),
          ],
          startPoint: .top, endPoint: .bottom)
        RadialGradient(
          colors: [
            Color.clear,
            Color.clear,
            Color.black.opacity(0.40),
          ],
          center: .center,
          startRadius: 100,
          endRadius: 240)
        DustTexture()
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: 40))
    // Inner top shadow — the device body's own lip casts a soft shadow
    // into the cavity. Sells the "this is a glass slab with a recessed
    // interior" reading that all the inner containers then sit inside.
    .overlay(
      RoundedRectangle(cornerRadius: 40)
        .stroke(Color.black.opacity(0.35), lineWidth: 3)
        .blur(radius: 2)
        .offset(y: 2)
        .mask(RoundedRectangle(cornerRadius: 40))
        .allowsHitTesting(false)
    )
    // Plasticky outer shell — translucent white gradient stroke matches
    // the inner panels' chrome language. Earlier this was mint top →
    // black bottom, which read as "neon LED edge" rather than "clear
    // plastic shell." White-on-white gradient (bright top catch, faint
    // bottom) reads as "translucent plastic catching ambient light from
    // above." 1.4pt line width gives the shell visible "thickness."
    .overlay(
      RoundedRectangle(cornerRadius: 40)
        .stroke(LinearGradient(colors: [
          Color.white.opacity(0.65),
          Color.white.opacity(0.30),
          Color.white.opacity(0.15),
          Color.white.opacity(0.08),
        ], startPoint: .top, endPoint: .bottom), lineWidth: 1.4)
    )
    .overlay(
      // Top-arc gel sheen — bright specular highlight where the curve
      // catches light. 0.70 (was 0.40) — needs to be visibly brighter
      // than the new 0.65 base stroke or the sheen disappears into it.
      RoundedRectangle(cornerRadius: 39)
        .trim(from: 0.05, to: 0.45)
        .stroke(Color.white.opacity(0.70), lineWidth: 1.4)
        .blur(radius: 0.6)
        .padding(0.5)
        .allowsHitTesting(false)
    )
    // Outer aura removed — there's no reason for the entire panel to
    // emit mint light into surrounding space. The device body's chrome
    // (plasticky stroke + sheen) does enough to read as "lit object";
    // the aura on top was decorative bloat. Padding also removed since
    // there's no shadow that needs room to render — the panel now
    // matches the body dimensions exactly.
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
    VStack(spacing: 4) {
      if coord.dropdownScreen == .hud {
        StatusRail(
          vm: coord.menubar,
          showingGlossary: $showingGlossary,
          onOpenHistory: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .history } },
          onOpenStats: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .stats } }
        )
      }

      screenContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(LCDScanlines())
        .lcdPanel()
        .padding(.horizontal, 6)

      if coord.dropdownScreen == .hud {
        // Transport panel uses the special capsule shape — horizontally
        // pill-shaped with fully rounded short edges. Distinct from the
        // rectangular LCD panel above so the eye reads it as the device's
        // dedicated playback-controls cradle.
        ControlsBar(menubar: coord.menubar, client: coord.client)
          .transportPanel()
          .padding(.horizontal, 6)
          .modifier(StaggeredAppear(delay: 0.20))
      }
    }
    // Vertical padding — 8pt top + 10pt bottom. Earlier 2pt top was
    // crowding the status bar against the body's upper corner curves;
    // 8pt gives "NOW PLAYING" and the time clear breathing room from
    // the top edge.
    .padding(.top, 8)
    .padding(.bottom, 10)
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
        StatsView(dbq: coord.dbq, onBack: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .hud } })
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .pet:
        PetView(
          pet: coord.pet,
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
        onOpenPet: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .pet } }
      )
      .modifier(StaggeredAppear(delay: 0.00))
      ReadoutsRow(vm: coord.nowPlaying)
        .modifier(StaggeredAppear(delay: 0.05))
      BadgeRow(kind: activeBadge, detail: badgeDetail)
        .modifier(StaggeredAppear(delay: 0.10))
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
      PixelGridVisualizer(engine: coord.visualizer)
        .modifier(StaggeredAppear(delay: 0.15))
        .task { await coord.visualizer.start() }
        .onAppear { coord.visualizer.attach() }
        .onDisappear { coord.visualizer.detach() }
      // Flex spacer absorbs any leftover vertical room so the LCD content
      // stays top-aligned and the screen area fills the bezel cleanly,
      // regardless of how many optional rows above (BadgeRow / ArtistContext)
      // are mounted.
      Spacer(minLength: 0)
    }
    .frame(maxHeight: .infinity, alignment: .top)
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
        onOpenStats: { withAnimation(.easeInOut(duration: 0.18)) { coord.dropdownScreen = .stats } }
      )

      if showingGlossary {
        GlossaryPanel()
      } else {
        Spacer(minLength: 12)

        VStack(alignment: .leading, spacing: 8) {
          Text("Welcome to Dial")
            .font(Dial.Typography.sansTitle)
            .foregroundStyle(Dial.Palette.ivory)
          Text("""
          A menubar companion for Spotify. Connect your account to start \
          tracking what you play and let the pet hatch.
          """)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted)
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
            .background(Dial.Palette.amber)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Dial.Palette.amber.opacity(0.4), radius: 8, x: 0, y: 0)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 18)

        Spacer(minLength: 12)

        Text("OAuth opens in your browser. Token stays in your Keychain.")
          .font(Dial.Typography.monoLabel)
          .tracking(0.6)
          .foregroundStyle(Dial.Palette.muted)
          .padding(.horizontal, 18)
          .padding(.bottom, 16)
      }
    }
  }

  // MARK: - Badge resolution

  private var activeBadge: BadgeKind {
    if coord.aggCache.firstListen { return .firstListen }
    if coord.aggCache.rediscovered { return .rediscovered }
    if coord.aggCache.onStreak    { return .onStreak }
    return .none
  }

  private var badgeDetail: String {
    switch activeBadge {
    case .firstListen:  "You've never played this before"
    case .rediscovered: "Haven't heard in a while"
    case .onStreak:     "Most-played track this week"
    case .none:         ""
    }
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
