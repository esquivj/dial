import SwiftUI

struct ReadoutsRow: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(spacing: 0) {
      Readout(label: "PLAYS · 30D",
              value: "\(vm.plays30d)",
              delta: vm.agg.firstListen ? "NEW" : "")
      Divider().background(Color.white.opacity(0.1))
      Readout(label: "RANK · 7D",
              value: vm.agg.rank7d.map { "#\($0)" } ?? "—",
              delta: vm.agg.firstListen ? "DEBUT" : "")
    }
    .background(Color(red: 0.055, green: 0.059, blue: 0.071))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
  }
}

private struct Readout: View {
  let label: String
  let value: String
  let delta: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      HStack(alignment: .lastTextBaseline, spacing: 6) {
        Text(value)
          .font(Dial.Typography.monoValue)
          .foregroundStyle(Dial.Palette.amber)
        Text(delta)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.amber.opacity(0.9))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
  }
}
