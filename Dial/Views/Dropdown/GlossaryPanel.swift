import SwiftUI

/// Inline panel that replaces the dropdown body when the user taps the info button.
/// Explains the badge vocabulary and pet life stages so first-timers know what's happening.
struct GlossaryPanel: View {
  @Environment(\.dialTheme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        section("BADGES") {
          glossaryRow(
            kind: .firstListen,
            color: theme.memoryAccent,
            label: "FIRST LISTEN",
            body: "The first time this track enters your history.")
          glossaryRow(
            kind: .newArtist,
            color: theme.memoryAccent,
            label: "NEW ARTIST",
            body: "The first track from an artist Dial has never seen in your history.")
          glossaryRow(
            kind: .rediscovered,
            color: theme.accent,
            label: "REDISCOVERED",
            body: "A track you haven't heard in 90+ days. The badge detail tells you how long it's been.")
          glossaryRow(
            kind: .deepCut,
            color: theme.accent,
            label: "DEEP CUT",
            body: "A rare track from an artist you already play a lot.")
          glossaryRow(
            kind: .onStreak,
            color: theme.memoryAccent,
            label: "ON STREAK",
            body: "10+ plays in 30 days AND ranked top-5 in the last 7 days. The track is in heavy rotation.")
          glossaryRow(
            kind: .albumMode,
            color: theme.memoryAccent,
            label: "ALBUM MODE",
            body: "Three or more consecutive tracks from the same album.")
          glossaryRow(
            kind: .repeatTrack,
            color: theme.memoryAccent,
            label: "REPEAT",
            body: "The same track three or more times in a row.")
          glossaryRow(
            kind: .play100,
            color: theme.textPrimary,
            label: "MILESTONES",
            body: "10th, 50th, 100th plays and listening anniversaries.")
        }

        section("PET REACTIONS") {
          Text("The pet mirrors listening context: new music, rediscoveries, XP growth, level-ups, quiet sessions, beat sync, and rare trick cameos after real badge moments.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(theme.textPrimary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }

        section("PET STAGES") {
          stageRow(name: "Egg",       xp: "0 XP")
          stageRow(name: "Hatching",  xp: "500 XP")
          stageRow(name: "Hatchling", xp: "1,000 XP")
          stageRow(name: "Juvenile",  xp: "5,000 XP")
          stageRow(name: "Companion", xp: "25,000 XP")
          stageRow(name: "Elder",     xp: "100,000 XP · 30 days from install")
        }

        section("XP") {
          Text("Every counted play earns at least **1 XP**, then rounds by listening time. New artists add **+50**, new albums add **+25**. A 3+ day live streak applies a 1.25× multiplier; longer streaks scale up to 2× max.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(theme.textPrimary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(theme.accent)
      content()
    }
  }

  private func glossaryRow(kind: BadgeMemoryKind, color: Color, label: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      glossaryChip(kind: kind, color: color, label: label)
      Text(body)
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(theme.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 2)
    }
  }

  private func glossaryChip(kind: BadgeMemoryKind, color: Color, label: String) -> some View {
    HStack(spacing: 6) {
      BadgePixelIcon(kind: kind, color: color, size: 14)
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(color)
    }
    .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.printed, style: .continuous),
      color: color)
  }

  private func stageRow(name: String, xp: String) -> some View {
    HStack {
      Text(name)
        .font(Dial.Typography.sansBody)
        .foregroundStyle(theme.textPrimary)
      Spacer()
      Text(xp)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(theme.textMuted)
    }
  }
}
