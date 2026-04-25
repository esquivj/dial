import SwiftUI

struct TrackHero: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AsyncImage(url: vm.track?.artUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        // Soft cream-toned placeholder so an empty track doesn't punch a
        // dark hole in the light layout.
        LinearGradient(
          colors: [Dial.Palette.subtle, Dial.Palette.hairline],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .stroke(Dial.Palette.hairline, lineWidth: 1)
      )

      VStack(alignment: .leading, spacing: 2) {
        Text(vm.track?.name ?? "Nothing playing")
          .font(Dial.Typography.sansTitle)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        if let artist = vm.track?.artistName {
          Text(artist)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.muted)
            .lineLimit(1)
        }
        if let album = vm.track?.albumName {
          Text(album)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.muted.opacity(0.75))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
  }
}
