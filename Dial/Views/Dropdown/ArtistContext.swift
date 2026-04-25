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
          .foregroundStyle(Dial.Palette.muted)
        Spacer()
        Text(rank7d.map { "#\($0) · 7D" } ?? "")
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.amber)
      }
      HStack(alignment: .firstTextBaseline) {
        Text(artist)
          .font(Dial.Typography.sansTitle)
          .foregroundStyle(Dial.Palette.ivory)
        Spacer()
        Text("\(lifetime) lifetime")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(Color(white: 0.54))
      }
    }
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
  }
}
