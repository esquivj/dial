import SwiftUI

/// Inline panel that replaces the dropdown body when the user taps the info button.
/// Explains the badge vocabulary and pet life stages so first-timers know what's happening.
struct GlossaryPanel: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        section("BADGES") {
          glossaryRow(
            kind: .firstListen,
            color: Dial.Palette.accentAlt,
            label: "FIRST LISTEN",
            body: "The first time this track enters your history.")
          glossaryRow(
            kind: .newArtist,
            color: Dial.Palette.accentAlt,
            label: "NEW ARTIST",
            body: "The first track from an artist Dial has never seen in your history.")
          glossaryRow(
            kind: .rediscovered,
            color: Dial.Palette.accent,
            label: "REDISCOVERED",
            body: "A track you haven't heard in 90+ days. The badge detail tells you how long it's been.")
          glossaryRow(
            kind: .deepCut,
            color: Dial.Palette.accent,
            label: "DEEP CUT",
            body: "A rare track from an artist you already play a lot.")
          glossaryRow(
            kind: .onStreak,
            color: Dial.Palette.accentAlt,
            label: "ON STREAK",
            body: "10+ plays in 30 days AND ranked top-5 in the last 7 days. The track is in heavy rotation.")
          glossaryRow(
            kind: .albumMode,
            color: Dial.Palette.accentAlt,
            label: "ALBUM MODE",
            body: "Three or more consecutive tracks from the same album.")
          glossaryRow(
            kind: .repeatTrack,
            color: Dial.Palette.accentAlt,
            label: "REPEAT",
            body: "The same track three or more times in a row.")
          glossaryRow(
            kind: .play100,
            color: Dial.Palette.textPrimary,
            label: "MILESTONES",
            body: "10th, 50th, 100th plays and listening anniversaries.")
        }

        section("PET REACTIONS") {
          Text("The pet mirrors the current track context: new music, rediscoveries, XP from counted plays, level-ups, pauses, dormancy, and beat sync.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.textPrimary.opacity(0.85))
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
          Text("**1 XP** per minute of listening, **+50** for a new artist, **+25** for a new album. A 3+ day live streak applies a 1.25× multiplier; longer streaks scale up to 2× max.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.textPrimary.opacity(0.85))
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
        .foregroundStyle(Dial.Palette.accent)
      content()
    }
  }

  private func glossaryRow(kind: BadgeMemoryKind, color: Color, label: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      glossaryChip(kind: kind, color: color, label: label)
      Text(body)
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(Dial.Palette.textMuted)
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
      shape: RoundedRectangle(cornerRadius: 3, style: .continuous),
      color: color)
  }

  private func stageRow(name: String, xp: String) -> some View {
    HStack {
      Text(name)
        .font(Dial.Typography.sansBody)
        .foregroundStyle(Dial.Palette.textPrimary)
      Spacer()
      Text(xp)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.textMuted)
    }
  }
}
