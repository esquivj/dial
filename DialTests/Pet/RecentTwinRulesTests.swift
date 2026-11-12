import XCTest
import GRDB
@testable import Dial

/// PLA-96. Recently-played rows that are the same listen as a live play, or
/// a restart of a recent row, must not count. Each case runs twice: through
/// `PetEngine.recordPlay` (rows that arrive from now on) and as raw rows read
/// through `counted_plays` (rows already in an archive, migration v20).
/// The two must agree.
final class RecentTwinRulesTests: XCTestCase {
  private let start: Int64 = 1_700_000_000
  private let recent = RecentPlaysReconciler.source

  /// One scenario: earlier rows, then the recent row under test.
  private struct Case {
    let name: String
    let earlier: [Play]
    let candidate: Play
    let counts: Bool
  }

  private func cases() -> [Case] {
    let d: Int64 = 200   // every track below is 200 s long
    return [
      Case(name: "live twin, recent stamped 30 s late",
           earlier: [live("A", at: start)],
           candidate: recentRow("A", at: start + d + 30),
           counts: false),
      Case(name: "live twin, recent stamped 60 s late (the limit)",
           earlier: [live("A", at: start)],
           candidate: recentRow("A", at: start + d + 60),
           counts: false),
      Case(name: "recent 61 s past the live play: its own listen (a pause or a later play)",
           earlier: [live("A", at: start)],
           candidate: recentRow("A", at: start + d + 61),
           counts: true),
      Case(name: "same song under another track id (relinked)",
           earlier: [live("A", at: start)],
           candidate: recentRow("A2", at: start + d + 3),
           counts: false),
      Case(name: "same title, different artist: not a twin",
           earlier: [live("A", at: start)],
           candidate: recentRow("B", at: start + d + 3),
           counts: true),
      Case(name: "restart: a second recent row 40 s after the first",
           earlier: [recentRow("A", at: start + d)],
           candidate: recentRow("A", at: start + d + 40),
           counts: false),
      Case(name: "back-to-back full replay, both from recently-played",
           earlier: [recentRow("A", at: start + d)],
           candidate: recentRow("A", at: start + 2 * d),
           counts: true),
      Case(name: "back-to-back replay after a live play keeps counting",
           earlier: [live("A", at: start)],
           candidate: recentRow("A", at: start + 2 * d),
           counts: true),
    ]
  }

  private func live(_ uri: String, at: Int64) -> Play {
    Play(playedAt: at, trackUri: uri, msPlayed: 60_000, source: "live")
  }

  private func recentRow(_ uri: String, at: Int64) -> Play {
    Play(playedAt: at, trackUri: uri, msPlayed: 200_000, source: recent)
  }

  /// "A" and "A2" are the same song (relinked ids), "B" shares the title
  /// with a different artist.
  private func makeDatabase() throws -> DatabaseQueue {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    try tracks.upsert(.init(uri: "A", name: "Song", albumName: "Al", albumArtUrl: nil, durationMs: 200_000,
                            artistsJson: #"[{"name":"Artist","uri":"spotify:artist:1"}]"#))
    try tracks.upsert(.init(uri: "A2", name: " song ", albumName: "Al (Deluxe)", albumArtUrl: nil, durationMs: 200_000,
                            artistsJson: #"[{"name":"ARTIST","uri":"spotify:artist:1"}]"#))
    try tracks.upsert(.init(uri: "B", name: "Song", albumName: "Other", albumArtUrl: nil, durationMs: 200_000,
                            artistsJson: #"[{"name":"Someone Else","uri":"spotify:artist:2"}]"#))
    return dbq
  }

  func test_recordPlay_appliesTheRules() throws {
    for c in cases() {
      let dbq = try makeDatabase()
      let engine = PetEngine(dbq: dbq, clock: { self.start })
      for p in c.earlier { try engine.recordPlay(p) }

      let recorded = try engine.recordPlay(c.candidate)

      XCTAssertEqual(recorded, c.counts, c.name)
    }
  }

  func test_countedPlays_appliesTheSameRules() throws {
    for c in cases() {
      let dbq = try makeDatabase()
      let plays = PlaysDAO(dbq: dbq)
      for p in c.earlier { try plays.insert(p) }
      try plays.insert(c.candidate)

      let counted = try dbq.read { db in
        try Int.fetchOne(db, sql: """
          SELECT COUNT(*) FROM counted_plays
          WHERE played_at = ? AND track_uri = ? AND source = ?
          """, arguments: [c.candidate.playedAt, c.candidate.trackUri, c.candidate.source]) ?? 0
      }

      XCTAssertEqual(counted == 1, c.counts, c.name)
    }
  }

  func test_unknownDuration_usesTheTenMinuteWindowAndAMinuteOfSlack() throws {
    let dbq = try InMemoryDatabase.make()
    try TracksDAO(dbq: dbq).upsert(.init(uri: "U", name: "U", albumName: nil, albumArtUrl: nil, durationMs: nil,
                                         artistsJson: nil))
    let engine = PetEngine(dbq: dbq, clock: { self.start })
    try engine.recordPlay(live("U", at: start))

    XCTAssertFalse(try engine.recordPlay(recentRow("U", at: start + 600 + 60)))
    XCTAssertTrue(try engine.recordPlay(recentRow("U", at: start + 600 + 61 + 600)))
  }
}
