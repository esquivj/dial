import SwiftUI

struct StatusRail: View {
  @Bindable var vm: MenubarStripViewModel
  @Bindable var pet: PetViewModel

  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Dial.Palette.amber.opacity(0.85)).frame(height: 1)
      HStack(spacing: 8) {
        Group {
          if case .beatSync(let bpm) = pet.behavior {
            BeatSyncSprite(grid: PetSprites.grid(for: pet.stage, behavior: pet.behavior),
                           pixelSize: 2, bpm: bpm)
          } else {
            PixelSprite(grid: PetSprites.grid(for: pet.stage, behavior: pet.behavior),
                        pixelSize: 2)
          }
        }
        .frame(width: 28, height: 28)
        Circle()
          .fill(Dial.Palette.amber)
          .frame(width: 6, height: 6)
          .shadow(color: Dial.Palette.amber, radius: 3)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.amber)
        Spacer()
        Text(timing)
          .font(Dial.Typography.monoLabel)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.muted)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
    }
    .background(LinearGradient(colors: [Dial.Palette.surface, Dial.Palette.ground],
                               startPoint: .top, endPoint: .bottom))
  }

  private var timing: String {
    let s = vm.progressMs / 1000
    return String(format: "%02d:%02d", s / 60, s % 60)
  }
}
