import SwiftUI

struct ArtistContext: View {
  let artist: String
  let rank7d: Int?
  let lifetime: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("ARTIST")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.textMuted)
        Spacer()
        Text(rank7d.map { "#\($0) · 7D" } ?? "")
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.accent)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(artist)
          .font(Dial.Typography.sansTitle)
          .foregroundStyle(Dial.Palette.textPrimary)
        Spacer()
        Text(lifetime > 0 ? "\(lifetime) lifetime" : "—")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(Dial.Palette.textMuted)
      }
    }
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .overlay(alignment: .top) {
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
    }
  }
}
