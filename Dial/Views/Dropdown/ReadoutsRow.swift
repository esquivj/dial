import SwiftUI

/// Personal track readouts: volume, current heat, and recency.
/// Three compact cards give the row a fuller information shape without
/// turning it into a metric grid.
struct ReadoutsRow: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(spacing: 0) {
      Readout(label: "PLAYS · YTD",
              value: "\(vm.playsYTD)",
              delta: vm.agg.firstListen ? "NEW" : "")
      ReadoutDivider()
      Readout(label: "RANK · 7D",
              value: vm.agg.rank7d.map { "#\($0)" } ?? "—",
              delta: vm.agg.firstListen && vm.agg.rank7d != nil ? "DEBUT" : "")
      ReadoutDivider()
      Readout(label: "LAST · PLAYED",
              value: lastPlayedValue,
              delta: lastPlayedDelta)
    }
    .padding(Dial.Layout.Readouts.railPadding)
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Layout.Readouts.railCornerRadius, style: .continuous),
      fill: Dial.Palette.surface.opacity(0.44),
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
}

private struct Readout: View {
  let label: String
  let value: String
  let delta: String

  private var deltaColor: Color {
    switch delta {
    case "NEW", "DEBUT": return Dial.Palette.accentAlt
    default:             return Dial.Palette.accent
    }
  }

  private var valueColor: Color {
    value == "—" ? Dial.Palette.textMuted.opacity(0.72) : Dial.Palette.accent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Dial.Layout.Readouts.cellLabelValueSpacing) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(Dial.Palette.textMuted)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
      HStack(alignment: .lastTextBaseline, spacing: Dial.Layout.Readouts.valueDeltaSpacing) {
        Text(value)
          .font(.custom("IBMPlexMono-Medium", size: Dial.Layout.Readouts.valueFontSize))
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
