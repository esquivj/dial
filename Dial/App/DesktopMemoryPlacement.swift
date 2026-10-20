// Dial/App/DesktopMemoryPlacement.swift
import CoreGraphics

/// The four places the desktop memory object can sit on a display.
enum DesktopMemoryCorner: String, CaseIterable, Codable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

/// Where the desktop memory window goes (docs/design/desktop-memory.md):
/// a corner of a display's visible area, so it stays clear of the menu bar
/// and the Dock. Pure, so snapping is testable without real screens.
/// Rects are in AppKit screen coordinates (origin bottom-left, y up).
struct DesktopMemoryPlacement {
  /// Gap between the chassis and the edges of the visible area.
  static let inset: CGFloat = 20

  /// The whole window, shadow margin included.
  var windowSize: CGSize = DesktopMemoryMetrics.windowSize
  /// Transparent room around the chassis inside the window.
  var shadowMargin: CGFloat = DesktopMemoryMetrics.shadowMargin

  /// The window frame that puts the chassis `inset` points from `corner`.
  func frame(corner: DesktopMemoryCorner, in visible: CGRect) -> CGRect {
    let offset = Self.inset - shadowMargin
    let x: CGFloat
    switch corner {
    case .topLeft, .bottomLeft: x = visible.minX + offset
    case .topRight, .bottomRight: x = visible.maxX - windowSize.width - offset
    }
    let y: CGFloat
    switch corner {
    case .bottomLeft, .bottomRight: y = visible.minY + offset
    case .topLeft, .topRight: y = visible.maxY - windowSize.height - offset
    }
    return CGRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
  }

  /// The corner of `visible` nearest to where the window was dropped.
  static func nearestCorner(to frame: CGRect, in visible: CGRect) -> DesktopMemoryCorner {
    let left = frame.midX < visible.midX
    let bottom = frame.midY < visible.midY
    switch (left, bottom) {
    case (true, true): return .bottomLeft
    case (false, true): return .bottomRight
    case (true, false): return .topLeft
    case (false, false): return .topRight
    }
  }

  /// The display a dropped window belongs to: the one under its center,
  /// else the one it overlaps most, else the nearest. `nil` only when
  /// there are no displays.
  static func displayIndex(for frame: CGRect, among visibles: [CGRect]) -> Int? {
    guard !visibles.isEmpty else { return nil }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    if let index = visibles.firstIndex(where: { $0.contains(center) }) {
      return index
    }
    let overlaps = visibles.map { $0.intersection(frame) }.map { $0.isNull ? 0 : $0.width * $0.height }
    if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
      return best
    }
    return visibles.indices.min { distance(from: center, to: visibles[$0]) < distance(from: center, to: visibles[$1]) }
  }

  private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return (dx * dx + dy * dy).squareRoot()
  }
}
