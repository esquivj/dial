import SwiftUI

struct SessionTimeline: View {
  let plays: [PlayAggregations.SessionPlay]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("LAST 60 MIN")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.muted)
        Spacer()
        Text("\(plays.count) TRACKS")
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.muted)
      }
      GeometryReader { proxy in
        let totalMs = max(plays.reduce(0) { $0 + Int($1.msPlayed) }, 1)
        let spacing: CGFloat = 3
        let usable = proxy.size.width - spacing * CGFloat(max(plays.count - 1, 0))
        HStack(alignment: .bottom, spacing: spacing) {
          ForEach(Array(plays.reversed().enumerated()), id: \.offset) { idx, p in
            let isCurrent = idx == plays.count - 1
            let share = usable * CGFloat(Int(p.msPlayed)) / CGFloat(totalMs)
            Rectangle()
              .fill(Dial.Palette.amber.opacity(isCurrent ? 1.0 : 0.22 + Double(idx) * 0.04))
              .frame(width: max(share, 2),
                     height: isCurrent ? 22 : CGFloat(10 + min(idx, 6) * 2))
          }
        }
      }
      .frame(height: 22)
    }
    .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14))
  }
}
