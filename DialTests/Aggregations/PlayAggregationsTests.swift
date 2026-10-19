// DialTests/Aggregations/PlayAggregationsTests.swift
import XCTest
import GRDB
import Foundation
@testable import Dial

final class PlayAggregationsTests: XCTestCase {
  var dbq: DatabaseQueue!
  var agg: PlayAggregations!
  override func setUpWithError() throws {
    dbq = try InMemoryDatabase.make()
    agg = PlayAggregations(dbq: dbq, now: { 1_700_000_000 })  // fixed clock
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    // Seed track metadata so artistRank7d (Task 13) has rows to join with
    try tracks.upsert(.init(uri: "A", name: "A", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: #"[{"name":"Caroline","uri":"art:1"}]"#))
    try tracks.upsert(.init(uri: "B", name: "B", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: #"[{"name":"Mac","uri":"art:2"}]"#))
    try tracks.upsert(.init(uri: "C", name: "C", albumName: nil, albumArtUrl: nil, durationMs: nil, artistsJson: nil))
    let now: Int64 = 1_700_000_000
    // 24 plays of C: 2 in the 7d window (rank 3, qualifies onStreak) + 22 in days 8-29
    // 7d plays: now-2d, now-3d (both within 7d and outside 60min window)
    for i in 2..<4  { try plays.insert(.init(playedAt: now - Int64(i) * 86_400, trackUri: "C", msPlayed: 200_000, source: "live")) }
    // 22 plays in days 8-29 (all within 30d, outside 7d)
    for i in 8..<30 { try plays.insert(.init(playedAt: now - Int64(i) * 86_400, trackUri: "C", msPlayed: 200_000, source: "live")) }
    // 5 plays of A in last 7d, starting 2h ago so none fall in the 60-min window
    for i in 0..<5  { try plays.insert(.init(playedAt: now - 2 * 3600 - Int64(i) * 3600, trackUri: "A", msPlayed: 200_000, source: "live")) }
    // 3 plays of B in last 7d, starting 2h ago
    for i in 0..<3  { try plays.insert(.init(playedAt: now - 2 * 3600 - Int64(i) * 3600, trackUri: "B", msPlayed: 200_000, source: "live")) }
  }

  // MARK: Task 11
  func test_plays30d_countsOnlyWithinWindow() throws {
    XCTAssertEqual(try agg.plays30d(trackUri: "C"), 24)
    XCTAssertEqual(try agg.plays30d(trackUri: "A"), 5)
  }

  func test_playsYTD_countsSinceStartOfCurrentYear() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 300 * 86_400, trackUri: "B", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 370 * 86_400, trackUri: "B", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.playsYTD(trackUri: "B"), 4)
  }

  func test_importedSkipsDoNotCountButLongEnoughImportsDo() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try tracks.upsert(.init(uri: "SHORT", name: "Short", albumName: nil, albumArtUrl: nil, durationMs: 40_000,
                            artistsJson: nil))
    try tracks.upsert(.init(uri: "D", name: "D", albumName: nil, albumArtUrl: nil, durationMs: nil,
                            artistsJson: nil))
    // Imported 5s skip: kept in plays, not counted.
    try plays.insert(.init(playedAt: now - 3600, trackUri: "D", msPlayed: 5_000, source: "import"))
    // Imported 30s listen: counted.
    try plays.insert(.init(playedAt: now - 7200, trackUri: "D", msPlayed: 30_000, source: "import"))
    // Imported 20s of a 40s track (>=50% of known duration): counted.
    try plays.insert(.init(playedAt: now - 3600, trackUri: "SHORT", msPlayed: 20_000, source: "import"))
    // Imported 19s of a 40s track: a skip.
    try plays.insert(.init(playedAt: now - 7200, trackUri: "SHORT", msPlayed: 19_000, source: "import"))
    // Live plays already passed DedupRule before insert, so they always count.
    try plays.insert(.init(playedAt: now - 10_800, trackUri: "SHORT", msPlayed: 20_000, source: "live"))

    XCTAssertEqual(try agg.plays30d(trackUri: "D"), 1)
    XCTAssertEqual(try agg.plays30d(trackUri: "SHORT"), 2)
    let stored = try dbq.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays WHERE track_uri IN ('D', 'SHORT')") }
    XCTAssertEqual(stored, 5, "Skips stay in the archive")
  }

  func test_recentTwinsOfLivePlaysAreHiddenButRealRepeatsCount() throws {
    // Rows written straight to `plays`, as the old strict dedup window let
    // them through. Live rows are start-stamped, recent rows end-stamped.
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let start: Int64 = 1_700_000_000
    for uri in ["ZERO", "ONE", "REPEAT", "ALONE"] {
      try tracks.upsert(.init(uri: uri, name: uri, albumName: nil, albumArtUrl: nil, durationMs: 200_000,
                              artistsJson: nil))
    }
    // 0 s past the old boundary: twin.
    try plays.insert(.init(playedAt: start, trackUri: "ZERO", msPlayed: 60_000, source: "live"))
    try plays.insert(.init(playedAt: start + 200, trackUri: "ZERO", msPlayed: 200_000, source: "recent"))
    // 1 s past the old boundary: twin.
    try plays.insert(.init(playedAt: start - 1, trackUri: "ONE", msPlayed: 60_000, source: "live"))
    try plays.insert(.init(playedAt: start + 200, trackUri: "ONE", msPlayed: 200_000, source: "recent"))
    // Back-to-back repeat seen live once: the first recent row is a twin,
    // the second is a real play Dial missed live.
    try plays.insert(.init(playedAt: start, trackUri: "REPEAT", msPlayed: 60_000, source: "live"))
    try plays.insert(.init(playedAt: start + 200, trackUri: "REPEAT", msPlayed: 200_000, source: "recent"))
    try plays.insert(.init(playedAt: start + 400, trackUri: "REPEAT", msPlayed: 200_000, source: "recent"))
    // A recent row with no live twin.
    try plays.insert(.init(playedAt: start + 200, trackUri: "ALONE", msPlayed: 200_000, source: "recent"))

    let counts = try dbq.read { db -> [String: Int] in
      let rows = try Row.fetchAll(db, sql: """
        SELECT track_uri, COUNT(*) AS n FROM counted_plays
        WHERE track_uri IN ('ZERO', 'ONE', 'REPEAT', 'ALONE')
        GROUP BY track_uri
        """)
      return Dictionary(uniqueKeysWithValues: rows.map { ($0["track_uri"] as String, $0["n"] as Int) })
    }
    XCTAssertEqual(counts, ["ZERO": 1, "ONE": 1, "REPEAT": 2, "ALONE": 1])
    let stored = try dbq.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays WHERE track_uri IN ('ZERO', 'ONE', 'REPEAT', 'ALONE')")
    }
    XCTAssertEqual(stored, 8, "Twins stay in the archive")
  }

  func test_albumPlaysYTD_countsSameAlbumAndArtistContext() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000

    try tracks.upsert(.init(
      uri: "spotify:track:iceman-a",
      name: "Make Them Know",
      albumName: "ICEMAN",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Drake","uri":"spotify:artist:drake"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:iceman-b",
      name: "Shabang",
      albumName: "ICEMAN",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Drake","uri":"artist:Drake"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:other-artist",
      name: "Other ICEMAN",
      albumName: "ICEMAN",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Not Drake","uri":"artist:not-drake"}]"#))

    try plays.insert(.init(playedAt: now - 60, trackUri: "spotify:track:iceman-a", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 120, trackUri: "spotify:track:iceman-b", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 3_600, trackUri: "spotify:track:iceman-b", msPlayed: 200_000, source: "recent"))
    try plays.insert(.init(playedAt: now - 370 * 86_400, trackUri: "spotify:track:iceman-b", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 240, trackUri: "spotify:track:other-artist", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.playsYTD(trackUri: "spotify:track:iceman-a"), 1)
    XCTAssertEqual(try agg.albumPlaysYTD(trackUri: "spotify:track:iceman-a"), 3)
  }

  func test_rank7d_ranksByCountDesc() throws {
    XCTAssertEqual(try agg.rank7d(trackUri: "A"), 1)
    XCTAssertEqual(try agg.rank7d(trackUri: "B"), 2)
  }

  func test_lastPlayedAt_returnsMostRecentPriorPlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 10 * 86_400, trackUri: "LAST", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 2 * 86_400, trackUri: "LAST", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.lastPlayedAt(trackUri: "LAST"), now - 2 * 86_400)
  }

  func test_lastPlayedAt_excludesCurrentCountedPlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 90 * 86_400, trackUri: "CURRENT", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now, trackUri: "CURRENT", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.lastPlayedAt(trackUri: "CURRENT", before: now), now - 90 * 86_400)
  }

  // MARK: Task 12
  func test_firstListen_onlyTrueIfNoImportAndOneLivePlay() throws {
    let plays = PlaysDAO(dbq: dbq)
    try plays.insert(.init(playedAt: 1_700_000_000, trackUri: "NEW", msPlayed: 200_000, source: "live"))
    XCTAssertTrue(try agg.firstListen(trackUri: "NEW"))
    try plays.insert(.init(playedAt: 1_700_000_001, trackUri: "NEW", msPlayed: 200_000, source: "live"))
    XCTAssertFalse(try agg.firstListen(trackUri: "NEW"))
  }

  func test_firstListen_usesTitleArtistFallbackForImportedAlternateUri() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000

    try tracks.upsert(.init(
      uri: "spotify:track:imported-version",
      name: "Juicebox",
      albumName: "First Impressions Of Earth",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"The Strokes","uri":"artist:The_Strokes"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:live-version",
      name: "Juicebox",
      albumName: "First Impressions Of Earth",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"The Strokes","uri":"spotify:artist:0epOFNiUfyON9EYx7Tpr6V"}]"#))

    try plays.insert(.init(
      playedAt: now - 120 * 86_400,
      trackUri: "spotify:track:imported-version",
      msPlayed: 200_000,
      source: "import"))
    try plays.insert(.init(
      playedAt: now,
      trackUri: "spotify:track:live-version",
      msPlayed: 200_000,
      source: "live"))

    XCTAssertFalse(try agg.firstListen(trackUri: "spotify:track:live-version"))
    XCTAssertTrue(try agg.rediscovered(trackUri: "spotify:track:live-version"))
    XCTAssertEqual(
      try agg.lastPlayedAt(trackUri: "spotify:track:live-version", before: now),
      now - 120 * 86_400)
  }

  func test_firstListen_falseForRareTrackFromFamiliarCatalog() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000

    for i in 0..<20 {
      let uri = "spotify:track:familiar-\(i)"
      try tracks.upsert(.init(
        uri: uri,
        name: "Known \(i)",
        albumName: i < 5 ? "Known Album" : "Other Album",
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Foals","uri":"artist:Foals"}]"#))
      try plays.insert(.init(
        playedAt: now - 120 * 86_400 + Int64(i),
        trackUri: uri,
        msPlayed: 200_000,
        source: "import"))
    }

    try tracks.upsert(.init(
      uri: "spotify:track:red-socks",
      name: "Red Socks Pugie",
      albumName: "Known Album",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Foals","uri":"spotify:artist:foals"}]"#))
    try plays.insert(.init(
      playedAt: now,
      trackUri: "spotify:track:red-socks",
      msPlayed: 200_000,
      source: "live"))

    XCTAssertFalse(try agg.firstListen(trackUri: "spotify:track:red-socks"))
  }

  func test_trackIdentityMergesRemasterCleanExplicitAndPunctuationVariants() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000

    try tracks.upsert(.init(
      uri: "spotify:track:red-socks-import",
      name: "Red Socks Pugie - 2008 Remaster",
      albumName: "Antidotes",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Foals","uri":"artist:Foals"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:red-socks-live",
      name: "RED SOCKS PUGIE (Explicit)",
      albumName: "Antidotes",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"FOALS","uri":"spotify:artist:foals"}]"#))

    try plays.insert(.init(
      playedAt: now - 120 * 86_400,
      trackUri: "spotify:track:red-socks-import",
      msPlayed: 200_000,
      source: "import"))
    try plays.insert(.init(
      playedAt: now,
      trackUri: "spotify:track:red-socks-live",
      msPlayed: 200_000,
      source: "live"))

    XCTAssertFalse(try agg.firstListen(trackUri: "spotify:track:red-socks-live"))
    XCTAssertTrue(try agg.rediscovered(trackUri: "spotify:track:red-socks-live"))
    XCTAssertEqual(try agg.playsYTD(trackUri: "spotify:track:red-socks-live"), 2)
    XCTAssertEqual(
      try agg.lastPlayedAt(trackUri: "spotify:track:red-socks-live", before: now),
      now - 120 * 86_400)
  }

  func test_rank7dMergesAlternateTrackIdentitiesBeforeRanking() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000

    try tracks.upsert(.init(
      uri: "spotify:track:signal-import",
      name: "Signal Test - Remastered 2011",
      albumName: "Signal",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Dial Artist","uri":"artist:Dial"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:signal-live",
      name: "Signal Test",
      albumName: "Signal",
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Dial Artist","uri":"spotify:artist:dial"}]"#))

    for i in 0..<2 {
      try plays.insert(.init(
        playedAt: now - Int64(i + 1) * 60,
        trackUri: "spotify:track:signal-import",
        msPlayed: 200_000,
        source: "import"))
    }
    for i in 0..<4 {
      try plays.insert(.init(
        playedAt: now - Int64(i + 3) * 60,
        trackUri: "spotify:track:signal-live",
        msPlayed: 200_000,
        source: "live"))
    }

    XCTAssertEqual(try agg.rank7d(trackUri: "spotify:track:signal-live"), 1)
  }

  func test_rediscovered_gapAtLeast90Days() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 100 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now, trackUri: "OLD", msPlayed: 200_000, source: "live"))
    XCTAssertTrue(try agg.rediscovered(trackUri: "OLD"))
  }

  func test_rediscovered_falseWhenTrackWasPlayedRecently() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 100 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 2 * 86_400, trackUri: "OLD", msPlayed: 200_000, source: "live"))

    XCTAssertFalse(try agg.rediscovered(trackUri: "OLD"))
  }
  func test_onStreak_requiresPlays30dGte10AndRank7dLte5() throws {
    XCTAssertTrue(try agg.onStreak(trackUri: "C"))    // 24 plays in 30d
    XCTAssertFalse(try agg.onStreak(trackUri: "A"))   // 5 plays in 30d
  }

  // MARK: Task 13
  func test_last60MinTracks_returnsOrderedUrisWithinWindow() throws {
    let plays = PlaysDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try plays.insert(.init(playedAt: now - 10 * 60, trackUri: "X", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 5  * 60, trackUri: "Y", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 1  * 60, trackUri: "Z", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 90 * 60, trackUri: "W", msPlayed: 200_000, source: "live"))  // outside
    let items = try agg.last60MinTracks()
    XCTAssertEqual(items.map(\.trackUri), ["Z","Y","X"])  // newest first
  }

  func test_artistRank7d() throws {
    // Tracks A and B (seeded in setUp) have artists art:1 and art:2 respectively.
    // 5 plays of A in 7d > 3 plays of B → art:1 ranks first.
    XCTAssertEqual(try agg.artistRank7d(artistUri: "art:1"), 1)
    XCTAssertEqual(try agg.artistRank7d(artistUri: "art:2"), 2)
  }

  func test_artistAggregatesMergeImportedAndSpotifyIdsByDisplayName() throws {
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now: Int64 = 1_700_000_000
    try tracks.upsert(.init(
      uri: "OLD_KETTAMA",
      name: "Old KETTAMA",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"KETTAMA","uri":"artist:KETTAMA"}]"#))
    try tracks.upsert(.init(
      uri: "LIVE_KETTAMA",
      name: "Live KETTAMA",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"KETTAMA","uri":"spotify:artist:kettama"}]"#))
    try tracks.upsert(.init(
      uri: "OTHER_HIGH",
      name: "Other",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Other","uri":"spotify:artist:other"}]"#))

    try plays.insert(.init(playedAt: now - 100, trackUri: "OLD_KETTAMA", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 90, trackUri: "OLD_KETTAMA", msPlayed: 200_000, source: "import"))
    try plays.insert(.init(playedAt: now - 80, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 79, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 78, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 77, trackUri: "LIVE_KETTAMA", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 70, trackUri: "OTHER_HIGH", msPlayed: 200_000, source: "live"))
    try plays.insert(.init(playedAt: now - 60, trackUri: "OTHER_HIGH", msPlayed: 200_000, source: "live"))

    XCTAssertEqual(try agg.artistLifetimePlays(artistUri: "spotify:artist:kettama"), 6)
    XCTAssertEqual(try agg.artistRank7d(artistUri: "spotify:artist:kettama"), 1)
  }
}
