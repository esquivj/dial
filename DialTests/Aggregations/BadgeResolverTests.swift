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

  func test_livePlay_doesNotRecordNewArtistWhenImportedArtistNameAlreadyExists() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try seedTrack(dbq, uri: "OLD", artistUri: "artist:KETTAMA", artistName: "KETTAMA")
    try seedTrack(dbq, uri: "LIVE", artistUri: "spotify:artist:kettama", artistName: "KETTAMA")

    try engine.recordPlay(.init(
      playedAt: 1_600_000_000,
      trackUri: "OLD",
      msPlayed: 60_000,
      source: "import"))
    try engine.recordPlay(.init(
      playedAt: 1_700_000_000,
      trackUri: "LIVE",
      msPlayed: 60_000,
      source: "live"))

    let kinds = try BadgeEventsDAO(dbq: dbq).recent().map(\.kind)
    XCTAssertTrue(kinds.contains(.firstListen))
    XCTAssertFalse(kinds.contains(.newArtist))
  }

  func test_currentInsight_beforeCountedPlay_usesImportedArtistNameAsKnownArtist() throws {
    let dbq = try InMemoryDatabase.make()
    let engine = PetEngine(dbq: dbq, clock: { 1_700_000_000 })
    try seedTrack(dbq, uri: "OLD", artistUri: "artist:KETTAMA", artistName: "KETTAMA")
    try seedTrack(dbq, uri: "LIVE", artistUri: "spotify:artist:kettama", artistName: "KETTAMA")

    try engine.recordPlay(.init(
      playedAt: 1_600_000_000,
      trackUri: "OLD",
      msPlayed: 60_000,
      source: "import"))

    let insight = try PlayAggregations(dbq: dbq, now: { 1_700_000_000 })
      .currentBadgeInsight(trackUri: "LIVE", currentPlayAt: nil)

    XCTAssertEqual(insight?.kind, .firstListen)
    XCTAssertEqual(insight?.detail, "No plays in your history")
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

  func test_currentInsight_skipBackToAlreadyCountedTrackDoesNotShowFirstListen() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:known", artistName: "Known Artist")
    try seedTrack(dbq, uri: "OTHER", artistUri: "art:known", artistName: "Known Artist")

    try engine.recordPlay(.init(
      playedAt: anchor - 240,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))
    try engine.recordPlay(.init(
      playedAt: anchor - 120,
      trackUri: "OTHER",
      msPlayed: 60_000,
      source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: nil)

    XCTAssertNil(insight)
  }

  func test_badgeMemoryScopeIsUnique() throws {
    let dbq = try InMemoryDatabase.make()
    let event = BadgeEvent(
      id: nil,
      kind: .firstListen,
      category: .discovery,
      trackUri: "T",
      artistUri: "art:known",
      albumName: "Album",
      earnedAt: 1_700_000_000,
      payloadJson: nil,
      scopeKey: "first_listen:T")

    try dbq.write { db in
      try BadgeEventsDAO.insertIgnoring(event, in: db)
      try BadgeEventsDAO.insertIgnoring(event, in: db)
    }

    XCTAssertEqual(try BadgeEventsDAO(dbq: dbq).recent().count, 1)
  }

  func test_currentInsight_afterCountedReplay_doesNotReuseFirstListenMemory() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:known", artistName: "Known Artist")
    try seedTrack(dbq, uri: "KNOWN", artistUri: "art:known", artistName: "Known Artist", albumName: "Catalog")

    try engine.recordPlay(.init(
      playedAt: anchor - 600,
      trackUri: "KNOWN",
      msPlayed: 60_000,
      source: "import"))

    try engine.recordPlay(.init(
      playedAt: anchor - 120,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))
    try engine.recordPlay(.init(
      playedAt: anchor,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: anchor)

    XCTAssertNil(insight)
  }

  func test_currentInsight_afterDeepCutExpires_doesNotReuseOldDeepCutMemory() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    let plays = PlaysDAO(dbq: dbq)

    for i in 0..<20 {
      let uri = "ARTIST_MAIN_\(i)"
      try seedTrack(dbq, uri: uri, artistUri: "art:frequent", artistName: "Frequent Artist", albumName: "Catalog")
      try plays.insert(.init(
        playedAt: anchor - 100_000 + Int64(i),
        trackUri: uri,
        msPlayed: 60_000,
        source: "import"))
    }
    try seedTrack(dbq, uri: "RARE", artistUri: "art:frequent", artistName: "Frequent Artist", albumName: "Oddities")
    try seedTrack(dbq, uri: "OTHER", artistUri: "art:other", artistName: "Other Artist", albumName: "Break")

    for i in 0..<4 {
      try engine.recordPlay(.init(
        playedAt: anchor - 400 + Int64(i * 100),
        trackUri: "RARE",
        msPlayed: 60_000,
        source: "live"))
      if i < 3 {
        try plays.insert(.init(
          playedAt: anchor - 350 + Int64(i * 100),
          trackUri: "OTHER",
          msPlayed: 60_000,
          source: "live"))
      }
    }

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "RARE", currentPlayAt: anchor - 100)

    XCTAssertNil(insight)
  }

  func test_currentInsight_repeatTrackOnlyShowsWhenRunStarts() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:known", artistName: "Known Artist")

    for i in 0..<3 {
      try engine.recordPlay(.init(
        playedAt: anchor + Int64(i),
        trackUri: "T",
        msPlayed: 60_000,
        source: "live"))
    }

    let thirdPlay = try PlayAggregations(dbq: dbq, now: { anchor + 2 })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: anchor + 2)
    XCTAssertEqual(thirdPlay?.kind, .repeatTrack)

    try engine.recordPlay(.init(
      playedAt: anchor + 3,
      trackUri: "T",
      msPlayed: 60_000,
      source: "live"))

    let fourthPlay = try PlayAggregations(dbq: dbq, now: { anchor + 3 })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: anchor + 3)
    XCTAssertNil(fourthPlay)
  }

  func test_currentInsight_albumModeOnlyShowsWhenRunStarts() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    for uri in ["A", "B", "C", "D"] {
      try seedTrack(dbq, uri: uri, artistUri: "art:album", artistName: "Album Artist", albumName: "One Record")
    }
    try seedTrack(dbq, uri: "OTHER", artistUri: "art:other", artistName: "Other Artist", albumName: "Break")

    try engine.recordPlay(.init(playedAt: anchor - 20, trackUri: "C", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: anchor - 10, trackUri: "OTHER", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: anchor, trackUri: "A", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: anchor + 1, trackUri: "B", msPlayed: 60_000, source: "live"))
    try engine.recordPlay(.init(playedAt: anchor + 2, trackUri: "C", msPlayed: 60_000, source: "live"))

    let thirdAlbumPlay = try PlayAggregations(dbq: dbq, now: { anchor + 2 })
      .currentBadgeInsight(trackUri: "C", currentPlayAt: anchor + 2)
    XCTAssertEqual(thirdAlbumPlay?.kind, .albumMode)

    try engine.recordPlay(.init(playedAt: anchor + 3, trackUri: "A", msPlayed: 60_000, source: "live"))

    let fourthAlbumPlay = try PlayAggregations(dbq: dbq, now: { anchor + 3 })
      .currentBadgeInsight(trackUri: "A", currentPlayAt: anchor + 3)
    XCTAssertNil(fourthAlbumPlay)
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
