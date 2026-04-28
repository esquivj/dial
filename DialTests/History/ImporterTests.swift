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

  func test_import_doesNotAdvanceLivePetStreak() throws {
    let dbq = try InMemoryDatabase.make()
    let importer = Importer(dbq: dbq, engine: PetEngine(dbq: dbq))
    let rows: [EndsongRow] = [
      .init(playedAt: 1_700_000_000, msPlayed: 180_000, trackUri: "T1",
            trackName: "n1", artistName: "a", albumName: "al"),
      .init(playedAt: 1_700_086_400, msPlayed: 180_000, trackUri: "T2",
            trackName: "n2", artistName: "a", albumName: "al"),
    ]

    XCTAssertEqual(try importer.importBatch(rows, sourcePath: "dummy"), 2)

    let state = try PetStateDAO(dbq: dbq).get()
    XCTAssertEqual(state.streakDays, 0)
    XCTAssertNil(state.streakAnchorDate)
    XCTAssertNil(state.lastPlayAt)
    XCTAssertEqual(state.xp, 6)
  }

  func test_importNeverReducesLiveXPAboveImportCap() throws {
    let dbq = try InMemoryDatabase.make()
    try PetStateDAO(dbq: dbq).update { state in
      state.xp = 30_000
      state.stage = .companion
    }
    let importer = Importer(dbq: dbq, engine: PetEngine(dbq: dbq))
    let rows: [EndsongRow] = [
      .init(playedAt: 1_700_000_000, msPlayed: 1_000_000 * 60_000, trackUri: "T",
            trackName: "n", artistName: "a", albumName: "al")
    ]

    XCTAssertEqual(try importer.importBatch(rows, sourcePath: "dummy"), 1)

    let state = try PetStateDAO(dbq: dbq).get()
    XCTAssertEqual(state.xp, 30_000)
  }
}
