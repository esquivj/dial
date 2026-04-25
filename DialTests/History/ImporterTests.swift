// DialTests/History/ImporterTests.swift
import XCTest
import GRDB
@testable import Dial

final class ImporterTests: XCTestCase {
  func test_import_is_idempotent() throws {
    let dbq = try InMemoryDatabase.make()
    let importer = Importer(dbq: dbq, engine: PetEngine(dbq: dbq))
    let rows: [EndsongRow] = [
      .init(playedAt: 1_700_000_000, msPlayed: 180_000, trackUri: "T",
            trackName: "n", artistName: "a", albumName: "al"),
      .init(playedAt: 1_700_000_000, msPlayed: 180_000, trackUri: "T",
            trackName: "n", artistName: "a", albumName: "al"),
    ]
    let n = try importer.importBatch(rows, sourcePath: "dummy")
    XCTAssertEqual(n, 1)   // duplicates rejected by unique constraint
    let again = try importer.importBatch(rows, sourcePath: "dummy")
    XCTAssertEqual(again, 0)
  }
}
