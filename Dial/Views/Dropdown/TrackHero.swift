import SwiftUI

struct TrackHero: View {
  @Bindable var vm: NowPlayingViewModel
  @Bindable var pet: PetViewModel
  /// Tap on the pet block opens the dedicated PetView. Wired from
  /// DropdownView (was previously on the StatusRail thumbnail; relocated
  /// here so the pet can be rendered at a readable 48×48).
  let onOpenPet: () -> Void

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
      // 0.10 (was 0.18) — demoted as part of the glow-discipline pass;
      // the album art is steady-state, the halo only needs to whisper.
      .shadow(color: Dial.Palette.amber.opacity(0.10), radius: 10, x: 0, y: 0)

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
      .frame(maxWidth: .infinity, alignment: .leading)

      // Pet block — moved from StatusRail (where it was 24×24, too small to
      // read the new pixel-art detail) to TrackHero at 48×48 inside a 56×56
      // LCD-bezel frame. Sits opposite the album art for balanced visual
      // weight: album = music identity, pet = brand identity, both equally
      // present in the user's primary glance row.
      petBlock
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
    .id(transitionID)
    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
    .animation(.easeOut(duration: 0.28), value: transitionID)
  }

  // MARK: - Pet

  /// Same Tamagotchi-on-a-handheld framing the StatusRail thumbnail used,
  /// scaled up. Tap → PetView. Streak-flame indicator (≥3 days) carried
  /// over from the old thumbnail so the per-pet status follows the pet.
  @ViewBuilder
  private var petBlock: some View {
    Button(action: onOpenPet) {
      ZStack {
        // Tamagotchi-style "powered LCD" inside the bezel — pale green-cream
        // background that the black-and-white pet silhouette sits on top of.
        // Was Color.black.opacity(0.40) when the pet itself was cyan; with
        // the pet now being a pure-black silhouette, the bezel needs to be
        // light or the pet would be invisible against the dark device chrome.
        RoundedRectangle(cornerRadius: 6)
          .fill(Dial.Palette.lcd)
        BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 56)
          .frame(width: 56, height: 56)
      }
      // Pet block bumped 56×56 → 64×64 (sprite 48 → 56) — the pixel-art
      // detail reads better at this size and balances against the 72×72
      // album art on the left. Text VStack still has ~132pt to work with.
      .frame(width: 64, height: 64)
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Dial.Palette.amber.opacity(0.55), lineWidth: 1)
      )
      .overlay(alignment: .topTrailing) {
        if pet.streakDays >= 3 {
          Image(systemName: "flame.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Dial.Palette.orange)
            .shadow(color: Dial.Palette.orange.opacity(0.8), radius: 3)
            .padding(4)
            .help("\(pet.streakDays)-day streak")
        }
      }
      .shadow(color: Dial.Palette.amber.opacity(0.30), radius: 6, x: 0, y: 0)
    }
    .buttonStyle(.plain)
    .help("Open pet")
  }
}
