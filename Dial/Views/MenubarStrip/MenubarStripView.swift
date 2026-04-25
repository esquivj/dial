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
    let grid = PetSprites.grid(for: pet.stage, behavior: pet.behavior)
    Group {
      if case .beatSync(let bpm) = pet.behavior {
        BeatSyncSprite(grid: grid, pixelSize: 1.5, bpm: bpm)
      } else {
        PixelSprite(grid: grid, pixelSize: 1.5)
      }
    }
    .frame(width: 21, height: 21)
  }
}
