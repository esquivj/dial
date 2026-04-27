import SwiftUI

enum BadgeKind { case firstListen, rediscovered, onStreak, none }

struct BadgeRow: View {
  let kind: BadgeKind
  let detail: String

  var body: some View {
    // Always render the row at fixed height regardless of badge state.
    // Earlier code returned `EmptyView()` when kind == .none, which
    // caused the rest of the LCD content (specifically the spectrum
    // visualizer below) to slide UP into the badge's vertical slot —
    // a layout shift on every track change between badged and unbadged
    // tracks. Reserving the row's space stabilizes the layout so
    // children below stay anchored regardless of badge presence.
    HStack(spacing: 8) {
      if kind != .none {
        chip
        Text(detail)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
  }

  private var chip: some View {
    let (fg, bg, border, label): (Color, Color, Color, String) = {
      switch kind {
      case .firstListen:
        // Magenta (not cyan) — this is the celebration moment of the row.
        // Cyan is the steady-state data tone; magenta is reserved for
        // "something noteworthy is happening with this track."
        return (Dial.Palette.orange,
                Dial.Palette.orange.opacity(0.10),
                Dial.Palette.orange.opacity(0.40),
                "FIRST LISTEN")
      case .rediscovered:
        // Mockup section 5 BADGES shows ▲ REDISCOVERED in mint, not muted.
        // Earlier code kept it muted to imply "quiet rediscovery" but the
        // spec is the source of truth — REDISCOVERED is a celebration tone
        // alongside FIRST LISTEN / ON STREAK, just with the cyan-side
        // primary accent (mint) rather than the magenta-side secondary.
        return (Dial.Palette.amber,
                Dial.Palette.amber.opacity(0.10),
                Dial.Palette.amber.opacity(0.40),
                "REDISCOVERED")
      case .onStreak:
        return (Dial.Palette.orange,
                Dial.Palette.orange.opacity(0.10),
                Dial.Palette.orange.opacity(0.35),
                "ON STREAK")
      case .none:
        return (.clear, .clear, .clear, "")
      }
    }()
    return HStack(spacing: 6) {
      ChipTriangle().fill(fg).frame(width: 8, height: 6)
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(fg)
    }
    .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
    .background(bg.opacity(0.6))  // 0.10 base × 0.6 = 0.06 effective fill
    .overlay(RoundedRectangle(cornerRadius: 3).stroke(border.opacity(0.55), lineWidth: 0.6))
    .clipShape(RoundedRectangle(cornerRadius: 3))
  }
}

private struct ChipTriangle: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: .init(x: r.midX, y: r.minY))
    p.addLine(to: .init(x: r.maxX, y: r.maxY))
    p.addLine(to: .init(x: r.minX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}
