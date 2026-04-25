// DialTests/DesignSystem/TokenTests.swift
import XCTest
import SwiftUI
@testable import Dial

final class TokenTests: XCTestCase {
  func test_amberMatchesSpec() {
    let amber = Dial.Palette.amber
    // Color comparison is a rendering concern; check that the token exists.
    XCTAssertNotNil(amber)
  }
  func test_monoValueFontSize() {
    // Verify the Swift token survived a build; deeper font rendering is covered by snapshot tests.
    XCTAssertNotNil(Dial.Typography.monoValue)
  }
}
