// DialTests/Pet/PetEngineTests.swift
import XCTest
import GRDB
@testable import Dial

final class PetEngineTests: XCTestCase {
  func test_firstLivePlay_awardsBaseAndNewArtist() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try TracksDAO(dbq: dbq).upsert(.init(uri: "T", name: "t", albumName: "Al", albumArtUrl: nil, durationMs: 200_000,
                                         artistsJson: #"[{"name":"X","uri":"art:X"}]"#))
    try engine.recordPlay(.init(playedAt: 1_700_000_000, trackUri: "T", msPlayed: 60_000, source: "live"))
    let s = try PetStateDAO(dbq: dbq).get()
    XCTAssertEqual(s.xp, 51)        // 1 minute (1 XP) + newArtist (50)
    XCTAssertEqual(s.stage, .egg)
    XCTAssertEqual(s.streakDays, 1)
  }

  func test_crossingThreshold_transitionsStage() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try TracksDAO(dbq: dbq).upsert(.init(uri: "T", name: "t", albumName: nil, albumArtUrl: nil, durationMs: nil, artistsJson: nil))
    // 500 minutes = 500 XP exactly → hatching
    try engine.recordPlay(.init(playedAt: 1_700_000_000, trackUri: "T", msPlayed: 500 * 60_000, source: "live"))
    XCTAssertEqual(try PetStateDAO(dbq: dbq).get().stage, .hatching)
  }

  func test_importedPlays_cappedAtCompanion() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try TracksDAO(dbq: dbq).upsert(.init(uri: "T", name: "t", albumName: nil, albumArtUrl: nil, durationMs: nil, artistsJson: nil))
    // 1M minutes of imported play → would far exceed elder, but capped at companion (25_000)
    try engine.recordPlay(.init(playedAt: 1_700_000_000, trackUri: "T", msPlayed: 1_000_000 * 60_000, source: "import"))
    let s = try PetStateDAO(dbq: dbq).get()
    XCTAssertEqual(s.stage, .companion)
    XCTAssertLessThanOrEqual(s.xp, 25_000)
  }
}
