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

  func test_livePlay_doesNotRecordFirstListenWhenImportedTitleArtistAlreadyExists() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(
      dbq,
      uri: "spotify:track:old-juicebox",
      trackName: "Juicebox",
      artistUri: "artist:The_Strokes",
      artistName: "The Strokes")
    try seedTrack(
      dbq,
      uri: "spotify:track:live-juicebox",
      trackName: "Juicebox",
      artistUri: "spotify:artist:strokes",
      artistName: "The Strokes")

    try recordOldFavorite(engine, trackUri: "spotify:track:old-juicebox", lastPlayedAt: anchor - 200 * 86_400)
    try engine.recordPlay(.init(
      playedAt: anchor,
      trackUri: "spotify:track:live-juicebox",
      msPlayed: 60_000,
      source: "live"))

    let kinds = try BadgeEventsDAO(dbq: dbq).recent().map(\.kind)
    XCTAssertFalse(kinds.contains(.firstListen))
    XCTAssertTrue(kinds.contains(.rediscovered))
  }

  func test_livePlay_doesNotRecordFirstListenForRemasterCleanExplicitVariant() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(
      dbq,
      uri: "spotify:track:old-red-socks",
      trackName: "Red Socks Pugie - 2008 Remaster",
      artistUri: "artist:Foals",
      artistName: "Foals")
    try seedTrack(
      dbq,
      uri: "spotify:track:live-red-socks",
      trackName: "RED SOCKS PUGIE (Clean)",
      artistUri: "spotify:artist:foals",
      artistName: "FOALS")

    try recordOldFavorite(engine, trackUri: "spotify:track:old-red-socks", lastPlayedAt: anchor - 200 * 86_400)
    try engine.recordPlay(.init(
      playedAt: anchor,
      trackUri: "spotify:track:live-red-socks",
      msPlayed: 60_000,
      source: "live"))

    let kinds = try BadgeEventsDAO(dbq: dbq).recent().map(\.kind)
    XCTAssertFalse(kinds.contains(.firstListen))
    XCTAssertTrue(kinds.contains(.rediscovered))
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
    XCTAssertEqual(insight?.detail, "First time in your history")
  }

  func test_currentInsight_beforeCountedPlay_usesImportedTitleArtistAsKnownTrack() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(
      dbq,
      uri: "spotify:track:old-juicebox",
      trackName: "Juicebox",
      artistUri: "artist:The_Strokes",
      artistName: "The Strokes")
    try seedTrack(
      dbq,
      uri: "spotify:track:live-juicebox",
      trackName: "Juicebox",
      artistUri: "spotify:artist:strokes",
      artistName: "The Strokes")

    try recordOldFavorite(engine, trackUri: "spotify:track:old-juicebox", lastPlayedAt: anchor - 200 * 86_400)

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "spotify:track:live-juicebox", currentPlayAt: nil)

    XCTAssertEqual(insight?.kind, .rediscovered)
    XCTAssertEqual(insight?.detail, "Last played 200 days ago")
  }

  func test_currentInsight_beforeCountedPlay_explainsRemasterVariantAsKnownTrack() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(
      dbq,
      uri: "spotify:track:old-red-socks",
      trackName: "Red Socks Pugie - 2008 Remaster",
      artistUri: "artist:Foals",
      artistName: "Foals")
    try seedTrack(
      dbq,
      uri: "spotify:track:live-red-socks",
      trackName: "Red Socks Pugie",
      artistUri: "spotify:artist:foals",
      artistName: "FOALS")

    try recordOldFavorite(engine, trackUri: "spotify:track:old-red-socks", lastPlayedAt: anchor - 200 * 86_400)

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "spotify:track:live-red-socks", currentPlayAt: nil)

    XCTAssertEqual(insight?.kind, .rediscovered)
    XCTAssertEqual(insight?.detail, "Last played 200 days ago")
    XCTAssertEqual(
      insight?.explanation,
      "Shown because the previous play was 200 days ago. "
        + "Rediscovered needs a 180+ day gap and 5+ earlier plays, at most once a day.")
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
    XCTAssertFalse(kinds.contains(.firstListen))
  }

  func test_currentInsight_beforeCountedPlay_prefersDeepCutForFamiliarCatalog() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let plays = PlaysDAO(dbq: dbq)

    for i in 0..<20 {
      let uri = "ARTIST_MAIN_\(i)"
      try seedTrack(dbq, uri: uri, artistUri: "art:frequent", artistName: "Frequent Artist", albumName: "Known Album")
      try plays.insert(.init(
        playedAt: anchor - 120 * 86_400 + Int64(i),
        trackUri: uri,
        msPlayed: 60_000,
        source: "import"))
    }
    try seedTrack(dbq, uri: "RARE", artistUri: "spotify:artist:frequent", artistName: "Frequent Artist", albumName: "Known Album")

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "RARE", currentPlayAt: nil)

    XCTAssertEqual(insight?.kind, .deepCut)
    XCTAssertEqual(insight?.detail, "1 play · 20 from this artist")
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

  func test_albumModeUsesArtistIdentityAliasAcrossImportAndLiveIds() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor: Int64 = 1_700_000_000
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    let plays = PlaysDAO(dbq: dbq)

    try seedTrack(
      dbq,
      uri: "OLD_A",
      artistUri: "artist:Foals",
      artistName: "Foals",
      albumName: "Antidotes")
    try seedTrack(
      dbq,
      uri: "OLD_B",
      artistUri: "artist:Foals",
      artistName: "Foals",
      albumName: "Antidotes")
    try seedTrack(
      dbq,
      uri: "LIVE_C",
      artistUri: "spotify:artist:foals",
      artistName: "Foals",
      albumName: "Antidotes")

    _ = try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db)
    }

    try plays.insert(.init(
      playedAt: anchor - 2,
      trackUri: "OLD_A",
      msPlayed: 60_000,
      source: "import"))
    try plays.insert(.init(
      playedAt: anchor - 1,
      trackUri: "OLD_B",
      msPlayed: 60_000,
      source: "import"))

    try engine.recordPlay(.init(
      playedAt: anchor,
      trackUri: "LIVE_C",
      msPlayed: 60_000,
      source: "live"))

    let kinds = try BadgeEventsDAO(dbq: dbq).recent().map(\.kind)
    XCTAssertTrue(kinds.contains(.albumMode))
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
        playedAt: firstReturn - 200 * 86_400 - Int64(i) * 86_400,
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
    XCTAssertEqual(insight?.detail, "Came back after 200 days")
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

  // MARK: Deep Cut stays rare (PLA-100)

  /// 20 imported plays of other tracks by "Loved Artist", so its rare tracks
  /// R1 and R2 qualify as deep cuts.
  private func seedFamiliarArtist(_ dbq: DatabaseQueue, engine: PetEngine, anchor: Int64) throws {
    for i in 0..<20 {
      try seedTrack(dbq, uri: "F\(i)", trackName: "Hit \(i)", artistUri: "art:loved", artistName: "Loved Artist")
      try engine.recordPlay(.init(
        playedAt: anchor - 400 * 86_400 + Int64(i) * 3_600, trackUri: "F\(i)", msPlayed: 60_000, source: "import"))
    }
    for uri in ["R1", "R2"] {
      try seedTrack(dbq, uri: uri, trackName: "Rare \(uri)", artistUri: "art:loved", artistName: "Loved Artist")
    }
  }

  private func deepCuts(_ dbq: DatabaseQueue) throws -> [String] {
    try BadgeEventsDAO(dbq: dbq).recent().filter { $0.kind == .deepCut }.compactMap(\.trackUri).sorted()
  }

  func test_deepCut_neverAwardedToRecentlyPlayedBackfill() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor = localNoon
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedFamiliarArtist(dbq, engine: engine, anchor: anchor)

    try engine.recordPlay(.init(playedAt: anchor, trackUri: "R1", msPlayed: 60_000, source: "recent"))

    XCTAssertEqual(try deepCuts(dbq), [])
  }

  func test_deepCut_atMostOncePerDay() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor = localNoon
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedFamiliarArtist(dbq, engine: engine, anchor: anchor)

    try engine.recordPlay(.init(playedAt: anchor, trackUri: "R1", msPlayed: 60_000, source: "live"))
    // R2 qualifies too, but R1 was already today's deep cut: no badge and
    // no pop-up for R2. R1 itself keeps showing it.
    let agg = PlayAggregations(dbq: dbq, now: { anchor + 600 })
    XCTAssertNotEqual(try agg.currentBadgeInsight(trackUri: "R2", currentPlayAt: nil)?.kind, .deepCut)
    XCTAssertEqual(try agg.currentBadgeInsight(trackUri: "R1", currentPlayAt: anchor)?.kind, .deepCut)
    try engine.recordPlay(.init(playedAt: anchor + 600, trackUri: "R2", msPlayed: 60_000, source: "live"))
    XCTAssertEqual(try deepCuts(dbq), ["R1"])

    // The next day R2 (still only 2 plays) gets its turn.
    try engine.recordPlay(.init(playedAt: anchor + 86_400, trackUri: "R2", msPlayed: 60_000, source: "live"))
    XCTAssertEqual(try deepCuts(dbq), ["R1", "R2"])
  }

  // MARK: Rediscovered stays rare (PLA-95)

  /// Noon local time, so a test's plays never straddle midnight.
  private var localNoon: Int64 {
    let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    return Int64(day.timeIntervalSince1970) + 12 * 3_600
  }

  private func rediscoveredCount(_ dbq: DatabaseQueue) throws -> Int {
    try BadgeEventsDAO(dbq: dbq).recent().filter { $0.kind == .rediscovered }.count
  }

  func test_rediscovered_needsLongGapAndRealHistory() throws {
    let anchor = localNoon
    func earns(priorPlays: Int, daysAgo: Int64) throws -> Bool {
      let dbq = try InMemoryDatabase.make()
      let engine = PetEngine(dbq: dbq, clock: { anchor })
      try seedTrack(dbq, uri: "T", artistUri: "art:old", artistName: "Old Artist")
      try recordOldFavorite(engine, trackUri: "T", lastPlayedAt: anchor - daysAgo * 86_400, plays: priorPlays)
      try engine.recordPlay(.init(playedAt: anchor, trackUri: "T", msPlayed: 60_000, source: "live"))
      return try rediscoveredCount(dbq) == 1
    }
    XCTAssertTrue(try earns(priorPlays: 5, daysAgo: 180))
    XCTAssertFalse(try earns(priorPlays: 5, daysAgo: 179), "gap under 180 days")
    XCTAssertFalse(try earns(priorPlays: 4, daysAgo: 400), "fewer than 5 earlier plays")
  }

  func test_rediscovered_neverAwardedToRecentlyPlayedBackfill() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor = localNoon
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:old", artistName: "Old Artist")
    try recordOldFavorite(engine, trackUri: "T", lastPlayedAt: anchor - 400 * 86_400)

    try engine.recordPlay(.init(playedAt: anchor, trackUri: "T", msPlayed: 60_000, source: "recent"))

    XCTAssertEqual(try rediscoveredCount(dbq), 0)
  }

  func test_rediscovered_atMostOncePerDay() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor = localNoon
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    for uri in ["A", "B"] {
      try seedTrack(dbq, uri: uri, trackName: uri, artistUri: "art:\(uri)", artistName: "Artist \(uri)")
      try recordOldFavorite(engine, trackUri: uri, lastPlayedAt: anchor - 300 * 86_400)
    }

    try engine.recordPlay(.init(playedAt: anchor, trackUri: "A", msPlayed: 60_000, source: "live"))
    // B qualifies too, but A already came back today: no badge, and no
    // pop-up for B either.
    let insightForB = try PlayAggregations(dbq: dbq, now: { anchor + 600 })
      .currentBadgeInsight(trackUri: "B", currentPlayAt: nil)
    XCTAssertNotEqual(insightForB?.kind, .rediscovered)
    try engine.recordPlay(.init(playedAt: anchor + 600, trackUri: "B", msPlayed: 60_000, source: "live"))
    XCTAssertEqual(try BadgeEventsDAO(dbq: dbq).recent().filter { $0.kind == .rediscovered }.map(\.trackUri), ["A"])

    // The next day B can come back.
    let tomorrow = anchor + 86_400
    try engine.recordPlay(.init(playedAt: tomorrow, trackUri: "B", msPlayed: 60_000, source: "live"))
    XCTAssertEqual(try rediscoveredCount(dbq), 1, "B was played yesterday, so it is no longer a 180-day return")
  }

  func test_rediscovered_sameTrackKeepsItsAfterglowAfterEarningToday() throws {
    let dbq = try InMemoryDatabase.make()
    let anchor = localNoon
    let engine = PetEngine(dbq: dbq, clock: { anchor })
    try seedTrack(dbq, uri: "T", artistUri: "art:old", artistName: "Old Artist")
    try recordOldFavorite(engine, trackUri: "T", lastPlayedAt: anchor - 300 * 86_400)
    try engine.recordPlay(.init(playedAt: anchor, trackUri: "T", msPlayed: 60_000, source: "live"))

    let insight = try PlayAggregations(dbq: dbq, now: { anchor })
      .currentBadgeInsight(trackUri: "T", currentPlayAt: anchor)
    XCTAssertEqual(insight?.kind, .rediscovered)
    XCTAssertTrue(try PlayAggregations(dbq: dbq, now: { anchor + 60 }).rediscovered(trackUri: "T"))
  }

  /// Imports `plays` plays of a track, the latest at `lastPlayedAt` and the
  /// rest a day apart before it.
  private func recordOldFavorite(_ engine: PetEngine, trackUri: String, lastPlayedAt: Int64, plays: Int = 5) throws {
    for i in 0..<plays {
      try engine.recordPlay(.init(
        playedAt: lastPlayedAt - Int64(i) * 86_400,
        trackUri: trackUri,
        msPlayed: 60_000,
        source: "import"))
    }
  }

  private func seedTrack(
    _ dbq: DatabaseQueue,
    uri: String,
    trackName: String? = nil,
    artistUri: String,
    artistName: String,
    albumName: String = "Album"
  ) throws {
    try TracksDAO(dbq: dbq).upsert(.init(
      uri: uri,
      name: trackName ?? uri,
      albumName: albumName,
      albumArtUrl: nil,
      durationMs: 1_000,
      artistsJson: #"[{"name":"\#(artistName)","uri":"\#(artistUri)"}]"#))
  }
}
