import XCTest
@testable import Dial

final class DesktopMemoryPlacementTests: XCTestCase {
  /// A 2560×1440 main display with a 31 pt menu bar and a 66 pt Dock.
  private let main = CGRect(x: 0, y: 66, width: 2560, height: 1343)
  /// A second display to its left, with no menu bar or Dock.
  private let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
  /// A 100×140 window with a 10 pt shadow margin: the window sits 10 pt in,
  /// so the chassis sits the standard 20 pt in.
  private let placement = DesktopMemoryPlacement(windowSize: CGSize(width: 100, height: 140), shadowMargin: 10)

  func test_eachCornerSitsInsideTheVisibleArea() {
    XCTAssertEqual(
      placement.frame(corner: .bottomRight, in: main),
      CGRect(x: 2560 - 100 - 10, y: 66 + 10, width: 100, height: 140))
    XCTAssertEqual(
      placement.frame(corner: .topLeft, in: main),
      CGRect(x: 10, y: 66 + 1343 - 140 - 10, width: 100, height: 140))
    XCTAssertEqual(
      placement.frame(corner: .bottomLeft, in: left),
      CGRect(x: -2560 + 10, y: 10, width: 100, height: 140))
    XCTAssertEqual(
      placement.frame(corner: .topRight, in: left),
      CGRect(x: -100 - 10, y: 1440 - 140 - 10, width: 100, height: 140))
  }

  func test_theRealWindowKeepsTheChassisTwentyPointsFromTheEdges() {
    let frame = DesktopMemoryPlacement().frame(corner: .bottomRight, in: main)
    let chassis = frame.insetBy(dx: DesktopMemoryMetrics.shadowMargin, dy: DesktopMemoryMetrics.shadowMargin)

    XCTAssertEqual(main.maxX - chassis.maxX, 20)
    XCTAssertEqual(chassis.minY - main.minY, 20)
  }

  func test_aDropSnapsToTheNearestCorner() {
    func drop(at point: CGPoint) -> DesktopMemoryCorner {
      let frame = CGRect(x: point.x - 50, y: point.y - 70, width: 100, height: 140)
      return DesktopMemoryPlacement.nearestCorner(to: frame, in: main)
    }

    XCTAssertEqual(drop(at: CGPoint(x: 300, y: 1200)), .topLeft)
    XCTAssertEqual(drop(at: CGPoint(x: 2300, y: 1200)), .topRight)
    XCTAssertEqual(drop(at: CGPoint(x: 300, y: 200)), .bottomLeft)
    XCTAssertEqual(drop(at: CGPoint(x: 2300, y: 200)), .bottomRight)
  }

  func test_aDropBelongsToTheDisplayUnderItsCenter() {
    let frame = CGRect(x: -400, y: 500, width: 100, height: 140)

    XCTAssertEqual(DesktopMemoryPlacement.displayIndex(for: frame, among: [main, left]), 1)
  }

  func test_aDropOffEveryDisplayPicksTheMostOverlapThenTheNearest() {
    // Centered in the main display's menu bar, still mostly over it.
    let overlapping = CGRect(x: 1000, y: 1380, width: 100, height: 140)
    XCTAssertEqual(DesktopMemoryPlacement.displayIndex(for: overlapping, among: [main, left]), 0)

    // Below both displays, nearer the left one.
    let below = CGRect(x: -1000, y: -600, width: 100, height: 140)
    XCTAssertEqual(DesktopMemoryPlacement.displayIndex(for: below, among: [main, left]), 1)
  }

  func test_noDisplaysMeansNoIndex() {
    XCTAssertNil(DesktopMemoryPlacement.displayIndex(for: .zero, among: []))
  }
}
