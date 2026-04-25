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
      HStack(alignment: .bottom, spacing: 3) {
        // `plays` from the aggregation is newest-first; reverse so the newest is the
        // rightmost (current) bar in the timeline.
        ForEach(Array(plays.reversed().enumerated()), id: \.offset) { idx, p in
          let isCurrent = idx == plays.count - 1
          Rectangle()
            .fill(Dial.Palette.amber.opacity(isCurrent ? 1.0 : 0.22 + Double(idx) * 0.06))
            .frame(width: max(CGFloat(p.msPlayed) / 5000.0, 30),
                   height: isCurrent ? 22 : CGFloat(10 + idx * 2))
        }
      }
      .frame(height: 22, alignment: .bottom)
    }
    .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14))
  }
}
