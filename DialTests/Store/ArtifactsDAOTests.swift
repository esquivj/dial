import XCTest
@testable import Dial

final class ArtifactsDAOTests: XCTestCase {
  func test_syncFromMemories_unlocksOneArtifactPerBadgeKind() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try BadgeEventsDAO.insertIgnoring(BadgeEvent(
        kind: .firstListen,
        category: .discovery,
        trackUri: "spotify:track:1",
        artistUri: "spotify:artist:1",
        albumName: "A",
        earnedAt: 1_700_000_000,
        payloadJson: nil,
        scopeKey: "first"), in: db)
      try BadgeEventsDAO.insertIgnoring(BadgeEvent(
        kind: .firstListen,
        category: .discovery,
        trackUri: "spotify:track:2",
        artistUri: "spotify:artist:2",
        albumName: "B",
        earnedAt: 1_700_000_050,
        payloadJson: nil,
        scopeKey: "first-again"), in: db)
      try BadgeEventsDAO.insertIgnoring(BadgeEvent(
        kind: .deepCut,
        category: .discovery,
        trackUri: "spotify:track:3",
        artistUri: "spotify:artist:3",
        albumName: "C",
        earnedAt: 1_700_000_100,
        payloadJson: nil,
        scopeKey: "deep"), in: db)
    }

    let artifacts = try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()
    XCTAssertEqual(Set(artifacts.map(\.kind)), [.firstListenSpark, .deepCutGem])
    XCTAssertEqual(artifacts.first(where: { $0.kind == .firstListenSpark })?.trackUri, "spotify:track:1")
  }

  func test_syncFromMemoriesAndTricks_unlocksTrickArtifact() throws {
    let dbq = try InMemoryDatabase.make()
    XCTAssertTrue(try PetTrickUnlocksDAO(dbq: dbq, now: { 1_700_000_000 }).unlock(.beatBounce))

    let artifacts = try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()
    XCTAssertEqual(artifacts.map(\.kind), [.beatBounceCharm])
    XCTAssertEqual(artifacts.first?.source, .trick)
  }
}
