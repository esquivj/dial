import SwiftUI

struct MenubarStripView: View {
  @Bindable var vm: MenubarStripViewModel
  @Bindable var pet: PetViewModel

  var body: some View {
    HStack(spacing: 6) {
      sprite
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

  @ViewBuilder
  private var sprite: some View {
    // Bigger than before (was h:20 in a 22×22 box). Pushes to the menubar
    // height ceiling and gives the bulldog more horizontal room — the
    // 1:1.93 portrait aspect means this lands at ~14×26 on screen.
    BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 26)
      .frame(width: 28, height: 26)
  }
}
