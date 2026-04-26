import SwiftUI

struct TrackHero: View {
  @Bindable var vm: NowPlayingViewModel

  /// Identity for the crossfade transition — when the URI changes,
  /// SwiftUI swaps the entire row and animates the swap. Without this,
  /// album art and text would snap-cut on every track change.
  private var transitionID: String { vm.track?.uri ?? "empty" }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AsyncImage(url: vm.track?.artUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        // Soft cream-toned placeholder so an empty track doesn't punch a
        // dark hole in the light layout.
        LinearGradient(
          colors: [Dial.Palette.subtle, Dial.Palette.hairline],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      // Album art bumped from 52→72: the artwork *is* the hero of the row.
      // Soft warm shadow gives it weight on the cream ground (Sleeve influence).
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      // Y2K crystal: subtle cyan halo around the album art instead of
      // a warm drop shadow. Reads as "lit-from-within" against the dark.
      .shadow(color: Dial.Palette.amber.opacity(0.18), radius: 10, x: 0, y: 0)

      VStack(alignment: .leading, spacing: 2) {
        // Marquee on the track name — Y2K-cliché now-playing scroll for
        // long titles. Fits-in-container titles render normally as
        // truncated lineLimit(1). Tiny height carve-out so the marquee's
        // GeometryReader has a height (it doesn't measure vertically).
        Marquee(
          text: vm.track?.name ?? "Nothing playing",
          font: Dial.Typography.sansTitle,
          foreground: Dial.Palette.ivory
        )
        .frame(height: 18)
        if let artist = vm.track?.artistName {
          Text(artist)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.muted)
            .lineLimit(1)
        }
        if let album = vm.track?.albumName {
          Text(album)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.muted.opacity(0.75))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
    .id(transitionID)
    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
    .animation(.easeOut(duration: 0.28), value: transitionID)
  }
}
