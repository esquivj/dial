import SwiftUI

enum DropdownScreen: Equatable { case hud, history, stats }

struct DropdownView: View {
  @Bindable var coord: AppCoordinator
  @State private var screen: DropdownScreen = .hud
  @State private var showingGlossary = false

  var body: some View {
    Group {
      if coord.settings.signedIn {
        signedInView
      } else {
        connectView
      }
    }
    // 400 (was 360): gives the HUD breathing room when both BadgeRow and
    // ArtistContext are visible. Prevents the layout shift on transition
    // back from History/Stats where the HUD was butting hard against the
    // frame and SwiftUI re-laid it inconsistently.
    .frame(width: 320, height: 400)
    .background(Dial.Palette.ground)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Dial.Palette.hairline, lineWidth: 1)
    )
  }

  // MARK: - Signed-in body (HUD / History / Stats / Glossary)

  private var signedInView: some View {
    VStack(spacing: 0) {
      // Status rail stays mounted ONLY on the HUD screen — History and Stats
      // own their own header (with a back chevron). Glossary keeps the rail
      // because it's a transient overlay.
      if screen == .hud {
        StatusRail(vm: coord.menubar, pet: coord.pet, showingGlossary: $showingGlossary)
      }

      if showingGlossary && screen == .hud {
        GlossaryPanel()
          .transition(.opacity.combined(with: .move(edge: .leading)))
      } else {
        switch screen {
        case .hud:
          hudBody
            .transition(.opacity)
        case .history:
          HistoryView(dbq: coord.dbq, onBack: { withAnimation(.easeInOut(duration: 0.18)) { screen = .hud } })
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .stats:
          StatsView(dbq: coord.dbq, onBack: { withAnimation(.easeInOut(duration: 0.18)) { screen = .hud } })
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
    }
  }

  private var hudBody: some View {
    VStack(spacing: 0) {
      // Staggered entrance: each section fades + lifts in with a 50ms cascade.
      // Reads as deliberate composition rather than "everything appears at once,"
      // and is short enough (~250ms total) not to feel like a loading sequence.
      TrackHero(vm: coord.nowPlaying)
        .modifier(StaggeredAppear(delay: 0.00))
      ReadoutsRow(vm: coord.nowPlaying)
        .modifier(StaggeredAppear(delay: 0.05))
      BadgeRow(kind: activeBadge, detail: badgeDetail)
        .modifier(StaggeredAppear(delay: 0.10))
      if let artist = coord.nowPlaying.track?.artistName {
        ArtistContext(
          artist: artist,
          rank7d: coord.aggCache.artistRank7d,
          lifetime: coord.aggCache.artistLifetimePlays
        )
        .modifier(StaggeredAppear(delay: 0.15))
      }
      SessionTimeline(plays: coord.aggCache.last60Min)
        .modifier(StaggeredAppear(delay: 0.20))
      // Flex spacer absorbs any leftover vertical room so ControlsBar
      // is always pinned to the bottom — independent of how many
      // optional rows above (BadgeRow / ArtistContext) are mounted.
      Spacer(minLength: 0)
      ControlsBar(
        menubar: coord.menubar,
        client: coord.client,
        onOpenHistory: { withAnimation(.easeInOut(duration: 0.18)) { screen = .history } },
        onOpenStats:   { withAnimation(.easeInOut(duration: 0.18)) { screen = .stats } }
      )
      .modifier(StaggeredAppear(delay: 0.25))
    }
    // Force the body to claim the entire space below the StatusRail so the
    // Spacer above behaves predictably and SwiftUI doesn't re-allocate
    // children when the screen swaps.
    .frame(maxHeight: .infinity, alignment: .top)
  }

  // MARK: - Pre-auth (Connect button)

  private var connectView: some View {
    VStack(spacing: 0) {
      StatusRail(vm: coord.menubar, pet: coord.pet, showingGlossary: $showingGlossary)

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
        .buttonStyle(.plain)
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
private struct StaggeredAppear: ViewModifier {
  let delay: Double
  @State private var appeared = false

  func body(content: Content) -> some View {
    content
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared ? 0 : 6)
      .animation(.easeOut(duration: 0.28).delay(delay), value: appeared)
      .onAppear { appeared = true }
  }
}
