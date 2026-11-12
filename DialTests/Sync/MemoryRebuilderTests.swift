import XCTest
import GRDB
@testable import Dial

/// `Dial --rebuild-memories`: re-judges memories under the current rules,
/// keeps plays and the pet, and backs up before swapping (PLA-95).
final class MemoryRebuilderTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("dial-rebuild-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  /// An archive whose only Rediscovered badge was earned under the old
  /// 90-day rule: one earlier play, 100 days before.
  private func makeArchive() throws -> (url: URL, start: Int64) {
    let url = directory.appendingPathComponent("dial.sqlite")
    let dbq = try DatabaseQueue(path: url.path)
    try Migrations.register().migrate(dbq)
    let start = try XCTUnwrap(MemoryRebuilder.startOfDay("2025-06-02"))
    let noon = start + 12 * 3_600
    let engine = PetEngine(dbq: dbq, clock: { noon })
    try TracksDAO(dbq: dbq).upsert(.init(
      uri: "T", name: "Old Song", albumName: "Record", albumArtUrl: nil, durationMs: 200_000,
      artistsJson: #"[{"name":"Old Artist","uri":"art:old"}]"#))
    try engine.recordPlay(.init(playedAt: noon - 100 * 86_400, trackUri: "T", msPlayed: 60_000, source: "import"))
    try engine.recordPlay(.init(playedAt: noon, trackUri: "T", msPlayed: 60_000, source: "live"))
    try dbq.write { db in
      try BadgeEventsDAO.insertIgnoring(.init(
        id: nil, kind: .rediscovered, category: BadgeMemoryKind.rediscovered.category,
        trackUri: "T", artistUri: "art:old", albumName: "Record", earnedAt: noon,
        payloadJson: nil, scopeKey: "rediscovered:T:\(noon)"), in: db)
    }
    try dbq.close()
    return (url, start)
  }

  private func counts(_ url: URL) throws -> (plays: Int, rediscovered: Int, xp: Int64) {
    let dbq = try DatabaseQueue(path: url.path)
    defer { try? dbq.close() }
    return try dbq.read { db in
      (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") ?? 0,
       try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM badge_events WHERE kind = 'rediscovered'") ?? 0,
       try Int64.fetchOne(db, sql: "SELECT xp FROM pet_state WHERE id = 1") ?? 0)
    }
  }

  func test_rebuild_dropsMemoriesTheCurrentRulesWouldNotAward() throws {
    let (url, start) = try makeArchive()
    let before = try counts(url)
    XCTAssertEqual(before.rediscovered, 1)

    let report = try MemoryRebuilder(archiveURL: url, from: start).run()

    let after = try counts(url)
    XCTAssertEqual(after.rediscovered, 0)
    XCTAssertEqual(after.plays, before.plays)
    XCTAssertEqual(after.xp, before.xp)
    XCTAssertEqual(report.playsReplayed, 1)
    XCTAssertEqual(report.kindsBefore["rediscovered"], 1)
    XCTAssertNil(report.kindsAfter["rediscovered"])
    let backup = try XCTUnwrap(report.backupURL)
    XCTAssertEqual(try counts(backup).rediscovered, 1, "the backup holds the archive as it was")
  }

  func test_dryRun_reportsButChangesNothing() throws {
    let (url, start) = try makeArchive()

    var rebuilder = MemoryRebuilder(archiveURL: url, from: start)
    rebuilder.dryRun = true
    let report = try rebuilder.run()

    XCTAssertNil(report.kindsAfter["rediscovered"])
    XCTAssertNil(report.backupURL)
    XCTAssertEqual(try counts(url).rediscovered, 1)
  }

  func test_startOfDay_parsesLocalDates() {
    XCTAssertNotNil(MemoryRebuilder.startOfDay("2026-04-25"))
    XCTAssertNil(MemoryRebuilder.startOfDay("April 25"))
  }
}
