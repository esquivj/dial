import SwiftUI

enum BadgeKind { case firstListen, rediscovered, onStreak, none }

struct BadgeRow: View {
  let kind: BadgeKind
  let detail: String

  var body: some View {
    if kind == .none {
      EmptyView()
    } else {
      HStack(spacing: 8) {
        chip
        Text(detail)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted)
          .lineLimit(1)
      }
      .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Dial.Palette.ground)
      .overlay(alignment: .top) {
        Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      }
    }
  }

  private var chip: some View {
    let (fg, bg, border, label): (Color, Color, Color, String) = {
      switch kind {
      case .firstListen:
        return (Dial.Palette.amber,
                Dial.Palette.amber.opacity(0.08),
                Dial.Palette.amber.opacity(0.35),
                "FIRST LISTEN")
      case .rediscovered:
        return (Dial.Palette.muted,
                Dial.Palette.muted.opacity(0.10),
                Dial.Palette.muted.opacity(0.40),
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
    .background(bg)
    .overlay(RoundedRectangle(cornerRadius: 3).stroke(border, lineWidth: 1))
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
