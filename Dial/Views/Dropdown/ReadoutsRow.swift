import SwiftUI

/// Personal track readouts: volume, current heat, and recency.
/// Three compact cards give the row a fuller information shape without
/// turning it into a metric grid.
struct ReadoutsRow: View {
  @Bindable var vm: NowPlayingViewModel
  let onOpenStats: () -> Void
  let onOpenHistory: () -> Void
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onOpenStats) {
        Readout(label: "TRACK · YTD",
                value: vm.playsYTD.formatted(),
                delta: playsDelta)
      }
      .buttonStyle(.pressable)
      .frame(maxWidth: .infinity)
      .help(playsHelp)
      .accessibilityLabel("Year to date track plays \(vm.playsYTD)")
      ReadoutDivider()
      Button(action: onOpenStats) {
        Readout(label: "RANK · 7D",
                value: vm.agg.rank7d.map { "#\($0)" } ?? "—",
                delta: vm.agg.firstListen && vm.agg.rank7d != nil ? "DEBUT" : "")
      }
      .buttonStyle(.pressable)
      .frame(maxWidth: .infinity)
      .help("7-day rank uses the same merged track identity as play count, then ranks by play count with most-recent play as the tie break.")
      .accessibilityLabel("Seven day rank \(vm.agg.rank7d.map { "#\($0)" } ?? "not ranked")")
      ReadoutDivider()
      Button(action: onOpenHistory) {
        Readout(label: "LAST · PLAYED",
                value: lastPlayedValue,
                delta: lastPlayedDelta)
      }
      .buttonStyle(.pressable)
      .frame(maxWidth: .infinity)
      .help("Last played ignores the current in-progress play and looks backward across imported, live, and recent catch-up history for the same merged track identity.")
      .accessibilityLabel("Last played \(lastPlayedValue)")
    }
    .padding(Dial.Layout.Readouts.railPadding)
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Layout.Readouts.railCornerRadius, style: .continuous),
      fill: theme.surface.opacity(0.54),
      edgeOpacity: 0.24,
      fillTopOpacity: 0.08,
      fillBottomOpacity: 0.018,
      sheenOpacity: 0.24,
      sheenLineWidth: 0.55,
      contactShadowOpacity: 0.18,
      contactShadowRadius: 1.5,
      contactShadowY: 0.75,
      innerShadowOpacity: 0.10)
    .padding(.horizontal, Dial.Layout.Readouts.outerHorizontalPadding)
    .padding(.vertical, Dial.Layout.Readouts.outerVerticalPadding)
  }

  private var lastPlayedValue: String {
    guard vm.track != nil else { return "—" }
    guard let lastPlayedAt = vm.agg.lastPlayedAt else { return "—" }
    let seconds = max(0, Int64(Date().timeIntervalSince1970) - lastPlayedAt)
    let days = seconds / 86_400
    switch days {
    case 0:
      return "TODAY"
    case 1:
      return "1D"
    case 2..<365:
      return "\(days)D"
    default:
      return "\(max(1, days / 365))Y"
    }
  }

  private var lastPlayedDelta: String {
    guard vm.track != nil, vm.agg.lastPlayedAt == nil else { return "" }
    return "NEW"
  }

  private var playsDelta: String {
    if vm.agg.firstListen { return "NEW" }
    guard vm.agg.albumPlaysYTD > vm.playsYTD else { return "" }
    return "ALB \(compactCount(vm.agg.albumPlaysYTD))"
  }

  private var playsHelp: String {
    let base = "Track YTD plays include imported history, live plays, and recent catch-up. Dial merges clean, explicit, remaster, punctuation, and alternate Spotify URI variants by title plus first artist."
    guard vm.agg.albumPlaysYTD > vm.playsYTD else { return base }
    return "\(base) Album YTD is \(vm.agg.albumPlaysYTD.formatted()) plays for \(vm.track?.albumName ?? "this album")."
  }

  private func compactCount(_ value: Int) -> String {
    if value >= 1_000 {
      return "\(value / 1_000)K"
    }
    return "\(value)"
  }
}

private struct Readout: View {
  let label: String
  let value: String
  let delta: String
  @Environment(\.dialTheme) private var theme

  private var deltaColor: Color {
    switch delta {
    case "NEW", "DEBUT": return theme.memoryAccent
    default:             return theme.accent
    }
  }

  private var valueColor: Color {
    value == "—" ? theme.textMuted.opacity(0.72) : theme.accent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Dial.Layout.Readouts.cellLabelValueSpacing) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(theme.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
      HStack(alignment: .lastTextBaseline, spacing: Dial.Layout.Readouts.valueDeltaSpacing) {
        Text(value)
          .font(.custom("GeistMono-Medium", size: Dial.Layout.Readouts.valueFontSize))
          .monospacedDigit()           // tabular nums — prevents jitter when 9 → 10
          .contentTransition(.numericText())
          .foregroundStyle(valueColor)
          .lineLimit(1)
          .minimumScaleFactor(0.76)
        Text(delta)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(deltaColor.opacity(0.9))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Dial.Layout.Readouts.cellHorizontalPadding)
  }
}

private struct ReadoutDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.white.opacity(0.10))
      .frame(width: 1, height: Dial.Layout.Readouts.dividerHeight)
      .overlay(Rectangle().fill(Color.black.opacity(0.20)).offset(x: 1))
  }
}
