// Dial/Views/DesktopMemory/DesktopMemoryView.swift
import AppKit
import SwiftUI

/// Sizes for the desktop memory object, outside the view so the window
/// code can use them too.
enum DesktopMemoryMetrics {
  static let padding: CGFloat = 12
  static let artSize: CGFloat = 192
  static let artToLCD: CGFloat = 10
  static let lcdHeight: CGFloat = 62
  static let pausedArtOpacity: Double = 0.55
  static let notPlayingArtOpacity: Double = 0.40

  /// The chassis itself.
  static let size = CGSize(
    width: artSize + padding * 2,
    height: padding * 2 + artSize + artToLCD + lcdHeight)
  /// Room around the chassis for its contact shadow. The window is this
  /// much bigger on every side.
  static let shadowMargin: CGFloat = 20
  static let windowSize = CGSize(
    width: size.width + shadowMargin * 2,
    height: size.height + shadowMargin * 2)
}

/// The desktop memory object (docs/design/desktop-memory.md): the album in
/// a smoke-gel chassis over one LCD well. The LCD stamps the track's memory
/// the way the memory pop-up does, so the two read as the same device.
/// It shows no controls; clicking it, or pressing it with VoiceOver, opens
/// the HUD.
struct DesktopMemoryView: View {
  private typealias Metrics = DesktopMemoryMetrics

  let content: DesktopMemoryContent
  let artwork: NSImage?
  /// Opens the HUD. Clicks go to the window's host view; VoiceOver's press
  /// comes here, to the SwiftUI element.
  let onOpen: () -> Void
  @Environment(\.dialTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var trackID: String { content.track?.uri ?? "none" }

  var body: some View {
    let chassis = RoundedRectangle(cornerRadius: Dial.Radius.device, style: .continuous)
    VStack(spacing: Metrics.artToLCD) {
      art
      LCDReadoutWell(cornerRadius: Dial.Radius.panel) { readout }
        .frame(height: Metrics.lcdHeight)
    }
    .padding(Metrics.padding)
    .frame(width: Metrics.size.width, height: Metrics.size.height)
    .dialChassisPlastic(shape: chassis)
    .shadow(color: .black.opacity(0.40), radius: 10, x: 0, y: 6)
    .padding(Metrics.shadowMargin)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(content.accessibilityLabel)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Opens Dial.")
    .accessibilityAction { onOpen() }
  }

  // MARK: - Art

  private var art: some View {
    ZStack {
      artImage
        .id(trackID)
        .transition(.opacity)
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: trackID)
    .frame(width: Metrics.artSize, height: Metrics.artSize)
    .opacity(artOpacity)
    .overlay { sheen }
    .dialMediaFrame(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous),
      showsGloss: false)
  }

  /// A soft reflection across the cover's glass. The HUD's corner glare is
  /// sized for small artwork and reads as a block at this size.
  private var sheen: some View {
    LinearGradient(
      colors: [
        Color.white.opacity(0.12),
        Color.white.opacity(0.03),
        Color.clear,
      ],
      startPoint: .topLeading,
      endPoint: UnitPoint(x: 0.6, y: 0.6))
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private var artImage: some View {
    if let artwork {
      Image(nsImage: artwork)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fill)
    } else {
      fallbackArt
    }
  }

  /// The HUD's fallback, scaled up: the Dial icon before any track, a
  /// music note when a track's cover is missing.
  private var fallbackArt: some View {
    ZStack {
      Rectangle()
        .fill(theme.ground)
      Rectangle()
        .fill(theme.surface.opacity(0.58))
        .overlay(LCDScanlines(pitch: 3, opacity: 0.08, color: .black))
      if content.track == nil, let icon = NSImage(named: "dial-app-icon") {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .padding(44)
          .opacity(0.88)
      } else {
        DialThickIcon("music.note", size: 44)
          .foregroundStyle(theme.textMuted.opacity(0.72))
      }
    }
  }

  private var artOpacity: Double {
    switch content.playback {
    case .playing: 1
    case .paused: Metrics.pausedArtOpacity
    case .notPlaying: content.track == nil ? 1 : Metrics.notPlayingArtOpacity
    }
  }

  // MARK: - LCD

  private var readout: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        if case let .memory(kind, _, _) = content.stamp {
          BadgePixelIcon(kind: kind, color: stampColor, size: 11)
        }
        Text(content.stampLabel)
          .font(Dial.Typography.pixelBadge)
          .tracking(1.2)
          .foregroundStyle(stampColor)
          .lineLimit(1)
        Spacer(minLength: 4)
        if let tag = content.playbackTag {
          Text(tag)
            .font(Dial.Typography.pixelBadge)
            .tracking(1.2)
            .foregroundStyle(theme.textMuted)
            .fixedSize()
        }
      }
      if let line = content.primaryLine {
        Text(line)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      let lines = content.secondaryLines
      if let longest = lines.first {
        ViewThatFits(in: .horizontal) {
          secondaryText(longest)
          if lines.count > 1 {
            secondaryText(lines[1])
          }
        }
      }
    }
    .id(content)
    .transition(.opacity)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: content)
  }

  private func secondaryText(_ line: String) -> some View {
    Text(line)
      .font(Dial.Typography.sansCaption)
      .foregroundStyle(theme.textMuted)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  /// Same mapping as the HUD badge chip and the memory pop-up: first
  /// listens and new artists are memory pink, rediscoveries and deep cuts
  /// take the cartridge accent, milestones print in primary text.
  private var stampColor: Color {
    switch content.stamp {
    case let .memory(kind, _, _):
      switch kind.category {
      case .discovery:
        return kind == .firstListen || kind == .newArtist ? theme.memoryAccent : theme.accent
      case .pattern:
        return theme.memoryAccent
      case .milestone:
        return theme.textPrimary
      }
    case .yearToDate, .nowPlaying:
      return theme.accent
    case .notPlaying:
      return theme.textMuted
    }
  }
}
