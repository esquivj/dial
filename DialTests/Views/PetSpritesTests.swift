// DialTests/Views/PetSpritesTests.swift
import XCTest
@testable import Dial

final class PetSpritesTests: XCTestCase {
  func test_everyStage_hasIdleSprite() {
    for stage in PetStage.allCases {
      let g = PetSprites.grid(for: stage, behavior: .idle)
      XCTAssertEqual(g.count, 14, "stage \(stage) idle should be 14 rows tall")
      XCTAssertEqual(g[0].count, 14, "stage \(stage) idle should be 14 cols wide")
      XCTAssertTrue(g.flatMap { $0 }.contains(where: { $0 != 0 }), "sprite for \(stage) is blank")
    }
  }
}
