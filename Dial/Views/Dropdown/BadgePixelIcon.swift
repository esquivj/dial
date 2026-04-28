import SwiftUI
import AppKit

/// Generated one-color pixel badges for chips. PNGs live in
/// `Resources/Badges/`, ship as black-on-transparent, and are marked as
/// templates so the chip can tint them with the badge category color.
struct BadgePixelIcon: View {
  let kind: BadgeMemoryKind
  let color: Color
  var size: CGFloat = 14

  var body: some View {
    if let nsImage = Self.load(named: kind.rawValue) {
      Image(nsImage: nsImage)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      fallbackIcon
    }
  }

  private var fallbackIcon: some View {
    Canvas { ctx, canvasSize in
      let rows = kind.pixelRows
      let rowCount = rows.count
      let colCount = rows.first?.count ?? 0
      guard rowCount > 0, colCount > 0 else { return }

      let cell = floor(min(canvasSize.width / CGFloat(colCount), canvasSize.height / CGFloat(rowCount)))
      let gridW = cell * CGFloat(colCount)
      let gridH = cell * CGFloat(rowCount)
      let x0 = floor((canvasSize.width - gridW) / 2)
      let y0 = floor((canvasSize.height - gridH) / 2)

      for (y, row) in rows.enumerated() {
        for (x, pixel) in row.enumerated() where pixel == "#" {
          let rect = CGRect(
            x: x0 + CGFloat(x) * cell,
            y: y0 + CGFloat(y) * cell,
            width: max(1, cell),
            height: max(1, cell))
          ctx.fill(Path(rect), with: .color(color))
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private static func load(named name: String) -> NSImage? {
    if let cached = cache[name] { return cached }
    let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Badges")
      ?? Bundle.main.url(forResource: name, withExtension: "png")
    guard let url, let img = NSImage(contentsOf: url) else { return nil }
    img.isTemplate = true
    cache[name] = img
    return img
  }

  private static var cache: [String: NSImage] = [:]
}

private extension BadgeMemoryKind {
  var pixelRows: [String] {
    switch self {
    case .firstListen:
      return [
        "....#....",
        "...###...",
        "..#####..",
        "...###...",
        "..#.#.#..",
        ".#..#..#.",
        "....#....",
        ".........",
        ".........",
      ]
    case .newArtist:
      return [
        "...###...",
        "..#####..",
        "..#####..",
        "...###...",
        "..#####..",
        ".#######.",
        "##.#.###.",
        "...#.....",
        "..###....",
      ]
    case .rediscovered:
      return [
        "...####..",
        "..#....#.",
        ".#......#",
        ".#..##..#",
        ".#...#..#",
        "..#....#.",
        "...####..",
        "....#....",
        "...##....",
      ]
    case .deepCut:
      return [
        "....#....",
        "...###...",
        "..#####..",
        ".#######.",
        "..#####..",
        "...###...",
        "....#....",
        "...#.#...",
        ".........",
      ]
    case .onStreak:
      return [
        "....#....",
        "...##....",
        "..####.#.",
        "..######.",
        ".#######.",
        ".######..",
        "..####...",
        "...##....",
        ".........",
      ]
    case .repeatTrack:
      return [
        "..###.##.",
        ".#...#..#",
        "#...#...#",
        "#...#...#",
        ".#..#..#.",
        "..##.##..",
        "....#....",
        "...##....",
        ".........",
      ]
    case .albumMode:
      return [
        ".######..",
        ".#....#..",
        ".######..",
        "..######.",
        "..#....#.",
        "..######.",
        "...######",
        "...#....#",
        "...######",
      ]
    case .play10:
      return [
        ".##..###.",
        "###.#...#",
        ".##.#...#",
        ".##.#...#",
        ".##.#...#",
        ".##.#...#",
        "####.###.",
        ".........",
        ".........",
      ]
    case .play50:
      return [
        "####.###.",
        "#....#..#",
        "#....#..#",
        "###..#..#",
        "...#.#..#",
        "#..#.#..#",
        ".##...##.",
        ".........",
        ".........",
      ]
    case .play100:
      return [
        ".#..#..#.",
        ".########",
        "..######.",
        "..######.",
        "...####..",
        "...####..",
        "..######.",
        ".########",
        ".........",
      ]
    case .anniversary:
      return [
        ".#.#.#.#.",
        ".#######.",
        ".#.....#.",
        ".#.###.#.",
        ".#.#.#.#.",
        ".#.###.#.",
        ".#.....#.",
        ".#######.",
        ".........",
      ]
    }
  }
}
