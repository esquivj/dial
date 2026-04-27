import SwiftUI

/// PLAYS · 30D and RANK · 7D sit side-by-side as two distinct cards
/// (was a single full-width strip with a center divider). The card-pair
/// treatment matches the mockup's "two stat panels" structure and lets
/// each card carry its own subtle mint stroke + lift, reading as
/// "lit-glass slabs on a tray" rather than "one row split in half."
struct ReadoutsRow: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(spacing: 8) {
      Readout(label: "PLAYS · 30D",
              value: "\(vm.plays30d)",
              delta: vm.agg.firstListen ? "NEW" : "")
      Readout(label: "RANK · 7D",
              value: vm.agg.rank7d.map { "#\($0)" } ?? "—",
              delta: vm.agg.firstListen ? "DEBUT" : "")
    }
    // Tighter padding — 10pt horizontal, 4pt vertical. Was 14/6, which
    // double-padded inside the LCD panel and pushed the cards inward.
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
  }
}

private struct Readout: View {
  let label: String
  let value: String
  let delta: String

  /// Hot pink on celebration deltas (NEW / DEBUT), mint otherwise.
  /// Reinforces the same two-tone rule used elsewhere: mint = steady data,
  /// hot pink = "this track triggered something noteworthy."
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
          // Single tight inner shadow — pixel-edge brightening without
          // bloom. The previous flat-no-shadow treatment read as
          // "forgot to style," but the prior two-layer halo was tacky.
          // Radius 2 / opacity 0.30 sits in the goldilocks zone: enough
          // to read as "lit pixel," not enough to leak outward as a
          // colored glow.
          .shadow(color: Dial.Palette.amber.opacity(0.30), radius: 2, x: 0, y: 0)
        Text(delta)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(deltaColor.opacity(0.9))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    // Translucent gel chrome — same recipe as the transport playback
    // buttons (`GelTransportStyle`): translucent white fill that shows
    // the LCD panel surface through it, bright top-arc sheen, soft
    // white edge, dark drop shadow underneath. No colored halo.
    // Reads as "lit gel pill on the LCD" matching the rest of the
    // transport-zone gel language.
    .background(
      ZStack {
        // Translucent white fill — top-down gradient, lets the LCD
        // surface behind tint through.
        RoundedRectangle(cornerRadius: 8)
          .fill(LinearGradient(
            colors: [
              Color.white.opacity(0.18),
              Color.white.opacity(0.04),
            ],
            startPoint: .top, endPoint: .bottom))
        // Top-arc sheen — bright wet-glass highlight at the upper curve.
        RoundedRectangle(cornerRadius: 8)
          .trim(from: 0.05, to: 0.45)
          .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
          .blur(radius: 0.4)
      }
    )
    .overlay(
      // Plasticky edge stroke — same hue and weight as the gel buttons.
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
    )
    // Dark contact drop shadow — physical lighting, no colored bloom.
    // Matches the gel transport buttons' drop shadow recipe so the
    // cards and buttons share one chrome language.
    .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
  }
}
