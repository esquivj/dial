import XCTest
@testable import Dial

final class PetTrickUnlocksDAOTests: XCTestCase {
  func test_unlockPersistsTrickOnce() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = PetTrickUnlocksDAO(dbq: dbq, now: { 1_700_000_000 })

    XCTAssertTrue(try dao.unlock(.sparkStep, sourceBadge: .newArtist))
    XCTAssertFalse(try dao.unlock(.sparkStep, sourceBadge: .newArtist))

    let unlocks = try dao.all()
    XCTAssertEqual(unlocks.map(\.trick), [.sparkStep])
    XCTAssertEqual(unlocks.first?.sourceBadge, BadgeMemoryKind.newArtist.rawValue)
  }
}
