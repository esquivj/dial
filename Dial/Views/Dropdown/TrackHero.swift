import SwiftUI
import AppKit

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
  let onOpenHistory: () -> Void
  let onOpenBadge: () -> Void
  @State private var lcdRefreshActive = false
  @State private var lcdRefreshTask: Task<Void, Never>?
  @State private var artworkState: TrackArtworkState = .empty
  @State private var artworkLoadTask: Task<Void, Never>?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dialTheme) private var theme

  /// Identity for track-owned content. The pet and hardware row stay planted;
  /// only artwork/readout data swaps when Spotify advances.
  private var transitionID: String { vm.track?.uri ?? "empty" }

  private var trackChangeAnimation: Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.22)
  }

  var body: some View {
    HStack(alignment: .center, spacing: Dial.Layout.Hero.spacing) {
      Button(action: onOpenHistory) {
        ZStack {
          heroArtwork
            .id(transitionID)
            .transition(.opacity)
        }
        .animation(trackChangeAnimation, value: transitionID)
        .frame(width: Dial.Layout.Hero.artworkSize, height: Dial.Layout.Hero.artworkSize)
        .dialMediaFrame(shape: RoundedRectangle(cornerRadius: Dial.Layout.Hero.artworkCornerRadius, style: .continuous))
        .overlay {
          if lcdRefreshActive {
            TrackLCDRefresh(color: theme.accent)
          }
        }
      }
      .buttonStyle(.pressable)
      .help("Open listening history")
      .accessibilityLabel(albumArtAccessibilityLabel)
      .accessibilityHint("Opens listening history")

      trackReadout
        .id(transitionID)
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .leading)))
        .animation(trackChangeAnimation, value: transitionID)
        .frame(maxWidth: .infinity, minHeight: Dial.Layout.Hero.textMinHeight, alignment: .leading)
        .layoutPriority(1)
        .overlay(alignment: .topLeading) {
          if lcdRefreshActive {
            TrackLCDRefresh(color: theme.accent)
          }
        }

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
    .onChange(of: transitionID) { oldValue, newValue in
      guard oldValue != newValue else { return }
      triggerLCDRefresh()
      refreshDisplayedArtwork(for: vm.track?.artUrl)
    }
    .onChange(of: vm.track?.artUrl) { _, newValue in
      refreshDisplayedArtwork(for: newValue)
    }
    .onAppear {
      refreshDisplayedArtwork(for: vm.track?.artUrl)
    }
    .onDisappear {
      lcdRefreshTask?.cancel()
      lcdRefreshTask = nil
      artworkLoadTask?.cancel()
      artworkLoadTask = nil
    }
  }

  private func triggerLCDRefresh() {
    guard !reduceMotion else { return }
    lcdRefreshTask?.cancel()
    lcdRefreshActive = false
    lcdRefreshTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(16))
      lcdRefreshActive = true
      try? await Task.sleep(for: .milliseconds(220))
      lcdRefreshActive = false
      lcdRefreshTask = nil
    }
  }

  private var trackReadout: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Marquee on the track name — Y2K-cliché now-playing scroll for
      // long titles. Fits-in-container titles render normally as
      // truncated lineLimit(1). Tiny height carve-out so the marquee's
      // GeometryReader has a height (it doesn't measure vertically).
      // Title in MINT mono — the mockup renders the track title in
      // bright mint, not ivory. Treating the title as "device readout"
      // (mint, mono) instead of "app body text" (ivory, sans) is what
      // flips the entire row's vibe. Geist Mono runs wider than IBM Plex,
      // so the default title size stays modest to keep the device panel
      // balanced against album art, badge, and pet.
      Marquee(
        text: vm.track?.name ?? "Nothing playing",
        font: titleFont,
        foreground: theme.accent
      )
      .frame(height: titleLineHeight)
      metadataCluster
      if badgeInsight != nil {
        badgeSlot
      }
    }
  }

  // MARK: - Pet

  @ViewBuilder
  private var heroArtwork: some View {
    if let image = currentArtworkImage {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      fallbackArtwork(showBrandIcon: vm.track == nil)
    }
  }

  @MainActor
  private func refreshDisplayedArtwork(for urlString: String?) {
    artworkLoadTask?.cancel()
    artworkLoadTask = nil

    guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      artworkState = vm.track == nil ? .empty : .failed(nil)
      return
    }

    if let cached = artworkCache.image(for: urlString) {
      artworkState = .loaded(url: urlString, image: cached)
      return
    }

    artworkState = .loading(url: urlString)
    artworkLoadTask = Task { @MainActor in
      let loaded = await artworkCache.load(urlString)
      guard !Task.isCancelled, vm.track?.artUrl == urlString else { return }
      if let loaded {
        artworkState = .loaded(url: urlString, image: loaded)
      } else {
        artworkState = .failed(urlString)
      }
      artworkLoadTask = nil
    }
  }

  private var currentArtworkImage: NSImage? {
    guard let urlString = vm.track?.artUrl else { return nil }
    if let image = artworkCache.image(for: urlString) { return image }
    if case let .loaded(url, image) = artworkState, url == urlString { return image }
    return nil
  }

  private func fallbackArtwork(showBrandIcon: Bool) -> some View {
    ZStack {
      Rectangle()
        .fill(theme.ground)
      Rectangle()
        .fill(theme.surface.opacity(0.58))
        .overlay(LCDScanlines(pitch: 3, opacity: 0.08, color: .black))
      if showBrandIcon, let icon = NSImage(named: "dial-app-icon") {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .padding(13)
          .opacity(0.88)
      } else {
        DialThickIcon("music.note", size: 22)
          .foregroundStyle(theme.textMuted.opacity(0.72))
      }
    }
  }

  @ViewBuilder
  private var metadataCluster: some View {
    if vm.track?.artistName != nil || vm.track?.albumName != nil {
      // Artist + album are one metadata cluster, not two equal siblings
      // competing with the title and badge. A 2pt internal gap keeps the
      // lines legible without splitting them into separate sections.
      HStack(alignment: .center, spacing: Dial.Layout.Hero.metadataActionSpacing) {
        VStack(alignment: .leading, spacing: Dial.Layout.Hero.metadataLineSpacing) {
          if let artist = vm.track?.artistName {
            Text(artist)
              .font(artistFont)
              .foregroundStyle(theme.textPrimary.opacity(0.84))
              .lineLimit(1)
              .truncationMode(.tail)
          }
          if let album = vm.track?.albumName {
            Text(album)
              .font(albumFont)
              .foregroundStyle(theme.textMuted.opacity(0.92))
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
        .layoutPriority(1)

        if vm.track != nil {
          LikedTrackButton(
            menubar: menubar,
            client: client,
            onReconnect: onReconnect)
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
    }
    .frame(height: max(badgeChipHeight, Dial.Layout.Hero.badgeMinHeight), alignment: .leading)
    .padding(.top, CGFloat(settings.hudHeroBadgeGap))
  }

  private func trackBadgeLine(_ insight: BadgeInsight) -> some View {
    let color = badgeColor(for: insight.kind)
    return Button(action: onOpenBadge) {
      badgeChip(for: insight.kind, color: color)
    }
      .buttonStyle(.pressable)
      .help(badgeHelp(for: insight))
      .accessibilityLabel("\(insight.kind.label): \(insight.detail)")
      .accessibilityHint(badgeHelp(for: insight))
  }

  private func badgeHelp(for insight: BadgeInsight) -> String {
    insight.explanation.isEmpty ? "\(insight.kind.label): \(insight.detail)" : insight.explanation
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
      return kind == .firstListen || kind == .newArtist ? theme.memoryAccent : theme.accent
    case .pattern:
      return theme.memoryAccent
    case .milestone:
      return theme.textPrimary
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
    .custom("GeistMono-Medium", size: CGFloat(settings.hudHeroTitleSize))
  }

  private var titleLineHeight: CGFloat {
    max(18, CGFloat(settings.hudHeroTitleSize) + 4)
  }

  private var artistFont: Font {
    .custom("GeistMono-Medium", size: CGFloat(settings.hudHeroArtistSize))
  }

  private var albumFont: Font {
    .custom("GeistMono-Regular", size: CGFloat(settings.hudHeroAlbumSize))
  }

  private var badgeFont: Font {
    .custom("GeistPixel-Square", size: 9 * badgeScale)
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
          fill: theme.lcd,
          edgeOpacity: 0.34,
          fillTopOpacity: 0.07,
          fillBottomOpacity: 0.025,
          sheenOpacity: 0.42,
          sheenLineWidth: 1.1,
          contactShadowOpacity: 0,
          innerShadowOpacity: 0.20)
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.tiny)
            .inset(by: 3)
            .stroke(theme.accent.opacity(0.24), lineWidth: 0.6)
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

private enum TrackArtworkState {
  case empty
  case loading(url: String)
  case loaded(url: String, image: NSImage)
  case failed(String?)
}

private struct TrackLCDRefresh: View {
  let color: Color
  @State private var phase: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let height = proxy.size.height
      let bandHeight = max(3, height * 0.18)
      let bandOpacity = max(0, sin(Double(phase) * .pi)) * 0.46

      ZStack(alignment: .top) {
        Rectangle()
          .fill(color.opacity(max(0, Double(1 - phase)) * 0.035))
        Rectangle()
          .fill(
            LinearGradient(
              colors: [
                color.opacity(0),
                color.opacity(bandOpacity),
                color.opacity(0),
              ],
              startPoint: .top,
              endPoint: .bottom)
          )
          .frame(height: bandHeight)
          .offset(y: -bandHeight + (height + bandHeight * 2) * phase)
      }
      .clipped()
      .allowsHitTesting(false)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.18)) {
        phase = 1
      }
    }
  }
}
