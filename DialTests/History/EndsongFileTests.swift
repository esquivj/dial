// DialTests/History/EndsongFileTests.swift
import XCTest
@testable import Dial

final class EndsongFileTests: XCTestCase {
  func test_parse_skipsInvalidRows_returnsValid() throws {
    let url = Bundle(for: Self.self).url(forResource: "sample_endsong", withExtension: "json")!
    let rows = try EndsongFile.parse(at: url)
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(rows[0].trackUri, "spotify:track:A")
  }
}
