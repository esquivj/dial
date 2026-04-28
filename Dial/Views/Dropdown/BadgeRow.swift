import SwiftUI

struct BadgeRow: View {
  let insight: BadgeInsight?
  let hasTrack: Bool

  var body: some View {
    // Always render the row at fixed height regardless of badge state.
    // Earlier code returned `EmptyView()` when kind == .none, which
    // caused the rest of the LCD content (specifically the spectrum
    // visualizer below) to slide UP into the badge's vertical slot —
    // a layout shift on every track change between badged and unbadged
    // tracks. Reserving the row's space stabilizes the layout so
    // children below stay anchored regardless of badge presence.
    HStack(spacing: 8) {
      if let insight {
        chip(insight.kind)
        Text(insight.detail)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textPrimary.opacity(0.78))
          .lineLimit(1)
          .minimumScaleFactor(0.86)
      } else {
        fallbackChip
        Text(fallbackDetail)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.78))
          .lineLimit(1)
          .minimumScaleFactor(0.86)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
  }

  private var fallbackChip: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(Dial.Palette.textMuted.opacity(hasTrack ? 0.65 : 0.35))
        .frame(width: 6, height: 6)
      Text(hasTrack ? "FAMILIAR" : "WAITING")
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(Dial.Palette.textMuted.opacity(hasTrack ? 0.78 : 0.48))
    }
    .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: 3, style: .continuous),
      color: Dial.Palette.textMuted,
      fillOpacity: 0.035,
      edgeOpacity: 0.16)
  }

  private var fallbackDetail: String {
    guard hasTrack else { return "Play a Spotify track for personal context" }
    return "Regular rotation · no special badge on this spin"
  }

  private func chip(_ kind: BadgeMemoryKind) -> some View {
    let (fg, label): (Color, String) = {
      switch kind {
      case .firstListen:
        // Magenta (not cyan) — this is the celebration moment of the row.
        // Cyan is the steady-state data tone; magenta is reserved for
        // "something noteworthy is happening with this track."
        return (Dial.Palette.accentAlt, "FIRST LISTEN")
      case .newArtist:
        return (Dial.Palette.accentAlt, "NEW ARTIST")
      case .rediscovered:
        // Mockup section 5 BADGES shows ▲ REDISCOVERED in mint, not muted.
        // Earlier code kept it muted to imply "quiet rediscovery" but the
        // spec is the source of truth — REDISCOVERED is a celebration tone
        // alongside FIRST LISTEN / ON STREAK, just with the cyan-side
        // primary accent (mint) rather than the magenta-side secondary.
        return (Dial.Palette.accent, "REDISCOVERED")
      case .deepCut:
        return (Dial.Palette.accent, "DEEP CUT")
      case .onStreak:
        return (Dial.Palette.accentAlt, "ON STREAK")
      case .repeatTrack:
        return (Dial.Palette.accentAlt, "REPEAT")
      case .albumMode:
        return (Dial.Palette.accentAlt, "ALBUM MODE")
      case .play10:
        return (Dial.Palette.textPrimary, "10TH PLAY")
      case .play50:
        return (Dial.Palette.textPrimary, "50TH PLAY")
      case .play100:
        return (Dial.Palette.textPrimary, "100TH PLAY")
      case .anniversary:
        return (Dial.Palette.textPrimary, "ANNIVERSARY")
      }
    }()
    return HStack(spacing: 6) {
      BadgePixelIcon(kind: kind, color: fg, size: 14)
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(fg)
    }
    .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: 3, style: .continuous),
      color: fg)
  }
}
