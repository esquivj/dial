import SwiftUI

/// The view that sits inside the NSStatusItem button. Shows a compact
/// "now playing" strip — small album art thumbnail + track name when
/// playing, or just a music-note icon when paused / nothing playing.
///
/// Replaced an earlier version that put the bulldog pet here. The pet
/// is still in the dropdown's StatusRail (and now has its own dedicated
/// PetView screen reachable by tapping it), but the menubar is the wrong
/// place for it — at typical menubar sizes the sprite is unreadable, and
/// the more useful information at a glance is "what am I listening to."
struct MenubarStripView: View {
  @Bindable var vm: MenubarStripViewModel

  var body: some View {
    HStack(spacing: 6) {
      icon
      switch vm.state {
      case .playing:
        Text(vm.track?.name ?? "")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
          .frame(maxWidth: 180, alignment: .leading)
      case .paused:
        Text("Paused")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted)
      case .nothingPlaying:
        EmptyView()
      }
    }
    .padding(.horizontal, 6)
  }

  /// Icon shown to the left of any text. Album art when a track is
  /// playing (the cover signals "this is what you're hearing"), music
  /// note glyph otherwise so the menubar item still has presence and
  /// the user can find Dial when nothing is playing.
  @ViewBuilder
  private var icon: some View {
    if vm.state == .playing,
       let urlString = vm.track?.artUrl,
       let url = URL(string: urlString)
    {
      AsyncImage(url: url) { img in
        img.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.3)
      }
      .frame(width: 18, height: 18)
      .clipShape(RoundedRectangle(cornerRadius: 2))
    } else {
      Image(systemName: "music.note")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Dial.Palette.amber)
        .frame(width: 18, height: 18)
    }
  }
}
