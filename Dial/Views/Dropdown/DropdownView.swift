import SwiftUI

struct DropdownView: View {
  @Bindable var coord: AppCoordinator
  @State private var showingGlossary = false

  var body: some View {
    Group {
      if coord.settings.signedIn {
        signedInView
      } else {
        connectView
      }
    }
    .frame(width: 320, height: 360)
    .background(Dial.Palette.ground)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Signed-in (full HUD)

  private var signedInView: some View {
    VStack(spacing: 0) {
      StatusRail(vm: coord.menubar, pet: coord.pet, showingGlossary: $showingGlossary)
      if showingGlossary {
        GlossaryPanel()
      } else {
        TrackHero(vm: coord.nowPlaying)
        ReadoutsRow(vm: coord.nowPlaying)
        BadgeRow(kind: activeBadge, detail: badgeDetail)
        if let artist = coord.nowPlaying.track?.artistName {
          ArtistContext(
            artist: artist,
            rank7d: coord.aggCache.artistRank7d,
            lifetime: coord.aggCache.artistLifetimePlays
          )
        }
        SessionTimeline(plays: coord.aggCache.last60Min)
        ControlsBar(
          client: coord.client,
          onOpenHistory: { coord.windows.openHistory() },
          onOpenStats: { coord.windows.openStats() }
        )
      }
    }
  }

  // MARK: - Pre-auth (Connect button)

  private var connectView: some View {
    VStack(spacing: 0) {
      // Same status rail so the pet egg is visible from the jump.
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
