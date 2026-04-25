import SwiftUI

struct DropdownView: View {
  @Bindable var coord: AppCoordinator

  var body: some View {
    VStack(spacing: 0) {
      StatusRail(vm: coord.menubar, pet: coord.pet)
      TrackHero(vm: coord.nowPlaying)
      ReadoutsRow(vm: coord.nowPlaying)
      BadgeRow(kind: activeBadge, detail: badgeDetail)
      if let artist = coord.nowPlaying.track?.artistName {
        ArtistContext(artist: artist, rank7d: coord.aggCache.artistRank7d, lifetime: 0)
      }
      SessionTimeline(plays: coord.aggCache.last60Min)
      ControlsBar(client: coord.client)
    }
    .frame(width: 320, height: 360)
    .background(Dial.Palette.ground)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

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
