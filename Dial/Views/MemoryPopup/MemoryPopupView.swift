// Dial/Views/MemoryPopup/MemoryPopupView.swift
import SwiftUI

/// The track-change memory pop-up: a tiny piece of Dial hardware, one
/// smoked-plastic bezel around one LCD readout. Line one stamps the memory
/// ("REDISCOVERED  Last played Mar 2023"); line two names the track.
/// Built only from the shared materials (chassis plastic, LCD panel,
/// scanlines) and the existing badge sprites.
struct MemoryPopupView: View {
  static let size = CGSize(width: 300, height: 54)

  let content: MemoryPopupContent
  @Environment(\.dialTheme) private var theme

  private static let bezelInset: CGFloat = 4

  var body: some View {
    let bezel = RoundedRectangle(cornerRadius: Dial.Radius.lcd, style: .continuous)
    lcd
      .padding(Self.bezelInset)
      .frame(width: Self.size.width, height: Self.size.height)
      .dialChassisPlastic(shape: bezel)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(content.kind.label): \(content.line). \(trackLine)")
      .accessibilityAddTraits(.isButton)
      .accessibilityHint("Opens Dial.")
  }

  private var lcd: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        BadgePixelIcon(kind: content.kind, color: color, size: 11)
        Text(content.label)
          .font(Dial.Typography.pixelBadge)
          .tracking(1.2)
          .foregroundStyle(color)
          .fixedSize()
        Text(content.line)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Text(trackLine)
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(theme.textMuted)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .overlay { LCDScanlines(opacity: 0.08) }
    .modifier(RecessedScreen(depth: 0.45, height: 8))
    .lcdPanel(cornerRadius: Dial.Radius.panel - Self.bezelInset / 2)
  }

  private var trackLine: String {
    content.artistName.isEmpty ? content.trackName : "\(content.trackName) · \(content.artistName)"
  }

  /// Same mapping as the HUD badge chip: first listens and new artists are
  /// memory pink, rediscoveries and deep cuts take the cartridge accent,
  /// and milestones print in primary text.
  private var color: Color {
    switch content.kind.category {
    case .discovery:
      return content.kind == .firstListen || content.kind == .newArtist ? theme.memoryAccent : theme.accent
    case .pattern:
      return theme.memoryAccent
    case .milestone:
      return theme.textPrimary
    }
  }
}
