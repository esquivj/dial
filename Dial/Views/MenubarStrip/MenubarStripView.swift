import SwiftUI

/// The view inside the `NSStatusItem` button.
/// Settings drive this directly because this is a personal app: sometimes
/// you want the practical now-playing strip; sometimes you want the tiny pet.
struct MenubarStripView: View {
  @Bindable var vm: MenubarStripViewModel
  @Bindable var settings: SettingsViewModel
  @Bindable var pet: PetViewModel
  @Bindable var nowPlaying: NowPlayingViewModel
  @Bindable var artworkCache: ArtworkCache

  private enum Metrics {
    static let iconSlot: CGFloat = 22
    static let albumArt: CGFloat = 20
    static let pet: CGFloat = 20
    static let brandSymbol: CGFloat = 20
  }

  @State private var trackFlash = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var theme: DialTheme {
    DialTheme.palette(for: settings.hudColorMode.resolvedTheme(soundTheme: nowPlaying.soundTheme))
  }

  var body: some View {
    stripContent
      .padding(.leading, horizontalPadding.leading)
      .padding(.trailing, horizontalPadding.trailing)
      .padding(.vertical, 1)
      .overlay(alignment: .bottomLeading) {
        if settings.showProgressInMenuBar, vm.state != .nothingPlaying, progressFraction > 0 {
          GeometryReader { proxy in
            Capsule()
              .fill(theme.accent.opacity(vm.state == .playing ? 0.85 : 0.32))
              .frame(width: max(4, proxy.size.width * progressFraction), height: 1.5)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          }
          .allowsHitTesting(false)
        }
      }
      .background {
        if trackFlash && settings.flashOnTrackChange {
          RoundedRectangle(cornerRadius: Dial.Radius.tiny)
            .fill(theme.accent.opacity(0.18))
            .overlay(
              RoundedRectangle(cornerRadius: Dial.Radius.tiny)
                .stroke(theme.accent.opacity(0.45), lineWidth: 0.8))
        }
      }
      .onChange(of: vm.track?.uri) { oldValue, newValue in
        guard settings.flashOnTrackChange, !reduceMotion, oldValue != nil, newValue != nil else { return }
        trackFlash = true
        Task {
          try? await Task.sleep(nanoseconds: 420_000_000)
          await MainActor.run { trackFlash = false }
        }
      }
  }

  private var horizontalPadding: (leading: CGFloat, trailing: CGFloat) {
    switch settings.menuBarDisplayMode {
    case .albumArtTitle, .albumArtTrackArtist:
      return (7, 1)
    default:
      return (4, 4)
    }
  }

  @ViewBuilder
  private var stripContent: some View {
    if vm.state == .nothingPlaying {
      HStack(spacing: 5) {
        brandIdleIcon
        brandMenuBarText
      }
    } else {
      switch settings.menuBarDisplayMode {
      case .albumArtTitle:
        HStack(spacing: 5) {
          artIcon
          titleText
        }
      case .albumArtTrackArtist:
        HStack(spacing: 5) {
          artIcon
          trackArtistText
        }
      case .petTitle:
        HStack(spacing: 5) {
          petIcon
          titleText
        }
      case .petOnly:
        artIcon
      case .iconOnly:
        artIcon
      case .titlePlayCount:
        HStack(spacing: 5) {
          titleText
          if vm.state == .playing {
            Text("·\(vm.playsYTD)")
              .font(Dial.Typography.monoSmall)
              .foregroundStyle(theme.accent)
              .monospacedDigit()
          }
        }
      case .tinyChaos:
        HStack(spacing: 4) {
          petIcon
          artIcon
          Text(vm.state == .playing ? "\(vm.playsYTD)" : stateLabel)
            .font(Dial.Typography.monoTiny)
            .foregroundStyle(theme.accent)
            .monospacedDigit()
        }
      }
    }
  }

  @ViewBuilder
  private var trackArtistText: some View {
    switch vm.state {
    case .playing:
      trackArtistLine
    case .paused:
      dynamicMenuBarText(pausedTrackArtistString)
        .foregroundStyle(Dial.Palette.textMuted)
    case .nothingPlaying:
      brandMenuBarText
    }
  }

  private var trackArtistLine: some View {
    dynamicMenuBarText(trackArtistString)
      .foregroundStyle(Dial.Palette.textPrimary)
  }

  private var trackArtistString: String {
    let title = vm.track?.name ?? ""
    let artist = vm.track?.artistName ?? ""
    return artist.isEmpty ? title : "\(title) • \(artist)"
  }

  private var pausedTrackArtistString: String {
    trackArtistString.isEmpty ? "DIAL" : trackArtistString
  }

  @ViewBuilder
  private var titleText: some View {
    switch vm.state {
    case .playing:
      dynamicMenuBarText(vm.track?.name ?? "")
        .foregroundStyle(Dial.Palette.textPrimary)
    case .paused:
      dynamicMenuBarText(pausedTitleString)
        .foregroundStyle(Dial.Palette.textMuted)
    case .nothingPlaying:
      brandMenuBarText
    }
  }

  private func dynamicMenuBarText(_ text: String) -> some View {
    Text(text)
      .font(MenuBarTextMetrics.font)
      .kerning(MenuBarTextMetrics.kerning)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(width: menuBarTextWidth(for: text), height: MenuBarTextMetrics.lineHeight, alignment: .leading)
      .clipped()
  }

  private func menuBarTextWidth(for text: String) -> CGFloat {
    MenuBarTextMetrics.width(for: text, max: CGFloat(settings.menuBarTitleWidth))
  }

  private var brandMenuBarText: some View {
    Text("DIAL")
      .font(.custom("GeistPixel-Square", size: MenuBarTextMetrics.brandFontSize))
      .kerning(MenuBarTextMetrics.brandKerning)
      .lineLimit(1)
      .foregroundStyle(Color.white.opacity(0.96))
      .frame(width: MenuBarTextMetrics.brandWidth, height: MenuBarTextMetrics.lineHeight, alignment: .leading)
      .clipped()
  }

  @ViewBuilder
  private var artIcon: some View {
    if settings.showAlbumArtInMenuBar,
       vm.state != .nothingPlaying,
       let urlString = vm.track?.artUrl
    {
      cachedArtwork(urlString: urlString)
    } else if vm.state == .paused, vm.track != nil {
      pausedFallbackIcon
    } else {
      brandIdleIcon
    }
  }

  @ViewBuilder
  private func cachedArtwork(urlString: String) -> some View {
    Group {
      if let image = artworkCache.image(for: urlString) {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        RoundedRectangle(cornerRadius: Dial.Radius.printed)
          .fill(Dial.Palette.surface)
          .task(id: urlString) {
            await artworkCache.load(urlString)
          }
      }
    }
    .frame(width: Metrics.albumArt, height: Metrics.albumArt)
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.printed))
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.printed)
        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
    )
    .saturation(vm.state == .paused ? 0.45 : 1)
    .brightness(vm.state == .paused ? -0.08 : 0)
    .opacity(vm.state == .paused ? 0.78 : 1)
    .overlay(alignment: .bottomTrailing) {
      if vm.state == .paused {
        pauseHoldChip
          .offset(x: 2, y: 2)
      }
    }
    .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
  }

  @ViewBuilder
  private var petIcon: some View {
    if settings.petEnabled {
      BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: Metrics.pet)
        .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
    } else {
      brandIdleIcon
    }
  }

  private var brandIdleIcon: some View {
    DialThickIcon("brand.sparkles", size: Metrics.brandSymbol)
      .foregroundStyle(Color.white.opacity(0.96))
      .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
      .accessibilityHidden(true)
  }

  private var pausedFallbackIcon: some View {
    RoundedRectangle(cornerRadius: Dial.Radius.printed)
      .fill(Dial.Palette.subtle.opacity(0.9))
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.printed)
          .stroke(theme.accent.opacity(0.28), lineWidth: 0.7))
      .overlay {
        DialThickIcon("pause.hold", size: 8)
          .foregroundStyle(theme.accent.opacity(0.72))
      }
      .frame(width: Metrics.albumArt, height: Metrics.albumArt)
      .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
      .accessibilityHidden(true)
  }

  private var pauseHoldChip: some View {
    DialThickIcon("pause.hold", size: 7)
      .foregroundStyle(theme.accent.opacity(0.82))
      .frame(width: 11, height: 11)
      .background(
        Circle()
          .fill(Dial.Palette.ground.opacity(0.78))
          .overlay(
            Circle()
              .stroke(theme.accent.opacity(0.28), lineWidth: 0.5)))
      .accessibilityHidden(true)
  }

  private var pausedTitleString: String {
    let title = vm.track?.name ?? ""
    return title.isEmpty ? "DIAL" : title
  }

  private var stateLabel: String {
    switch vm.state {
    case .playing:        return "\(vm.playsYTD)"
    case .paused:         return "II"
    case .nothingPlaying: return "--"
    }
  }

  private var progressFraction: CGFloat {
    guard vm.durationMs > 0 else { return 0 }
    let ms = vm.interpolatedProgressMs()
    return CGFloat(min(1, max(0, Double(ms) / Double(vm.durationMs))))
  }
}
