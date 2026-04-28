// DialTests/Aggregations/BadgeResolverTests.swift
import GRDB
import XCTest
@testable import Dial

final class BadgeResolverTests: XCTestCase {
  func test_liveFirstPlay_recordsDiscoveryMemories() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try seedTrack(dbq, uri: "T", artistUri: "art:new", artistName: "New Artist")

    try engine.recordPlay(.init(playedAt: 1_700_000_000, trackUri: "T", msPlayed: 60_000, source: "live"))

    let kinds = try Set(BadgeEventsDAO(dbq: dbq).recent().map(\.kind))
    XCTAssertTrue(kinds.contains(.firstListen))
    XCTAssertTrue(kinds.contains(.newArtist))
  }

  func test_importedHistory_skipsDiscoverySpam_butRecordsMilestones() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try seedTrack(dbq, uri: "T", artistUri: "art:old", artistName: "Old Artist")

    for i in 0..<10 {
      try engine.recordPlay(.init(
        playedAt: 1_600_000_000 + Int64(i) * 86_400,
        trackUri: "T",
        msPlayed: 60_000,
        source: "import"))
    }

    let events = try BadgeEventsDAO(dbq: dbq).recent()
    XCTAssertEqual(events.map(\.kind), [.play10])
  }

  func test_deepCut_recordsForRareTrackFromFrequentArtist() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    let tracks = TracksDAO(dbq: dbq)
    let plays = PlaysDAO(dbq: dbq)

    for i in 0..<19 {
      let uri = "ARTIST_MAIN_\(i)"
      try seedTrack(dbq, uri: uri, artistUri: "art:frequent", artistName: "Frequent Artist")
      try plays.insert(.init(
        playedAt: 1_690_000_000 + Int64(i),
        trackUri: uri,
        msPlayed: 60_000,
        source: "import"))
    }
    try tracks.upsert(.init(
      uri: "RARE",
      name: "Rare",
      albumName: "Oddities",
      albumArtUrl: nil,
      durationMs: 1_000,
      artistsJson: #"[{"name":"Frequent Artist","uri":"art:frequent"}]"#))

    try engine.recordPlay(.init(
      playedAt: 1_700_000_000,
      trackUri: "RARE",
      msPlayed: 60_000,
      source: "live"))

    let kinds = try Set(BadgeEventsDAO(dbq: dbq).recent().map(\.kind))
    XCTAssertTrue(kinds.contains(.deepCut))
  }

  func test_currentInsight_beforeCountedPlay_surfacesNewArtistContext() throws {
    let dbq = try InMemoryDatabase.make()
    try seedTrack(dbq, uri: "T", artistUri: "art:new", artistName: "New Artist")

    let insight = try PlayAggregations(dbq: dbq, now: { 1_700_000_000 })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: nil)

    XCTAssertEqual(insight?.kind, .newArtist)
    XCTAssertEqual(insight?.detail, "First track from this artist")
  }

  func test_currentInsight_doesNotReuseFirstListenForUncountedReplay() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:new", artistName: "New Artist")
    try engine.recordPlay(.init(
      playedAt: anchor - 120,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: nil)

    XCTAssertNil(insight)
  }

  func test_currentInsight_afterCountedPlay_surfacesMilestone() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try seedTrack(dbq, uri: "T", artistUri: "art:repeat", artistName: "Repeat Artist")

    for i in 0..<9 {
      try engine.recordPlay(.init(
        playedAt: 1_600_000_000 + Int64(i) * 86_400,
        trackUri: "T",
        msPlayed: 60_000,
        source: "import"))
    }
    try engine.recordPlay(.init(
      playedAt: 1_700_000_000,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { 1_700_000_000 })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: 1_700_000_000)

    XCTAssertEqual(insight?.kind, .play10)
    XCTAssertEqual(insight?.detail, "10 lifetime plays")
  }

  func test_currentInsight_reusesRecentRediscoveryForSameDayReplay() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let firstReturn = anchor - 3_600
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    let plays = PlaysDAO(dbq: dbq)
    try seedTrack(dbq, uri: "T", artistUri: "art:old", artistName: "Old Artist")

    for i in 0..<9 {
      try engine.recordPlay(.init(
        playedAt: firstReturn - 100 * 86_400 - Int64(i) * 86_400,
        trackUri: "T",
        msPlayed: 60_000,
        source: "import"))
    }
    try engine.recordPlay(.init(
      playedAt: firstReturn,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))
    try plays.insert(.init(
      playedAt: anchor - 1_800,
      trackUri: "OTHER",
      msPlayed: 60_000,
      source: "live"))
    try engine.recordPlay(.init(
      playedAt: anchor,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: anchor)

    XCTAssertEqual(insight?.kind, .rediscovered)
    XCTAssertEqual(insight?.detail, "Came back after 100 days")
  }

  func test_repeatAndAlbumMode_recordOnceWhenRunStarts() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    for uri in ["A", "B", "C"] {
      try seedTrack(dbq, uri: uri, artistUri: "art:album", artistName: "Album Artist", albumName: "One Record")
    }

    try engine.recordPlay(.init(playedAt: 1_700_000_000, trackUri: "A", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: 1_700_000_002, trackUri: "B", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: 1_700_000_004, trackUri: "C", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: 1_700_000_006, trackUri: "C", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: 1_700_000_008, trackUri: "C", msPlayed: 60_000, source: "live"))

    let kinds = try BadgeEventsDAO(dbq: dbq).recent().map(\.kind)
    XCTAssertEqual(kinds.filter { $0 == .albumMode }.count, 1)
    XCTAssertEqual(kinds.filter { $0 == .repeatTrack }.count, 1)
  }

  private func seedTrack(
    _ dbq: DatabaseQueue,
    uri: String,
    artistUri: String,
    artistName: String,
    albumName: String = "Album"
  ) throws {
    try TracksDAO(dbq: dbq).upsert(.init(
      uri: uri,
      name: uri,
      albumName: albumName,
      albumArtUrl: nil,
      durationMs: 1_000,
      artistsJson: #"[{"name":"\#(artistName)","uri":"\#(artistUri)"}]"#))
  }
}
