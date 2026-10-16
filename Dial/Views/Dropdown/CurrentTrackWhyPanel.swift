import SwiftUI

struct CurrentTrackWhyPanel: View {
  @Bindable var vm: NowPlayingViewModel
  let badgeInsight: BadgeInsight?
  let onOpenStats: () -> Void
  let onOpenHistory: () -> Void

  @Environment(\.dialTheme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        header

        whyRow(
          title: "BADGE",
          value: badgeTitle,
          detail: badgeDetail,
          color: badgeColor,
          icon: badgeIcon)

        whyRow(
          title: "THEME",
          value: themeTitle,
          detail: themeDetail,
          color: theme.accent,
          icon: AnyView(DialIcon("sparkles").frame(width: 13, height: 13)))

        HStack(spacing: 7) {
          factChip(
            label: "TRACK · YTD",
            value: "\(vm.playsYTD)",
            help: "Track YTD plays include imported history, live plays, and recent catch-up. Dial merges alternate Spotify URI variants by normalized title plus first artist.")
          if vm.agg.albumPlaysYTD > vm.playsYTD {
            factChip(
              label: "ALBUM",
              value: "\(vm.agg.albumPlaysYTD)",
              help: "Album YTD counts every track on this album by the same first artist. Useful for projects like ICEMAN where the memory is album-level, not just one track.")
          }
          factChip(
            label: "RANK · 7D",
            value: vm.agg.rank7d.map { "#\($0)" } ?? "-",
            help: "7-day rank uses merged track identity, then ranks by play count with latest play as the tie break.")
          factChip(
            label: "LAST",
            value: lastPlayedValue,
            help: "Last played ignores the current in-progress play and looks backward through imported, live, and recent catch-up history.")
        }

        whyRow(
          title: "IDENTITY",
          value: identityTitle,
          detail: identityDetail,
          color: theme.textPrimary.opacity(0.88),
          icon: AnyView(DialIcon("clock.arrow.circlepath").frame(width: 13, height: 13)))

        footerActions
      }
      .padding(EdgeInsets(top: 14, leading: 15, bottom: 16, trailing: 15))
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("WHY THIS SPIN")
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.accent)

      if let track = vm.track {
        Text(track.name)
          .font(Dial.Typography.monoTitle)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Text("\(track.artistName) · \(track.albumName)")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.82))
          .lineLimit(1)
          .minimumScaleFactor(0.70)
      } else {
        Text("No current track")
          .font(Dial.Typography.monoTitle)
          .foregroundStyle(theme.textPrimary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 9, trailing: 10))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      color: theme.accent,
      fillOpacity: 0.035,
      edgeOpacity: 0.15)
  }

  private func whyRow(
    title: String,
    value: String,
    detail: String,
    color: Color,
    icon: AnyView
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      icon
        .foregroundStyle(color)
        .frame(width: 18, height: 18)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(title)
            .font(Dial.Typography.monoTiny)
            .tracking(1.2)
            .foregroundStyle(theme.textMuted.opacity(0.74))
          Text(value.uppercased())
            .font(Dial.Typography.monoLabel)
            .tracking(1.0)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        }
        Text(detail)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.82))
          .lineLimit(2)
          .minimumScaleFactor(0.72)
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
    .dialRecessedPanel(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      fill: theme.surface.opacity(0.36),
      strokeOpacity: 0.18)
    .help(detail)
  }

  private func factChip(label: String, value: String, help: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(0.9)
        .foregroundStyle(theme.textMuted.opacity(0.74))
        .lineLimit(1)
        .minimumScaleFactor(0.70)
      Text(value)
        .font(Dial.Typography.monoValue)
        .monospacedDigit()
        .foregroundStyle(value == "-" ? theme.textMuted.opacity(0.66) : theme.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.70)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous),
      fill: theme.surface.opacity(0.42),
      edgeOpacity: 0.20,
      fillTopOpacity: 0.07,
      fillBottomOpacity: 0.02,
      sheenOpacity: 0.16,
      sheenLineWidth: 0.5,
      contactShadowOpacity: 0.12,
      contactShadowRadius: 1.2,
      contactShadowY: 0.6,
      innerShadowOpacity: 0.08)
    .help(help)
  }

  private var footerActions: some View {
    HStack(spacing: 8) {
      Button(action: onOpenStats) {
        footerButtonLabel("OPEN STATS", icon: "chart.bar.fill")
      }
      .buttonStyle(.pressable)
      .help("Open the stats surface for the full library view.")

      Button(action: onOpenHistory) {
        footerButtonLabel("OPEN HISTORY", icon: "clock.arrow.circlepath")
      }
      .buttonStyle(.pressable)
      .help("Open recent listening history.")
    }
  }

  private func footerButtonLabel(_ label: String, icon: String) -> some View {
    HStack(spacing: 6) {
      DialIcon(icon)
        .frame(width: 12, height: 12)
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(1.0)
    }
    .foregroundStyle(theme.textPrimary.opacity(0.86))
    .frame(maxWidth: .infinity)
    .frame(height: 28)
    .background(theme.surface.opacity(0.34))
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .stroke(theme.hairline.opacity(0.32), lineWidth: 1))
  }

  private var badgeTitle: String {
    badgeInsight?.kind.label ?? "Familiar"
  }

  private var badgeDetail: String {
    guard let badgeInsight else {
      return vm.track == nil
        ? "Play a Spotify track for personal context."
        : "No special badge on this spin; the track is already part of the library memory."
    }
    return badgeInsight.explanation.isEmpty
      ? "\(badgeInsight.kind.label): \(badgeInsight.detail)"
      : badgeInsight.explanation
  }

  private var badgeColor: Color {
    guard let kind = badgeInsight?.kind else { return theme.textMuted.opacity(0.80) }
    switch kind {
    case .firstListen, .newArtist, .onStreak, .repeatTrack, .albumMode:
      return theme.memoryAccent
    case .rediscovered, .deepCut:
      return theme.accent
    case .play10, .play50, .play100, .anniversary:
      return theme.textPrimary
    }
  }

  private var badgeIcon: AnyView {
    if let kind = badgeInsight?.kind {
      return AnyView(BadgePixelIcon(kind: kind, color: badgeColor, size: 14))
    }
    return AnyView(Circle().fill(badgeColor).frame(width: 7, height: 7))
  }

  private var themeTitle: String {
    guard let decision = vm.soundThemeDecision else { return vm.soundTheme.label }
    return "\(decision.theme.label) · \(Int((decision.confidence * 100).rounded()))%"
  }

  private var themeDetail: String {
    guard let decision = vm.soundThemeDecision else {
      return "No current sound decision; Dial is using the active cartridge theme."
    }
    return "\(decision.source.label): \(decision.reason)"
  }

  private var identityTitle: String {
    guard let track = vm.track else { return "Waiting" }
    let artist = track.artistName.isEmpty ? "unknown artist" : track.artistName
    return "\(track.name) · \(artist)"
  }

  private var identityDetail: String {
    "Counts use exact Spotify URI first, then normalized title plus first artist to catch remasters, explicit variants, and imported-history aliases."
  }

  private var lastPlayedValue: String {
    guard vm.track != nil else { return "-" }
    guard let lastPlayedAt = vm.agg.lastPlayedAt else { return "NEW" }
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
}
