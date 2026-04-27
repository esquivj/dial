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
      // Album art: 72pt frame with directional-lighting chrome (no
      // colored bloom). Reads as "framed media sitting on the device,
      // lit from above":
      //   * Inner top shadow — image recessed into the frame
      //   * Top-arc white sheen — specular highlight where light catches
      //   * Mint stroke — the lit branded frame edge
      //   * Dark drop shadow — the frame casts a soft shadow on the
      //     surface below it (NOT a colored halo)
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.black.opacity(0.45), lineWidth: 3)
          .blur(radius: 2)
          .offset(y: 1.5)
          .mask(RoundedRectangle(cornerRadius: 6))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .trim(from: 0.05, to: 0.45)
          .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
          .blur(radius: 0.6)
          .allowsHitTesting(false)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Dial.Palette.amber.opacity(0.55), lineWidth: 1)
      )
      // Dark drop shadow (radius 4, y-offset 2) replacing the prior
      // mint bloom. Colored halos read as "neon glow" — tacky. A dark
      // contact shadow reads as "object resting above its surface" —
      // physically lit.
      .shadow(color: Color.black.opacity(0.40), radius: 4, x: 0, y: 2)

      VStack(alignment: .leading, spacing: 2) {
        // Marquee on the track name — Y2K-cliché now-playing scroll for
        // long titles. Fits-in-container titles render normally as
        // truncated lineLimit(1). Tiny height carve-out so the marquee's
        // GeometryReader has a height (it doesn't measure vertically).
        // Title in MINT mono — the mockup renders the track title in
        // bright mint, not ivory. Treating the title as "device readout"
        // (mint, mono) instead of "app body text" (ivory, sans) is what
        // flips the entire row's vibe. 14pt fits typical track names
        // in the ~132pt title container (HStack remainder after album +
        // pet + spacing). Larger sizes overflow → constant marquee.
        Marquee(
          text: vm.track?.name ?? "Nothing playing",
          font: Dial.Typography.monoTitle,
          foreground: Dial.Palette.amber
        )
        .frame(height: 20)
        // Artist + album also in mint, but at lower opacity for
        // hierarchy. Mockup shows them as faded mint, not gray. Gray
        // (the prior `muted` token) read as "secondary app text" —
        // mint at 0.65 / 0.45 reads as "secondary device readout."
        if let artist = vm.track?.artistName {
          Text(artist)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.amber.opacity(0.65))
            .lineLimit(1)
        }
        if let album = vm.track?.albumName {
          Text(album)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.amber.opacity(0.45))
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
    // Tighter padding to match the render's edge-to-edge density. Was
    // 12/14/14/14; trimmed to 10/12/12/12 so the album art, title, and
    // pet block sit closer to the LCD panel's inner edges.
    .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
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
      // Tamagotchi-style "powered LCD" — pale green-cream background
      // that the B&W pet silhouette sits on top of. Pet bezel now uses
      // the shared GelContainer treatment with the LCD cream as base
      // fill, so it gets the same convex top-arc sheen as every other
      // container. The pet block is the most "device" element in the
      // layout (a literal bezel-around-a-screen metaphor) so its halo
      // and stroke run a notch brighter than the stat cards.
      BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 56)
        .frame(width: 56, height: 56)
        .frame(width: 64, height: 64)
        // Pet block is the only container that should keep a mint stroke —
        // it's a literal "powered LCD bezel" metaphor. Other containers
        // (cards, LCD panels) use the new plasticky-white stroke default.
        .gelContainer(
          cornerRadius: 6,
          strokeColor: Dial.Palette.amber,
          strokeOpacity: 0.85,
          sheenOpacity: 0.55,        // brighter sheen — pet is the hero container
          sheenLineWidth: 1.4,
          haloOpacity: 0,            // no colored bloom — replaced by drop shadow below
          convexTopOpacity: 0.0,     // LCD already light — no extra mint glow on top
          convexBottomOpacity: 0.0,  // skip darken — would muddy the cream LCD
          innerShadowOpacity: 0.18,  // light bezel = soft inner shadow only
          baseFill: Dial.Palette.lcd
        )
        // Directional drop shadow (dark, downward y-offset) — the pet
        // block sits raised above the LCD panel surface and casts a
        // soft contact shadow. Lighting effect, not "neon halo."
        .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
        .overlay(alignment: .topTrailing) {
          if pet.streakDays >= 3 {
            DialIcon("flame.fill")
              .frame(width: 14, height: 14)
              .foregroundStyle(Dial.Palette.orange)
              .shadow(color: Dial.Palette.orange.opacity(0.8), radius: 3)
              .padding(4)
              .help("\(pet.streakDays)-day streak")
          }
        }
    }
    .buttonStyle(.pressable)
    .help("Open pet")
  }
}

