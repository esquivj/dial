// Dial/Views/PixelSprite/PixelSprite.swift
import SwiftUI

/// Renders a 14×14 pixel grid. `pixelSize` controls per-pixel side length:
/// 1 for the menubar strip (~14×14 px), 2 for the dropdown's status rail.
struct PixelSprite: View {
  let grid: PetSprites.Grid
  let pixelSize: CGFloat
  let amber: Color
  let ivory: Color
  let shadow: Color

  init(grid: PetSprites.Grid,
       pixelSize: CGFloat = 1,
       amber: Color = Dial.Palette.amber,
       ivory: Color = Dial.Palette.ivory,
       shadow: Color = Dial.Palette.muted) {
    self.grid = grid
    self.pixelSize = pixelSize
    self.amber = amber
    self.ivory = ivory
    self.shadow = shadow
  }

  var body: some View {
    Canvas { ctx, size in
      let w = size.width / CGFloat(grid[0].count)
      let h = size.height / CGFloat(grid.count)
      for (y, row) in grid.enumerated() {
        for (x, v) in row.enumerated() where v != 0 {
          let rect = CGRect(x: CGFloat(x) * w, y: CGFloat(y) * h, width: w, height: h)
          let color: Color = v == 1 ? amber : v == 2 ? ivory : shadow
          ctx.fill(Path(rect), with: .color(color))
        }
      }
    }
    .frame(width: CGFloat(grid[0].count) * pixelSize,
           height: CGFloat(grid.count) * pixelSize)
  }
}
