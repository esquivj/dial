import SwiftUI

struct ReadoutsRow: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(spacing: 0) {
      Readout(label: "PLAYS · 30D",
              value: "\(vm.plays30d)",
              delta: vm.agg.firstListen ? "NEW" : "")
      Divider().background(Dial.Palette.hairline)
      Readout(label: "RANK · 7D",
              value: vm.agg.rank7d.map { "#\($0)" } ?? "—",
              delta: vm.agg.firstListen ? "DEBUT" : "")
    }
    .background(Dial.Palette.subtle)
    .overlay(alignment: .top) {
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
    }
  }
}

private struct Readout: View {
  let label: String
  let value: String
  let delta: String

  /// Magenta on celebration deltas (NEW / DEBUT), cyan otherwise. Reinforces
  /// the same two-tone rule used elsewhere: cyan = steady data, magenta =
  /// "this track triggered something noteworthy."
  private var deltaColor: Color {
    switch delta {
    case "NEW", "DEBUT": return Dial.Palette.orange
    default:             return Dial.Palette.amber
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      HStack(alignment: .lastTextBaseline, spacing: 6) {
        Text(value)
          .font(Dial.Typography.monoValue)
          .monospacedDigit()           // tabular nums — prevents jitter when 9 → 10
          .contentTransition(.numericText())
          .foregroundStyle(Dial.Palette.amber)
          // 0.20 (was 0.55) — demoted from "blazing" to "lit." The numerals
          // are steady-state data; the heavy glow was contributing to the
          // overall cyan ambient noise. Bright glow is now reserved for
          // actual events (track-pulse, peak markers, hover states).
          .shadow(color: Dial.Palette.amber.opacity(0.20), radius: 6, x: 0, y: 0)
        Text(delta)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(deltaColor.opacity(0.9))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // Padding 8 (was 12). Combined with the 20pt monoValue (was 28pt),
    // the row now lands at ~45pt (was ~65pt) — reclaims ~20pt of HUD
    // vertical and stops feeling oversized when the values are 0 / —.
    .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
  }
}
