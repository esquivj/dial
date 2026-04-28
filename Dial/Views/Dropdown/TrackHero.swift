import SwiftUI

struct TrackHero: View {
  @Bindable var vm: NowPlayingViewModel
  @Bindable var pet: PetViewModel
  @Bindable var menubar: MenubarStripViewModel
  @Bindable var settings: SettingsViewModel
  @Bindable var artworkCache: ArtworkCache
  let client: SpotifyClient
  let onReconnect: () async throws -> Void
  let badgeInsight: BadgeInsight?
  let showPet: Bool
  /// Tap on the pet block opens the dedicated PetView. Wired from
  /// DropdownView (was previously on the StatusRail thumbnail; relocated
  /// here so the pet can be rendered at a readable size.
  let onOpenPet: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Identity for the crossfade transition — when the URI changes,
  /// SwiftUI swaps the entire row and animates the swap. Without this,
  /// album art and text would snap-cut on every track change.
  private var transitionID: String { vm.track?.uri ?? "empty" }

  var body: some View {
    HStack(alignment: .center, spacing: Dial.Layout.Hero.spacing) {
      heroArtwork
      .frame(width: Dial.Layout.Hero.artworkSize, height: Dial.Layout.Hero.artworkSize)
      .dialMediaFrame(shape: RoundedRectangle(cornerRadius: Dial.Layout.Hero.artworkCornerRadius, style: .continuous))
      .accessibilityLabel(albumArtAccessibilityLabel)

      VStack(alignment: .leading, spacing: 0) {
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
          font: titleFont,
          foreground: Dial.Palette.accent
        )
        .frame(height: titleLineHeight)
        metadataCluster
        badgeSlot
      }
      .frame(maxWidth: .infinity, minHeight: Dial.Layout.Hero.textMinHeight, alignment: .leading)
      .layoutPriority(1)

      // Pet block — moved from StatusRail (where it was 24×24, too small to
      // read the new pixel-art detail) to TrackHero inside a readable LCD
      // LCD-bezel frame. Sits opposite the album art for balanced visual
      // weight: album = music identity, pet = brand identity, both equally
      // present in the user's primary glance row.
      if showPet {
        petBlock
      }
    }
    // Tighter padding to match the render's edge-to-edge density. Was
    // 12/14/14/14; trimmed to 10/12/12/12 so the album art, title, and
    // pet block sit closer to the LCD panel's inner edges.
    .padding(Dial.Layout.Hero.padding)
    .id(transitionID)
    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
    .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: transitionID)
  }

  // MARK: - Pet

  @ViewBuilder
  private var heroArtwork: some View {
    if let urlString = vm.track?.artUrl,
       let image = artworkCache.image(for: urlString)
    {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      LinearGradient(
        colors: [Dial.Palette.subtle, Dial.Palette.hairline],
        startPoint: .topLeading, endPoint: .bottomTrailing)
        .task(id: vm.track?.artUrl) {
          await artworkCache.load(vm.track?.artUrl)
        }
    }
  }

  @ViewBuilder
  private var metadataCluster: some View {
    if vm.track?.artistName != nil || vm.track?.albumName != nil {
      // Artist + album are one metadata cluster, not two equal siblings
      // competing with the title and badge. A 2pt internal gap keeps the
      // lines legible without splitting them into separate sections.
      VStack(alignment: .leading, spacing: Dial.Layout.Hero.metadataLineSpacing) {
        if let artist = vm.track?.artistName {
          Text(artist)
            .font(artistFont)
            .foregroundStyle(Dial.Palette.textPrimary.opacity(0.84))
            .lineLimit(1)
            .truncationMode(.tail)
        }
        if let album = vm.track?.albumName {
          Text(album)
            .font(albumFont)
            .foregroundStyle(Dial.Palette.textMuted.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .padding(.top, CGFloat(settings.hudHeroMetadataGap))
    }
  }

  @ViewBuilder
  private var badgeSlot: some View {
    HStack(spacing: Dial.Layout.Hero.badgeSpacing) {
      if let badgeInsight {
        trackBadgeLine(badgeInsight)
      }
      Spacer(minLength: Dial.Layout.Hero.badgeTrailingMinSpacing)
      if vm.track != nil {
        LikedTrackButton(
          menubar: menubar,
          client: client,
          onReconnect: onReconnect)
      }
    }
    .frame(height: max(badgeChipHeight, Dial.Layout.Hero.badgeMinHeight), alignment: .leading)
    .padding(.top, CGFloat(settings.hudHeroBadgeGap))
  }

  private func trackBadgeLine(_ insight: BadgeInsight) -> some View {
    let color = badgeColor(for: insight.kind)
    return badgeChip(for: insight.kind, color: color)
      .accessibilityLabel("\(insight.kind.label): \(insight.detail)")
  }

  private func badgeChip(for kind: BadgeMemoryKind, color: Color) -> some View {
    HStack(spacing: Dial.Layout.Hero.badgeSpacing) {
      BadgePixelIcon(kind: kind, color: color, size: Dial.Layout.Hero.badgeIconBaseSize * badgeScale)
      Text(badgeLabel(for: kind))
        .font(badgeFont)
        .tracking(1.2)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .padding(EdgeInsets(
      top: Dial.Layout.Hero.badgePaddingBase.top * badgeScale,
      leading: Dial.Layout.Hero.badgePaddingBase.leading * badgeScale,
      bottom: Dial.Layout.Hero.badgePaddingBase.bottom * badgeScale,
      trailing: Dial.Layout.Hero.badgePaddingBase.trailing * badgeScale))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Layout.Hero.badgeCornerRadius, style: .continuous),
      color: color)
  }

  private func badgeColor(for kind: BadgeMemoryKind) -> Color {
    switch kind.category {
    case .discovery:
      return kind == .firstListen || kind == .newArtist ? Dial.Palette.accentAlt : Dial.Palette.accent
    case .pattern:
      return Dial.Palette.accentAlt
    case .milestone:
      return Dial.Palette.textPrimary
    }
  }

  private func badgeLabel(for kind: BadgeMemoryKind) -> String {
    switch kind {
    case .firstListen: return "FIRST LISTEN"
    case .newArtist: return "NEW ARTIST"
    case .rediscovered: return "REDISCOVERED"
    case .deepCut: return "DEEP CUT"
    case .onStreak: return "ON STREAK"
    case .repeatTrack: return "REPEAT"
    case .albumMode: return "ALBUM MODE"
    case .play10: return "10TH PLAY"
    case .play50: return "50TH PLAY"
    case .play100: return "100TH PLAY"
    case .anniversary: return "ANNIVERSARY"
    }
  }

  private var titleFont: Font {
    .custom("IBMPlexMono-Medium", size: CGFloat(settings.hudHeroTitleSize))
  }

  private var titleLineHeight: CGFloat {
    max(20, CGFloat(settings.hudHeroTitleSize) + 4)
  }

  private var artistFont: Font {
    .custom("IBMPlexSans-Medium", size: CGFloat(settings.hudHeroArtistSize))
  }

  private var albumFont: Font {
    .custom("IBMPlexSans-Regular", size: CGFloat(settings.hudHeroAlbumSize))
  }

  private var badgeFont: Font {
    .custom("IBMPlexMono-Medium", size: 9 * badgeScale)
  }

  private var badgeScale: CGFloat {
    CGFloat(settings.hudBadgeScale)
  }

  private var badgeChipHeight: CGFloat {
    Dial.Layout.Hero.badgeMinHeight * badgeScale
  }

  /// Same Tamagotchi-on-a-handheld framing the StatusRail thumbnail used,
  /// scaled up. Tap -> PetView for streaks, bond meters, and trick actions.
  @ViewBuilder
  private var petBlock: some View {
    Button(action: onOpenPet) {
      // Pet LCD: same outer footprint as before, but the sprite sits
      // farther inside the screen. That inset is what makes the housing
      // read as a physical screen instead of a sprite pasted to a button.
      BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: Dial.Layout.Hero.petSpriteHeight)
        .frame(width: Dial.Layout.Hero.petContentSize, height: Dial.Layout.Hero.petContentSize)
        .frame(width: Dial.Layout.Hero.petFrameSize, height: Dial.Layout.Hero.petFrameSize)
        .dialRaisedGel(
          shape: RoundedRectangle(cornerRadius: Dial.Layout.Hero.petCornerRadius, style: .continuous),
          fill: Dial.Palette.lcd,
          edgeOpacity: 0.34,
          fillTopOpacity: 0.07,
          fillBottomOpacity: 0.025,
          sheenOpacity: 0.42,
          sheenLineWidth: 1.1,
          contactShadowOpacity: 0,
          innerShadowOpacity: 0.20)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .inset(by: 3)
            .stroke(Dial.Palette.accent.opacity(0.24), lineWidth: 0.6)
        )
        // Directional drop shadow (dark, downward y-offset) — the pet
        // block sits raised above the LCD panel surface and casts a
        // soft contact shadow. Lighting effect, not "neon halo."
        .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
    }
    .buttonStyle(.pressable)
    .help("Open pet")
    .accessibilityLabel("Open pet")
    .accessibilityHint("Shows pet stage and listening progress")
  }

  private var albumArtAccessibilityLabel: String {
    guard let track = vm.track else { return "Nothing playing" }
    return "Album art for \(track.albumName)"
  }
}
