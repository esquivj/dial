import SwiftUI

/// Inline panel that replaces the dropdown body when the user taps the info button.
/// Explains the badge vocabulary and pet life stages so first-timers know what's happening.
struct GlossaryPanel: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        section("BADGES") {
          glossaryRow(
            symbol: chipSymbol(color: Dial.Palette.amber),
            label: "FIRST LISTEN",
            body: "Triggered the first time you stream a track. Worth a +50 XP variety bonus if it's also a new artist.")
          glossaryRow(
            symbol: chipSymbol(color: Dial.Palette.ivory),
            label: "REDISCOVERED",
            body: "A track you haven't heard in 90+ days. The artist row will show how long it's been.")
          glossaryRow(
            symbol: chipSymbol(color: Dial.Palette.orange),
            label: "ON STREAK",
            body: "10+ plays in 30 days AND ranked top-5 in the last 7 days. The track is in heavy rotation.")
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
          Text("**1 XP** per minute of listening, **+50** for a new artist, **+25** for a new album. A 3+ day listening streak applies a 1.25× multiplier; longer streaks scale up to 2× max.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.ivory.opacity(0.85))
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
        .foregroundStyle(Dial.Palette.amber)
      content()
    }
  }

  private func glossaryRow<Symbol: View>(symbol: Symbol, label: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      symbol
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(Dial.Typography.monoLabel)
          .tracking(1.2)
          .foregroundStyle(Dial.Palette.ivory)
        Text(body)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func chipSymbol(color: Color) -> some View {
    Triangle()
      .fill(color)
      .frame(width: 8, height: 6)
      .padding(.top, 4)
  }

  private func stageRow(name: String, xp: String) -> some View {
    HStack {
      Text(name)
        .font(Dial.Typography.sansBody)
        .foregroundStyle(Dial.Palette.ivory)
      Spacer()
      Text(xp)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.muted)
    }
  }
}

private struct Triangle: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: .init(x: r.midX, y: r.minY))
    p.addLine(to: .init(x: r.maxX, y: r.maxY))
    p.addLine(to: .init(x: r.minX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}
