import SwiftUI

/// What a hotkey flash says: one transport glyph, one short stamp, and for
/// volume a 10-segment meter.
struct HotkeyFlashContent: Equatable {
  enum Tone: Equatable { case primary, accent, memory, muted }

  let symbol: String
  let label: String
  var level: Int?
  var tone: Tone = .primary

  static let play = HotkeyFlashContent(symbol: "play.fill", label: "PLAY")
  static let pause = HotkeyFlashContent(symbol: "pause.fill", label: "PAUSE")
  static let next = HotkeyFlashContent(symbol: "forward.fill", label: "NEXT")
  static let previous = HotkeyFlashContent(symbol: "backward.fill", label: "PREVIOUS")
  static let liked = HotkeyFlashContent(symbol: "heart.fill", label: "LIKED", tone: .memory)
  static let unliked = HotkeyFlashContent(symbol: "heart", label: "UNLIKED", tone: .muted)
  static let noTrack = HotkeyFlashContent(symbol: "music.note", label: "NO TRACK", tone: .muted)
  static let reconnect = HotkeyFlashContent(symbol: "heart.slash", label: "RECONNECT", tone: .muted)
  static let noPlayer = HotkeyFlashContent(symbol: "exclamationmark.triangle", label: "NO PLAYER", tone: .muted)
  static let desktopMemoryOn = HotkeyFlashContent(symbol: "rectangle.inset.filled", label: "DESKTOP MEMORY ON")
  static let desktopMemoryOff = HotkeyFlashContent(symbol: "rectangle.inset.filled", label: "DESKTOP MEMORY OFF", tone: .muted)

  static func volume(_ percent: Int) -> HotkeyFlashContent {
    let clamped = max(0, min(100, percent))
    let symbol: String
    switch clamped {
    case 0:       symbol = "speaker.slash.fill"
    case ..<50:   symbol = "speaker.wave.1.fill"
    default:      symbol = "speaker.wave.3.fill"
    }
    return HotkeyFlashContent(symbol: symbol, label: "VOL \(clamped)%", level: clamped, tone: .accent)
  }
}

/// The hotkey confirmation: the memory pop-up's LCD strip, shortened to a
/// single line. It shows for about a second under the menu bar item.
struct HotkeyFlashView: View {
  static let size = CGSize(width: 184, height: 34)
  static let meterSegments = 10

  let content: HotkeyFlashContent
  @Environment(\.dialTheme) private var theme

  var body: some View {
    LCDReadoutStrip(size: Self.size) { readout }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(content.label.capitalized)
  }

  private var readout: some View {
    HStack(spacing: 7) {
      DialThickIcon(content.symbol, size: 11, weight: 0.45)
        .foregroundStyle(color)
        .frame(width: 14, height: 14)
      Text(content.label)
        .font(Dial.Typography.pixelBadge)
        .tracking(1.2)
        .foregroundStyle(color)
        .fixedSize()
      if let level = content.level {
        Spacer(minLength: 4)
        meter(level: level)
      }
    }
    .frame(maxWidth: .infinity, alignment: content.level == nil ? .center : .leading)
  }

  private func meter(level: Int) -> some View {
    let lit = Self.litSegments(for: level)
    return HStack(spacing: 2) {
      ForEach(0..<Self.meterSegments, id: \.self) { index in
        Rectangle()
          .fill(index < lit ? color : theme.textMuted.opacity(0.18))
          .frame(width: 4, height: 9)
      }
    }
  }

  /// 0% lights nothing, any audible volume lights at least one segment.
  static func litSegments(for level: Int) -> Int {
    let clamped = max(0, min(100, level))
    guard clamped > 0 else { return 0 }
    return max(1, Int((Double(clamped) / 100 * Double(meterSegments)).rounded()))
  }

  private var color: Color {
    switch content.tone {
    case .primary: return theme.textPrimary
    case .accent:  return theme.accent
    case .memory:  return theme.memoryAccent
    case .muted:   return theme.textMuted
    }
  }
}
