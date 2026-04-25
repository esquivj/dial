import SwiftUI

struct TrackHero: View {
  @Bindable var vm: NowPlayingViewModel

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      AsyncImage(url: vm.track?.artUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        LinearGradient(
          colors: [Color(red: 0.22, green: 0.14, blue: 0.09),
                   Color(red: 0.96, green: 0.72, blue: 0.47)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 2) {
        Text(vm.track?.name ?? "Nothing playing")
          .font(Dial.Typography.sansTitle)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        if let artist = vm.track?.artistName {
          Text(artist)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Color(red: 0.54, green: 0.55, blue: 0.57))
            .lineLimit(1)
        }
        if let album = vm.track?.albumName {
          Text(album)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Color(red: 0.42, green: 0.43, blue: 0.45))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
  }
}
