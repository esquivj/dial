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
    static let capsuleRadius: CGFloat = 7
  }

  @State private var trackFlash = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private var theme: DialTheme {
    DialTheme.palette(for: settings.hudColorMode.resolvedTheme(soundTheme: nowPlaying.soundTheme))
  }

  /// The strip sits on the system menu bar, which turns light or dark with
  /// the desktop. Dark keeps the original white/ivory ink; a light bar gets
  /// near-black ink so the text doesn't vanish.
  private func ink(_ dark: Color, light lightOpacity: Double) -> Color {
    colorScheme == .light ? Color.black.opacity(lightOpacity) : dark
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
        menuBarTrackFlash
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

  @ViewBuilder
  private var menuBarTrackFlash: some View {
    if trackFlash && settings.flashOnTrackChange {
      RoundedRectangle(cornerRadius: Metrics.capsuleRadius, style: .continuous)
        .fill(theme.accent.opacity(0.14))
    }
  }

  private var horizontalPadding: (leading: CGFloat, trailing: CGFloat) {
    switch settings.menuBarDisplayMode {
    case .albumArtTitle, .albumArtTrackArtist:
      return (7, 5)
    default:
      return (6, 6)
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
      dynamicMenuBarText(pausedTrackArtistString, foreground: ink(Dial.Palette.textMuted, light: 0.5))
    case .nothingPlaying:
      brandMenuBarText
    }
  }

  private var trackArtistLine: some View {
    let title = vm.track?.name ?? ""
    let artist = vm.track?.artistName ?? ""

    return Group {
      if title.isEmpty || artist.isEmpty {
        dynamicMenuBarText(trackArtistString, foreground: ink(Color.white.opacity(0.93), light: 0.85))
      } else {
        dynamicMenuBarPair(primary: title, secondary: artist, widthKey: trackArtistString)
      }
    }
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
      dynamicMenuBarText(vm.track?.name ?? "", foreground: ink(Dial.Palette.textPrimary, light: 0.85))
    case .paused:
      dynamicMenuBarText(pausedTitleString, foreground: ink(Dial.Palette.textMuted, light: 0.5))
    case .nothingPlaying:
      brandMenuBarText
    }
  }

  private func dynamicMenuBarText(
    _ text: String,
    foreground: Color
  ) -> some View {
    MenubarTickerText(
      segments: [.init(text: text, foreground: foreground)],
      width: menuBarTextWidth(for: text),
      accessibilityLabel: text)
  }

  private func dynamicMenuBarPair(primary: String, secondary: String, widthKey: String) -> some View {
    MenubarTickerText(
      segments: [
        .init(text: primary, foreground: ink(Color.white.opacity(0.94), light: 0.85)),
        .init(text: " • ", foreground: ink(theme.accent.opacity(0.70), light: 0.35)),
        .init(text: secondary, foreground: ink(Dial.Palette.textMuted.opacity(0.88), light: 0.55)),
      ],
      width: menuBarTextWidth(for: widthKey),
      accessibilityLabel: widthKey)
  }

  private func menuBarTextWidth(for text: String) -> CGFloat {
    MenuBarTextMetrics.width(for: text, max: CGFloat(settings.menuBarTitleWidth))
  }

  private var brandMenuBarText: some View {
    Text("DIAL")
      .font(.custom("GeistPixel-Square", size: MenuBarTextMetrics.brandFontSize))
      .kerning(MenuBarTextMetrics.brandKerning)
      .lineLimit(1)
      .foregroundStyle(ink(Color.white.opacity(0.96), light: 0.85))
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
        .stroke(Color.white.opacity(0.24), lineWidth: 0.55)
    )
    .shadow(color: Color.black.opacity(0.40), radius: 1.5, x: 0, y: 0.6)
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
      // The sprite is black line art; the white matte fills its body so it
      // still reads on a dark menu bar.
      BulldogSprite(
        stage: pet.stage,
        behavior: pet.behavior,
        height: Metrics.pet,
        matteColor: Color.white.opacity(0.92))
        .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
    } else {
      brandIdleIcon
    }
  }

  private var brandIdleIcon: some View {
    DialThickIcon("brand.sparkles", size: Metrics.brandSymbol)
      .foregroundStyle(ink(Color.white.opacity(0.96), light: 0.85))
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

private struct MenubarTickerText: View {
  struct Segment {
    let text: String
    let foreground: Color
  }

  let segments: [Segment]
  let width: CGFloat
  let accessibilityLabel: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var contentWidth: CGFloat = 0
  @State private var cycleStart = Date()

  private let speed: Double = 24
  private let startHold: TimeInterval = 0.85
  private let endHold: TimeInterval = 0.95

  var body: some View {
    let overflow = max(0, contentWidth - width)
    let needsTicker = overflow > 1 && !reduceMotion

    ZStack(alignment: .leading) {
      if needsTicker {
        TimelineView(.animation) { context in
          scrollingContent(
            elapsed: context.date.timeIntervalSince(cycleStart),
            overflow: overflow)
        }
      } else if overflow > 1 {
        fallbackText
      } else {
        tickerContent
      }
    }
    .frame(width: width, height: MenuBarTextMetrics.lineHeight, alignment: .leading)
    .clipped()
    .background(measuredContent)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .onAppear { cycleStart = Date() }
    .onChange(of: accessibilityLabel) { _, _ in cycleStart = Date() }
    .onChange(of: width) { _, _ in cycleStart = Date() }
  }

  private func scrollingContent(elapsed: TimeInterval, overflow: CGFloat) -> some View {
    let travelTime = max(1.0, TimeInterval(overflow) / speed)
    let cycleLength = startHold + travelTime + endHold
    let phase = elapsed.truncatingRemainder(dividingBy: cycleLength)
    let offset: CGFloat = {
      if phase < startHold {
        return 0
      }
      if phase < startHold + travelTime {
        return -CGFloat(phase - startHold) * speed
      }
      return -overflow
    }()

    return tickerContent.offset(x: offset)
  }

  private var tickerContent: some View {
    HStack(spacing: 0) {
      ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
        Text(segment.text)
          .font(MenuBarTextMetrics.font)
          .kerning(MenuBarTextMetrics.kerning)
          .foregroundStyle(segment.foreground)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
  }

  private var fallbackText: some View {
    Text(accessibilityLabel)
      .font(MenuBarTextMetrics.font)
      .kerning(MenuBarTextMetrics.kerning)
      .foregroundStyle(segments.first?.foreground ?? Dial.Palette.textPrimary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var measuredContent: some View {
    tickerContent
      .opacity(0)
      .background(
        GeometryReader { proxy in
          Color.clear
            .onAppear { contentWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in
              contentWidth = width
            }
        }
      )
  }
}
