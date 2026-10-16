// DialTests/Aggregations/StatsQueriesTests.swift
import XCTest
import GRDB
import Foundation
@testable import Dial

final class StatsQueriesTests: XCTestCase {
  func test_weekdayRhythm_normalizesByWeekdayOccurrences() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let rangeStart = localEpoch(year: 2024, month: 1, day: 1, hour: 0)
    let now = localEpoch(year: 2024, month: 1, day: 15, hour: 12)

    // Jan 1/8/15 2024 are Mondays: 6 raw plays across 3 Mondays = 2.0/day.
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 1, hour: 12), track: "mon")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 8, hour: 12), track: "mon")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 15, hour: 12), track: "mon")

    // Jan 2/9 are Tuesdays: fewer raw plays, but stronger normalized rhythm.
    try insertPlays(plays, count: 3, startingAt: localEpoch(year: 2024, month: 1, day: 2, hour: 12), track: "tue")
    try insertPlays(plays, count: 2, startingAt: localEpoch(year: 2024, month: 1, day: 9, hour: 12), track: "tue")

    let buckets = try StatsQueries(dbq: dbq).weekdayRhythm(since: rangeStart, now: now)
    let monday = try XCTUnwrap(buckets.first { $0.label == "MON" })
    let tuesday = try XCTUnwrap(buckets.first { $0.label == "TUE" })

    XCTAssertEqual(monday.count, 6)
    XCTAssertEqual(monday.occurrences, 3)
    XCTAssertEqual(monday.value, 2.0, accuracy: 0.001)
    XCTAssertEqual(tuesday.count, 5)
    XCTAssertEqual(tuesday.occurrences, 2)
    XCTAssertEqual(tuesday.value, 2.5, accuracy: 0.001)
    XCTAssertEqual(buckets.max(by: { $0.value < $1.value })?.label, "TUE")
  }

  func test_recentDailyRhythm_usesChronologicalSevenDayBuckets() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 15, hour: 12)

    try insertPlays(plays, count: 1, startingAt: localEpoch(year: 2024, month: 1, day: 9, hour: 12), track: "first")
    try insertPlays(plays, count: 3, startingAt: now - 10, track: "today")

    let buckets = try StatsQueries(dbq: dbq).recentDailyRhythm(days: 7, now: now)

    XCTAssertEqual(buckets.count, 7)
    XCTAssertEqual(buckets.first?.label, "TUE")
    XCTAssertEqual(buckets.first?.count, 1)
    let today = try XCTUnwrap(buckets.last)
    XCTAssertEqual(today.label, "TODAY")
    XCTAssertEqual(today.count, 3)
    XCTAssertEqual(today.value, 3.0, accuracy: 0.001)
  }

  func test_topGenres_countsArtistDerivedGenreSignals() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let artists = ArtistsDAO(dbq: dbq)

    try artists.upsert(.init(
      uri: "spotify:artist:A",
      name: "Artist A",
      genresJson: #"["rap","atl hip hop"]"#,
      imageUrl: nil))
    try artists.upsert(.init(
      uri: "spotify:artist:B",
      name: "Artist B",
      genresJson: #"["rap"]"#,
      imageUrl: nil))

    try tracks.upsert(.init(
      uri: "spotify:track:A1",
      name: "A1",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Artist A","uri":"spotify:artist:A"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:B1",
      name: "B1",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Artist B","uri":"spotify:artist:B"}]"#))

    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:A1", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:A1", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 3, trackUri: "spotify:track:B1", msPlayed: 180_000, source: "import"))

    let genres = try StatsQueries(dbq: dbq).topGenres(limit: 2)

    XCTAssertEqual(genres.map(\.genre), ["rap", "atl hip hop"])
    XCTAssertEqual(genres[0].playCount, 3)
    XCTAssertEqual(genres[0].artistCount, 2)
    XCTAssertEqual(genres[1].playCount, 2)
    XCTAssertEqual(genres[1].artistCount, 1)
  }

  func test_topGenres_prefersNormalizedSoundFamilies() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let artists = ArtistsDAO(dbq: dbq)

    try artists.upsert(.init(
      uri: "spotify:artist:A",
      name: "Artist A",
      genresJson: #"["pop"]"#,
      imageUrl: nil))
    try tracks.upsert(.init(
      uri: "spotify:track:A1",
      name: "A1",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Artist A","uri":"spotify:artist:A"}]"#))
    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:A1", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:A1", msPlayed: 180_000, source: "import"))

    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:A', 'artist', 'lastfm', 'corridos', 'corridos tumbados', 100, 10)
      """)
    }

    let genres = try StatsQueries(dbq: dbq).topGenres(limit: 2)

    XCTAssertEqual(genres.map(\.genre), ["corridos"])
    XCTAssertEqual(genres[0].playCount, 2)
    XCTAssertEqual(genres[0].detailTags, ["corridos tumbados"])
  }

  func test_topGenresIncludesResolvedThemeForSoundSignalColor() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:techno",
      name: "Techno",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Hard Techno Artist","uri":"spotify:artist:techno"}]"#))
    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:techno", msPlayed: 180_000, source: "import"))
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:techno', 'artist', 'lastfm', 'electronic', 'hard techno', 100, 10)
      """)
    }

    let genres = try StatsQueries(dbq: dbq).topGenres(limit: 1)

    XCTAssertEqual(genres.first?.theme, .slime)
  }

  func test_topArtistsDedupesSyntheticAndSpotifyIdsByDisplayName() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:imported",
      name: "Imported",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:live",
      name: "Live",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"spotify:artist:juniorh"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:other",
      name: "Other",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Peso Pluma","uri":"spotify:artist:peso"}]"#))

    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 3, trackUri: "spotify:track:live", msPlayed: 180_000, source: "live"))
    try plays.insert(.init(playedAt: 4, trackUri: "spotify:track:live", msPlayed: 180_000, source: "live"))
    try plays.insert(.init(playedAt: 5, trackUri: "spotify:track:live", msPlayed: 180_000, source: "live"))
    try plays.insert(.init(playedAt: 6, trackUri: "spotify:track:other", msPlayed: 180_000, source: "live"))

    let artists = try StatsQueries(dbq: dbq).topArtists(limit: 10)

    XCTAssertEqual(artists.filter { $0.name == "Junior H" }.count, 1)
    XCTAssertEqual(artists.first?.name, "Junior H")
    XCTAssertEqual(artists.first?.count, 5)
    XCTAssertEqual(artists.first?.uri, "spotify:artist:juniorh")
  }

  func test_topArtistsDedupesDisplayNameCaseAndWhitespace() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:one",
      name: "One",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":" Junior H ","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:two",
      name: "Two",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"junior h","uri":"spotify:artist:juniorh"}]"#))

    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:one", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:two", msPlayed: 180_000, source: "live"))

    let artists = try StatsQueries(dbq: dbq).topArtists(limit: 10)

    XCTAssertEqual(artists.count, 1)
    XCTAssertEqual(artists.first?.count, 2)
    XCTAssertEqual(artists.first?.uri, "spotify:artist:juniorh")
  }

  func test_artistIdentityRepairCreatesExactNameAliases() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:imported",
      name: "Imported",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:live",
      name: "Live",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"spotify:artist:juniorh"}]"#))

    let aliasCount = try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
    }

    XCTAssertEqual(aliasCount, 1)
    let row = try dbq.read { db in
      try Row.fetchOne(db, sql: """
        SELECT source_uri, canonical_uri, canonical_name, confidence, reason
        FROM artist_identity_aliases
        WHERE source_uri = 'artist:Junior_H'
      """)
    }
    XCTAssertEqual(row?["canonical_uri"], "spotify:artist:juniorh")
    XCTAssertEqual(row?["canonical_name"], "Junior H")
    let confidence: Double? = row?["confidence"]
    XCTAssertEqual(confidence, 1.0)
    XCTAssertEqual(row?["reason"], "exact_normalized_name")
  }

  func test_artistIdentityRepairSkipsAmbiguousCanonicalNames() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:fallback",
      name: "Fallback",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Phoenix","uri":"artist:Phoenix"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:one",
      name: "One",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Phoenix","uri":"spotify:artist:one"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:two",
      name: "Two",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Phoenix","uri":"spotify:artist:two"}]"#))

    let aliasCount = try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
    }

    XCTAssertEqual(aliasCount, 0)
  }

  func test_topGenresUsesCanonicalTagsThroughArtistAlias() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:imported",
      name: "Imported Corrido",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:canonical",
      name: "Canonical Corrido",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"spotify:artist:juniorh"}]"#))
    try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:juniorh', 'artist', 'lastfm', 'corridos', 'corridos tumbados', 100, 10)
      """)
    }
    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))

    let genres = try StatsQueries(dbq: dbq).topGenres(limit: 1)

    XCTAssertEqual(genres.first?.genre, "corridos")
    XCTAssertEqual(genres.first?.playCount, 2)
    XCTAssertEqual(genres.first?.artistCount, 1)
  }

  func test_totalsCountsAliasedArtistsOnce() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:imported",
      name: "Imported",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:live",
      name: "Live",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"spotify:artist:juniorh"}]"#))
    try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
    }
    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:live", msPlayed: 180_000, source: "live"))

    let totals = try StatsQueries(dbq: dbq).totals()

    XCTAssertEqual(totals.uniqueArtists, 1)
  }

  func test_soundTheme_reNormalizesRawTagsForCurrentRulebook() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:A', 'artist', 'lastfm', 'punk/emo', 'hardcore', 100, 10),
          ('spotify:artist:A', 'artist', 'lastfm', 'punk/emo', 'beatdown hardcore', 69, 10),
          ('spotify:artist:A', 'artist', 'lastfm', 'electronic', 'electronic', 17, 10),
          ('spotify:artist:A', 'artist', 'lastfm', 'electronic', 'techno', 1, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:A")

    XCTAssertEqual(theme, .aqua)
  }

  func test_soundTheme_treatsGenericElectronicPopAsAqua() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:froufrou', 'artist', 'lastfm', 'electronic', 'electronic', 100, 10),
          ('spotify:artist:froufrou', 'artist', 'lastfm', 'electronic', 'electronica', 12, 10),
          ('spotify:artist:froufrou', 'artist', 'lastfm', 'indie', 'indie', 55, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:froufrou")

    XCTAssertEqual(theme, .aqua)
  }

  func test_soundTheme_treatsAmbientChillwaveAsAqua() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:bedroom', 'artist', 'lastfm', 'ambient', 'chillwave', 100, 10),
          ('spotify:artist:bedroom', 'artist', 'lastfm', 'ambient', 'ambient', 92, 10),
          ('spotify:artist:bedroom', 'artist', 'lastfm', 'indie', 'lo fi', 60, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:bedroom")

    XCTAssertEqual(theme, .aqua)
  }

  func test_soundTheme_treatsTheBraveryStyleTagsAsAqua() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:bravery', 'artist', 'lastfm', 'indie', 'indie rock', 100, 10),
          ('spotify:artist:bravery', 'artist', 'lastfm', 'indie', 'indie', 99, 10),
          ('spotify:artist:bravery', 'artist', 'lastfm', 'rock', 'rock', 45, 10),
          ('spotify:artist:bravery', 'artist', 'lastfm', 'indie', 'alternative rock', 19, 10),
          ('spotify:artist:bravery', 'artist', 'lastfm', 'electronic', 'electronic', 4, 10),
          ('spotify:artist:bravery', 'artist', 'lastfm', 'punk/emo', 'post-punk revival', 1, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:bravery")

    XCTAssertEqual(theme, .aqua)
  }

  func test_tagNormalizerKeepsGarageRockAndDancePunkOutOfElectronicFamily() {
    XCTAssertEqual(DialTagNormalizer.normalize("garage rock")?.family, "rock")
    XCTAssertEqual(DialTagNormalizer.normalize("garage rock revival")?.family, "rock")
    XCTAssertEqual(DialTagNormalizer.normalize("dance-punk")?.family, "punk/emo")
    XCTAssertEqual(DialTagNormalizer.normalize("dance rock")?.family, "rock")
    XCTAssertEqual(DialTagNormalizer.normalize("uk garage")?.family, "electronic")
    XCTAssertEqual(DialTagNormalizer.normalize("post brexit new wave")?.family, "rock")
    XCTAssertEqual(DialTagNormalizer.normalize("new wave of british heavy metal")?.family, "metal")
    XCTAssertNil(DialTagNormalizer.normalize("post"))
  }

  func test_soundTheme_defaultsLatinSpanishFamiliesToSmokeGel() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:badbunny', 'artist', 'lastfm', 'reggaeton', 'urbano latino', 100, 10),
          ('spotify:artist:badbunny', 'artist', 'lastfm', 'latin', 'latin', 80, 10),
          ('spotify:artist:juniorh', 'artist', 'lastfm', 'corridos', 'corridos tumbados', 100, 10),
          ('spotify:artist:juniorh', 'artist', 'lastfm', 'latin', 'spanish', 60, 10)
      """)
    }

    let queries = StatsQueries(dbq: dbq)

    XCTAssertEqual(try queries.soundTheme(forArtistUri: "spotify:artist:badbunny"), .classic)
    XCTAssertEqual(try queries.soundTheme(forArtistUri: "spotify:artist:juniorh"), .classic)
  }

  func test_soundThemeUsesCanonicalTagsThroughArtistAlias() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:fallback",
      name: "Fallback Techno",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Kettama","uri":"artist:Kettama"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:canonical",
      name: "Canonical Techno",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Kettama","uri":"spotify:artist:kettama"}]"#))
    try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:kettama', 'artist', 'lastfm', 'electronic', 'hard techno', 100, 10)
      """)
    }

    let decision = try StatsQueries(dbq: dbq).soundThemeDecision(
      forArtistUris: ["artist:Kettama"],
      trackName: "Imported Techno",
      artistName: "Kettama",
      albumName: "",
      allowRecentFallback: false)

    XCTAssertEqual(decision?.theme, .slime)
    XCTAssertEqual(decision?.source, .artistTags)
  }

  func test_soundTheme_defaultsMainstreamRapAndRnbToSmokeGel() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:drake', 'artist', 'lastfm', 'rap', 'rap', 71, 10),
          ('spotify:artist:drake', 'artist', 'lastfm', 'r&b', 'rnb', 34, 10),
          ('spotify:artist:drake', 'artist', 'lastfm', 'rap', 'hip hop', 26, 10),
          ('spotify:artist:drake', 'artist', 'lastfm', 'pop', 'pop', 3, 10)
      """)
    }

    let decision = try StatsQueries(dbq: dbq).soundThemeDecision(
      forArtistUris: ["spotify:artist:drake"],
      trackName: "What Did I Miss?",
      artistName: "Drake",
      albumName: "",
      allowRecentFallback: false)

    XCTAssertEqual(decision?.theme, .classic)
    XCTAssertEqual(decision?.source, .artistTags)
  }

  func test_soundTheme_biasesCoreLibraryArtistsToSmokeGelWhenSignalIsWeak() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    let plays = PlaysDAO(dbq: dbq)
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:core', 'artist', 'lastfm', 'indie', 'indie', 100, 10),
          ('spotify:artist:core', 'artist', 'lastfm', 'pop', 'pop', 40, 10)
      """)
    }
    try tracks.upsert(.init(
      uri: "spotify:track:core",
      name: "Core Memory",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Core Artist","uri":"spotify:artist:core"}]"#))
    for idx in 0..<50 {
      try plays.insert(.init(
        playedAt: Int64(idx + 1),
        trackUri: "spotify:track:core",
        msPlayed: 180_000,
        source: "import"))
    }

    let decision = try StatsQueries(dbq: dbq).soundThemeDecision(
      forArtistUris: ["spotify:artist:core"],
      trackName: "Core Memory",
      artistName: "Core Artist",
      albumName: "",
      allowRecentFallback: false)

    XCTAssertEqual(decision?.theme, .classic)
    XCTAssertTrue(decision?.reason.contains("core-library artist") == true)
  }

  func test_soundTheme_doesNotLetCoreLibraryBiasOverrideStrongElectronic() throws {
    let dbq = try InMemoryDatabase.make()
    let tracks = TracksDAO(dbq: dbq)
    let plays = PlaysDAO(dbq: dbq)
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:coretechno', 'artist', 'lastfm', 'electronic', 'hard techno', 100, 10),
          ('spotify:artist:coretechno', 'artist', 'lastfm', 'pop', 'pop', 10, 10)
      """)
    }
    try tracks.upsert(.init(
      uri: "spotify:track:coretechno",
      name: "Core Techno",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Core Techno","uri":"spotify:artist:coretechno"}]"#))
    for idx in 0..<50 {
      try plays.insert(.init(
        playedAt: Int64(idx + 1),
        trackUri: "spotify:track:coretechno",
        msPlayed: 180_000,
        source: "import"))
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:coretechno")

    XCTAssertEqual(theme, .slime)
  }

  func test_soundThemeTransitionKeepsPreviousThemeWhenNewTrackHasNoFreshDecision() {
    let resolved = AppCoordinator.resolvedSoundThemeState(
      currentTheme: .slime,
      hasTrack: true,
      decision: nil)

    XCTAssertEqual(resolved.theme, .slime)
    XCTAssertEqual(resolved.decision?.source, .held)
    XCTAssertEqual(resolved.decision?.theme, .slime)
  }

  func test_soundTheme_keepsLatinHouseElectronic() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:latinhouse', 'artist', 'lastfm', 'latin', 'latin house', 100, 10),
          ('spotify:artist:latinhouse', 'artist', 'lastfm', 'latin', 'spanish', 80, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:latinhouse")

    XCTAssertEqual(theme, .slime)
  }

  func test_soundTheme_keepsSpanishMetalMagenta() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:spanishmetal', 'artist', 'lastfm', 'latin', 'spanish metal', 100, 10),
          ('spotify:artist:spanishmetal', 'artist', 'lastfm', 'latin', 'spanish', 80, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:spanishmetal")

    XCTAssertEqual(theme, .ember)
  }

  func test_soundTheme_keepsExplicitHardcorePunkInEmber() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:A', 'artist', 'lastfm', 'punk/emo', 'hardcore punk', 100, 10),
          ('spotify:artist:A', 'artist', 'lastfm', 'electronic', 'techno', 25, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:A")

    XCTAssertEqual(theme, .ember)
  }

  func test_soundTheme_treatsMixedElectronicTagsAsElectronic() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:A', 'artist', 'lastfm', 'latin', 'latin house', 33, 10),
          ('spotify:artist:A', 'artist', 'lastfm', 'rap', 'trap', 33, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:A")

    XCTAssertEqual(theme, .slime)
  }

  func test_soundTheme_usesFeaturedArtistsForCurrentTrackColor() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO artists (uri, name, genres_json, image_url)
        VALUES
          ('spotify:artist:primary', 'Primary Latin', NULL, NULL),
          ('spotify:artist:feature', 'Feature Techno', NULL, NULL)
      """)
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:primary', 'artist', 'lastfm', 'latin', 'latin', 100, 10),
          ('spotify:artist:feature', 'artist', 'lastfm', 'electronic', 'hard techno', 100, 10)
      """)
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUris: [
      "spotify:artist:primary",
      "spotify:artist:feature"
    ])

    XCTAssertEqual(theme, .slime)
  }

  func test_soundThemeDecisionExplainsFeaturedElectronicOverride() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO artists (uri, name, genres_json, image_url)
        VALUES
          ('spotify:artist:tnt', 'TNT', NULL, NULL),
          ('spotify:artist:technoboy', 'Technoboy', NULL, NULL),
          ('spotify:artist:tuneboy', 'Tuneboy', NULL, NULL)
      """)
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES
          ('spotify:artist:tnt', 'artist', 'lastfm', 'rock', 'hard rock', 100, 10),
          ('spotify:artist:tnt', 'artist', 'lastfm', 'metal', 'heavy metal', 80, 10),
          ('spotify:artist:tnt', 'artist', 'lastfm', 'electronic', 'hardstyle', 9, 10),
          ('spotify:artist:technoboy', 'artist', 'lastfm', 'electronic', 'hardstyle', 100, 10),
          ('spotify:artist:technoboy', 'artist', 'lastfm', 'electronic', 'techno', 80, 10),
          ('spotify:artist:tuneboy', 'artist', 'lastfm', 'electronic', 'hardstyle', 100, 10)
      """)
    }

    let decision = try StatsQueries(dbq: dbq).soundThemeDecision(
      forArtistUris: [
        "spotify:artist:tnt",
        "spotify:artist:technoboy",
        "spotify:artist:tuneboy"
      ],
      trackName: "Hard Beat",
      artistName: "TNT",
      albumName: "Hard Beat",
      allowRecentFallback: false)

    XCTAssertEqual(decision?.theme, .slime)
    XCTAssertEqual(decision?.source, .artistTags)
    XCTAssertTrue(decision?.reason.contains("Technoboy") == true)
  }

  func test_soundTheme_usesRecentSessionWhenCurrentArtistHasNoTags() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = Int64(Date().timeIntervalSince1970)

    try tracks.upsert(.init(
      uri: "spotify:track:current",
      name: "Current",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Unknown Hard Techno Artist","uri":"spotify:artist:unknown"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:recent",
      name: "Recent",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Tagged Techno Artist","uri":"spotify:artist:tagged"}]"#))

    try plays.insert(.init(playedAt: now - 10, trackUri: "spotify:track:current", msPlayed: 180_000, source: "live"))
    for idx in 1...4 {
      try plays.insert(.init(playedAt: now - Int64(idx * 120), trackUri: "spotify:track:recent", msPlayed: 180_000, source: "live"))
    }

    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:tagged', 'artist', 'lastfm', 'electronic', 'hard techno', 100, ?)
      """, arguments: [now])
    }

    let theme = try StatsQueries(dbq: dbq).soundTheme(forArtistUri: "spotify:artist:unknown")

    XCTAssertEqual(theme, .slime)
  }

  func test_directSoundThemeDoesNotUseRecentSessionFallback() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = Int64(Date().timeIntervalSince1970)

    try tracks.upsert(.init(
      uri: "spotify:track:current",
      name: "Current",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Unknown Artist","uri":"spotify:artist:unknown"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:recent",
      name: "Recent",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Tagged Indie Artist","uri":"spotify:artist:tagged"}]"#))

    try plays.insert(.init(playedAt: now - 10, trackUri: "spotify:track:current", msPlayed: 180_000, source: "live"))
    for idx in 1...4 {
      try plays.insert(.init(playedAt: now - Int64(idx * 120), trackUri: "spotify:track:recent", msPlayed: 180_000, source: "live"))
    }

    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:tagged', 'artist', 'lastfm', 'indie', 'indie', 100, ?)
      """, arguments: [now])
    }

    let queries = StatsQueries(dbq: dbq)

    XCTAssertEqual(try queries.soundTheme(forArtistUri: "spotify:artist:unknown"), .aqua)
    XCTAssertNil(try queries.directSoundTheme(forArtistUris: ["spotify:artist:unknown"]))
  }

  func test_soundThemeHintTreatsHardTechnoTrackMetadataAsElectronic() throws {
    let theme = StatsQueries.soundThemeHint(
      trackName: "Get Ready for This Hard Techno",
      artistName: "KX CHR",
      albumName: "")

    XCTAssertEqual(theme, .slime)
  }

  func test_soundThemeHintDoesNotTreatGarageRockAsElectronic() throws {
    let theme = StatsQueries.soundThemeHint(
      trackName: "Garage Rock Revival",
      artistName: "The Bravery",
      albumName: "Indie Rock Classics")

    XCTAssertNil(theme)
  }

  func test_soundThemeHintDefaultsLatinMetadataToSmokeGel() throws {
    let theme = StatsQueries.soundThemeHint(
      trackName: "NO TENGA$ MIEDO",
      artistName: "Junior H",
      albumName: "Corridos Tumbados")

    XCTAssertEqual(theme, .classic)
  }

  func test_soundThemeHintLetsSonicMetadataBeatLatinDefault() throws {
    let theme = StatsQueries.soundThemeHint(
      trackName: "Spanish Metal",
      artistName: "Demo",
      albumName: "Latin Metal")

    XCTAssertEqual(theme, .ember)
  }

  func test_soundThemeDecisionUsesTrackTextWhenArtistTagsAreMissing() throws {
    let decision = try StatsQueries(dbq: try InMemoryDatabase.make()).soundThemeDecision(
      forArtistUris: ["spotify:artist:missing"],
      trackName: "Get Ready for This Hard Techno",
      artistName: "KX CHR",
      albumName: "",
      allowRecentFallback: false)

    XCTAssertEqual(decision?.theme, .slime)
    XCTAssertEqual(decision?.source, .trackMetadata)
    XCTAssertTrue(decision?.reason.contains("hard techno") == true)
  }

  func test_weeklyMemoryBuildsLiveWrappedLayerFromEnrichedTags() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let priorWeek = localEpoch(year: 2024, month: 1, day: 10, hour: 12)
    let currentWeek = localEpoch(year: 2024, month: 1, day: 16, hour: 12)

    for idx in 0..<5 {
      let artistUri = "spotify:artist:\(idx)"
      let trackUri = "spotify:track:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "Track \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Artist \#(idx)","uri":"\#(artistUri)"}]"#))
      try dbq.write { db in
        try db.execute(sql: """
          INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
          VALUES (?, 'artist', 'lastfm', 'electronic', 'hard techno', 100, ?)
        """, arguments: [artistUri, now])
      }

      try plays.insert(.init(playedAt: priorWeek + Int64(idx), trackUri: trackUri, msPlayed: 180_000, source: "import"))
      try plays.insert(.init(playedAt: currentWeek + Int64(idx * 60), trackUri: trackUri, msPlayed: 180_000, source: "import"))
      try plays.insert(.init(playedAt: currentWeek + Int64(1_000 + idx * 60), trackUri: trackUri, msPlayed: 180_000, source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(now: now))

    XCTAssertEqual(memory.trait, "Pulsebound")
    XCTAssertEqual(memory.memento, "Signal Cube")
    XCTAssertEqual(memory.roomObjectName, "stereo")
    XCTAssertEqual(memory.theme, .slime)
    XCTAssertEqual(memory.playCount, 10)
    XCTAssertEqual(memory.newArtists, 0)

    try WeeklyMemoriesDAO(dbq: dbq, now: { now }).upsert(memory, now: now)
    let artifacts = try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()
    let signalCube = try XCTUnwrap(artifacts.first { $0.kind == .signalCube })
    XCTAssertEqual(signalCube.detail, "Signal Cube · Pulsebound · electronic")
  }

  func test_weeklyMemoryDoesNotUseStaticRoomArchitectureAsFeaturedObject() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let currentWeek = localEpoch(year: 2024, month: 1, day: 16, hour: 12)
    let artistUri = "spotify:artist:bright"

    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES (?, 'artist', 'lastfm', 'latin', 'latin pop', 100, ?)
      """, arguments: [artistUri, now])
    }

    for idx in 0..<3 {
      let trackUri = "spotify:track:bright:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "Bright Track \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Bright Artist","uri":"\#(artistUri)"}]"#))
      try plays.insert(.init(
        playedAt: currentWeek + Int64(idx * 60),
        trackUri: trackUri,
        msPlayed: 180_000,
        source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(now: now))

    XCTAssertEqual(memory.trait, "Bright")
    XCTAssertEqual(memory.memento, "Shelf Sticker")
    XCTAssertEqual(memory.roomObjectName, "mcm_hifi_console")
    XCTAssertNotEqual(memory.roomObjectName, "window")
    XCTAssertNotEqual(memory.roomObjectName, "rug")
  }

  func test_weeklyMemoryBuildsNocturnalTraitFromLateNightListening() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let lateNight = localEpoch(year: 2024, month: 1, day: 16, hour: 23)

    for idx in 0..<6 {
      let trackUri = "spotify:track:nocturnal:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "Late Track \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Night Artist \#(idx)","uri":"spotify:artist:night:\#(idx)"}]"#))
      try plays.insert(.init(
        playedAt: lateNight + Int64(idx * 60),
        trackUri: trackUri,
        msPlayed: 180_000,
        source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(now: now))

    XCTAssertEqual(memory.trait, "Nocturnal")
    XCTAssertEqual(memory.memento, "Moonlit Tape")
    XCTAssertEqual(memory.roomObjectName, "desk_lamp")
    XCTAssertTrue(memory.recapLine.contains("late-night plays"))
  }

  func test_weeklyMemoryBuildsLoyalTraitFromRepeatArtist() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let currentWeek = localEpoch(year: 2024, month: 1, day: 16, hour: 12)

    for idx in 0..<10 {
      let trackUri = "spotify:track:loyal:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "Loyal Track \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Repeat Signal","uri":"spotify:artist:repeat"}]"#))
      try plays.insert(.init(
        playedAt: currentWeek + Int64(idx * 90),
        trackUri: trackUri,
        msPlayed: 180_000,
        source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(now: now))

    XCTAssertEqual(memory.trait, "Loyal")
    XCTAssertEqual(memory.memento, "Repeat Charm")
    XCTAssertEqual(memory.roomObjectName, "record_cube")
    XCTAssertTrue(memory.recapLine.contains("Repeat Signal"))
  }

  func test_weeklyMemoryBuildsCuriousTraitFromNewArtists() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let currentWeek = localEpoch(year: 2024, month: 1, day: 16, hour: 12)

    for idx in 0..<12 {
      let trackUri = "spotify:track:curious:\(idx)"
      let artistUri = "spotify:artist:curious:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "New Signal \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"New Artist \#(idx)","uri":"\#(artistUri)"}]"#))
      try plays.insert(.init(
        playedAt: currentWeek + Int64(idx * 90),
        trackUri: trackUri,
        msPlayed: 180_000,
        source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(now: now))

    XCTAssertEqual(memory.trait, "Curious")
    XCTAssertEqual(memory.memento, "Fresh Sticker")
    XCTAssertEqual(memory.roomObjectName, "plant")
    XCTAssertEqual(memory.newArtists, 12)
  }

  func test_weeklyMemoryCanBeGeneratedForHistoricalWeekWithoutFutureBleed() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let weekStart = localEpoch(year: 2024, month: 1, day: 8, hour: 0)
    let weekEnd = localEpoch(year: 2024, month: 1, day: 15, hour: 0)
    let nextWeek = localEpoch(year: 2024, month: 1, day: 16, hour: 12)

    try tracks.upsert(.init(
      uri: "spotify:track:bounded",
      name: "Bounded",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Week One","uri":"spotify:artist:week-one"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:future",
      name: "Future",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Week Two","uri":"spotify:artist:week-two"}]"#))

    for idx in 0..<3 {
      try plays.insert(.init(
        playedAt: weekStart + 86_400 + Int64(idx * 60),
        trackUri: "spotify:track:bounded",
        msPlayed: 180_000,
        source: "import"))
    }
    for idx in 0..<10 {
      try plays.insert(.init(
        playedAt: nextWeek + Int64(idx * 60),
        trackUri: "spotify:track:future",
        msPlayed: 180_000,
        source: "import"))
    }

    let memory = try XCTUnwrap(StatsQueries(dbq: dbq).weeklyMemory(weekStart: weekStart, weekEnd: weekEnd))

    XCTAssertEqual(memory.playCount, 3)
    XCTAssertFalse(memory.recapLine.contains("Week Two"))
  }

  func test_weeklyMemoriesPersistAndUnlockMementoArtifacts() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let now = localEpoch(year: 2024, month: 1, day: 17, hour: 12)
    let lateNight = localEpoch(year: 2024, month: 1, day: 16, hour: 23)

    for idx in 0..<6 {
      let trackUri = "spotify:track:weekly-persist:\(idx)"
      try tracks.upsert(.init(
        uri: trackUri,
        name: "Saved Week \(idx)",
        albumName: nil,
        albumArtUrl: nil,
        durationMs: nil,
        artistsJson: #"[{"name":"Memory Artist \#(idx)","uri":"spotify:artist:memory:\#(idx)"}]"#))
      try plays.insert(.init(
        playedAt: lateNight + Int64(idx * 60),
        trackUri: trackUri,
        msPlayed: 180_000,
        source: "import"))
    }

    let memories = try WeeklyMemoriesDAO(dbq: dbq, now: { now }).ensureRecentWeeks(limit: 2)
    let artifacts = try ArtifactsDAO(dbq: dbq).all()

    XCTAssertEqual(memories.first?.memento, "Moonlit Tape")
    XCTAssertEqual(memories.first?.trait, "Nocturnal")
    XCTAssertTrue(artifacts.contains { $0.kind == .moonlitTape && $0.source == .weeklyMemory })
  }

  func test_enrichmentProgressIncludesArtistProgress() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)
    let artists = ArtistsDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:A1",
      name: "A1",
      albumName: nil,
      albumArtUrl: "https://art/a.jpg",
      durationMs: nil,
      artistsJson: #"[{"name":"Artist A","uri":"spotify:artist:A"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:B1",
      name: "B1",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Artist B","uri":"spotify:artist:B"}]"#))
    try artists.upsert(.init(
      uri: "spotify:artist:A",
      name: "Artist A",
      genresJson: #"[]"#,
      imageUrl: nil))
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO tag_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
        VALUES ('spotify:artist:A', 'artist', 'lastfm', 'success', 10, NULL)
      """)
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES ('spotify:artist:A', 'artist', 'lastfm', 'rap', 'hip hop', 100, 10)
      """)
    }

    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:A1", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:B1", msPlayed: 180_000, source: "import"))

    let progress = try StatsQueries(dbq: dbq).enrichmentProgress()

    XCTAssertEqual(progress.total, 2)
    XCTAssertEqual(progress.enriched, 1)
    XCTAssertEqual(progress.trackArtistResolved, 2)
    XCTAssertEqual(progress.trackArtistDirect, 2)
    XCTAssertEqual(progress.trackArtistAliased, 0)
    XCTAssertEqual(progress.artistIdentityAliases, 0)
    XCTAssertEqual(progress.artistTotal, 2)
    XCTAssertEqual(progress.artistEnriched, 0)
    XCTAssertEqual(progress.tagArtistTotal, 2)
    XCTAssertEqual(progress.tagArtistChecked, 1)
    XCTAssertEqual(progress.tagArtistTagged, 1)
  }

  func test_enrichmentProgressCountsIdentityAliasesAsResolved() throws {
    let dbq = try InMemoryDatabase.make()
    let plays = PlaysDAO(dbq: dbq)
    let tracks = TracksDAO(dbq: dbq)

    try tracks.upsert(.init(
      uri: "spotify:track:imported",
      name: "Imported",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"artist:Junior_H"}]"#))
    try tracks.upsert(.init(
      uri: "spotify:track:canonical",
      name: "Canonical",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: #"[{"name":"Junior H","uri":"spotify:artist:juniorh"}]"#))
    try dbq.write { db in
      try ArtistIdentityRepair.rebuildAliases(in: db, now: 100)
    }
    try plays.insert(.init(playedAt: 1, trackUri: "spotify:track:imported", msPlayed: 180_000, source: "import"))
    try plays.insert(.init(playedAt: 2, trackUri: "spotify:track:canonical", msPlayed: 180_000, source: "live"))

    let progress = try StatsQueries(dbq: dbq).enrichmentProgress()

    XCTAssertEqual(progress.total, 2)
    XCTAssertEqual(progress.trackArtistResolved, 2)
    XCTAssertEqual(progress.trackArtistDirect, 1)
    XCTAssertEqual(progress.trackArtistAliased, 1)
    XCTAssertEqual(progress.artistIdentityAliases, 1)
  }

  func test_recentPlaySyncHealthSurfacesCatchUpState() throws {
    let dbq = try InMemoryDatabase.make()
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO recent_play_sync_state (
          id,
          last_played_at_ms,
          last_synced_at,
          last_response_count,
          last_response_saturated,
          consecutive_saturated,
          last_inserted_count
        )
        VALUES (1, 1700000100123, 1700000200, 50, 1, 2, 17)
        """)
    }

    let health = try StatsQueries(dbq: dbq).recentPlaySyncHealth()

    XCTAssertEqual(health?.lastPlayedAtMs, 1_700_000_100_123)
    XCTAssertEqual(health?.lastSyncedAt, 1_700_000_200)
    XCTAssertEqual(health?.lastResponseCount, 50)
    XCTAssertEqual(health?.lastResponseSaturated, true)
    XCTAssertEqual(health?.consecutiveSaturated, 2)
    XCTAssertEqual(health?.lastInsertedCount, 17)
  }

  func test_enrichmentQueueHealthSurfacesRetryAndStaleBacklog() throws {
    let dbq = try InMemoryDatabase.make()
    let now: Int64 = 1_800_000_000
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO metadata_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
        VALUES
          ('spotify:track:stale', 'track', 'spotify', 'success', ?, NULL),
          ('spotify:artist:fresh', 'artist', 'spotify', 'success', ?, NULL),
          ('spotify:track:failed', 'track', 'spotify', 'failed', ?, 'server'),
          ('spotify:track:partial', 'track', 'spotify', 'partial', ?, 'missing artist'),
          ('spotify:artist:limited', 'artist', 'spotify', 'limited', ?, '429')
      """, arguments: [
        now - 91 * 86_400,
        now - 10 * 86_400,
        now - 2 * 86_400,
        now - 600,
        now - 1_800
      ])
      try db.execute(sql: """
        INSERT INTO tag_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
        VALUES
          ('spotify:artist:tag-failed', 'artist', 'lastfm', 'failed', ?, 'server'),
          ('spotify:artist:tag-limited', 'artist', 'lastfm', 'limited', ?, '429'),
          ('spotify:artist:tag-empty', 'artist', 'lastfm', 'empty', ?, NULL)
      """, arguments: [
        now - 2 * 86_400,
        now - 600,
        now - 1_000
      ])
    }

    let health = try StatsQueries(dbq: dbq).enrichmentQueueHealth(now: now)

    XCTAssertEqual(health.metadataFailed, 1)
    XCTAssertEqual(health.metadataLimited, 1)
    XCTAssertEqual(health.metadataPartial, 1)
    XCTAssertEqual(health.metadataRetryReady, 2)
    XCTAssertEqual(health.tagFailed, 1)
    XCTAssertEqual(health.tagLimited, 1)
    XCTAssertEqual(health.tagEmpty, 1)
    XCTAssertEqual(health.tagRetryReady, 1)
    XCTAssertEqual(health.retryReadyTotal, 3)
    XCTAssertEqual(health.staleTrackMetadata, 1)
    XCTAssertEqual(health.staleArtistMetadata, 0)
  }

  func test_statsSnapshotCarriesCurrentWeeklyMemoryForStatsSurface() async throws {
    let dbq = try InMemoryDatabase.make()
    let now = Int64(Date().timeIntervalSince1970)
    let bounds = StatsQueries.weekBounds(containing: now)
    let memory = StatsQueries.WeeklyMemorySnapshot(
      weekStart: bounds.start,
      weekEnd: bounds.end,
      trait: "Pulsebound",
      memento: "Signal Cube",
      recapLine: "The week leaned into electronic pressure.",
      roomObjectName: "stereo",
      dominantGenre: "electronic",
      theme: .slime,
      playCount: 12,
      listeningMs: 2_160_000,
      uniqueArtists: 4,
      newArtists: 1)
    try WeeklyMemoriesDAO(dbq: dbq, now: { now }).upsert(memory, now: now)

    let snapshot = await StatsViewSnapshot.load(dbq: dbq, range: .ytd)

    XCTAssertEqual(snapshot.weeklyMemory?.trait, "Pulsebound")
    XCTAssertEqual(snapshot.weeklyMemory?.memento, "Signal Cube")
    XCTAssertEqual(snapshot.weeklyMemory?.dominantGenre, "electronic")
    XCTAssertEqual(snapshot.weeklyMemory?.roomObjectName, "stereo")
  }

  private func insertPlays(
    _ plays: PlaysDAO,
    count: Int,
    startingAt epoch: Int64,
    track: String
  ) throws {
    for idx in 0..<count {
      try plays.insert(.init(
        playedAt: epoch + Int64(idx),
        trackUri: "\(track):\(idx)",
        msPlayed: 180_000,
        source: "import"))
    }
  }

  private func localEpoch(year: Int, month: Int, day: Int, hour: Int) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(
      year: year,
      month: month,
      day: day,
      hour: hour))!
    return Int64(date.timeIntervalSince1970)
  }
}
