// Dial/Aggregations/StatsQueries.swift
import GRDB
import Foundation

/// Queries that power the History and Stats windows. All read-only.
struct StatsQueries {
  let dbq: DatabaseQueue

  // MARK: - History

  struct HistoryRow: Identifiable, Hashable {
    let id: Int64                  // play row id
    let playedAt: Int64
    let trackUri: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let albumArtUrl: String?
  }

  /// Most-recent plays first. Joins `plays` with `tracks` (left join — plays
  /// without metadata still surface, just with empty strings).
  ///
  /// Default cap of 200 is intentional: HistoryView is a "what did I just
  /// listen to" feed, not an archive browser. The full history stays in the
  /// DB (where Stats aggregates against it) — there's just no need to scroll
  /// through 193k rows in a popover that's 320pt wide.
  ///
  /// Defensive `json_valid` guard: some `artists_json` rows in the DB have
  /// malformed JSON (e.g. unescaped backslashes from imported Spotify
  /// extended-history rows like `"artist:Axwell_/\_Ingrosso"`). Without
  /// this guard, hitting one of those rows during the join causes SQLite
  /// to throw "malformed JSON" and the whole query fails — so the view
  /// silently shows empty data via `try?`. Wrapping in CASE returns NULL
  /// (handled downstream) instead of crashing the query.
  func recentPlays(limit: Int = 200) throws -> [HistoryRow] {
    try dbq.read { db in
      return try Row.fetchAll(db, sql: """
        SELECT p.id, p.played_at, p.track_uri,
               COALESCE(t.name, '') AS name,
               COALESCE(
                 CASE WHEN json_valid(t.artists_json) = 1
                      THEN json_extract(t.artists_json, '$[0].name')
                      ELSE NULL END,
                 ''
               ) AS artist,
               t.album_name, t.album_art_url
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        ORDER BY p.played_at DESC
        LIMIT ?
      """, arguments: [limit]).map { row in
        HistoryRow(
          id: row["id"],
          playedAt: row["played_at"],
          trackUri: row["track_uri"],
          trackName: row["name"],
          artistName: row["artist"],
          albumName: row["album_name"],
          albumArtUrl: row["album_art_url"])
      }
    }
  }

  // MARK: - Top tracks / artists

  struct TopRow: Identifiable, Hashable {
    let uri: String
    let name: String
    let count: Int
    let artUrl: String?     // only populated by topTracks; nil for topArtists
    let subtitle: String?   // artist name for tracks; nil for artists
    var id: String { uri }
  }

  func topTracks(limit: Int = 10, since: Int64? = nil, until: Int64? = nil) throws -> [TopRow] {
    try dbq.read { db in
      var filters: [String] = []
      var arguments: [Int64] = []
      if let since {
        filters.append("p.played_at >= ?")
        arguments.append(since)
      }
      if let until {
        filters.append("p.played_at < ?")
        arguments.append(until)
      }
      let filter = filters.isEmpty ? "" : "WHERE \(filters.joined(separator: " AND "))"
      arguments.append(Int64(limit))
      return try Row.fetchAll(db, sql: """
        SELECT p.track_uri AS uri,
               COALESCE(t.name, p.track_uri) AS name,
               t.album_art_url AS art_url,
               CASE WHEN json_valid(t.artists_json) = 1
                    THEN json_extract(t.artists_json, '$[0].name')
                    ELSE NULL END AS artist_name,
               COUNT(*) AS c
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        \(filter)
        GROUP BY p.track_uri
        ORDER BY c DESC, MAX(p.played_at) DESC
        LIMIT ?
      """, arguments: StatementArguments(arguments)).map { row in
        TopRow(
          uri: row["uri"], name: row["name"], count: row["c"],
          artUrl: row["art_url"], subtitle: row["artist_name"]
        )
      }
    }
  }

  // MARK: - Genres

  struct GenreRow: Identifiable, Hashable {
    let genre: String
    let playCount: Int
    let artistCount: Int
    let detailTags: [String]
    let theme: DialThemeID?
    var id: String { genre }
  }

  struct WeeklyMemorySnapshot: Equatable {
    let weekStart: Int64
    let weekEnd: Int64
    let trait: String
    let memento: String
    let recapLine: String
    let roomObjectName: String
    let dominantGenre: String?
    let theme: DialThemeID
    let playCount: Int
    let listeningMs: Int64
    let uniqueArtists: Int
    let newArtists: Int
  }

  /// Top artist-derived sound signals for the selected range. Dial prefers
  /// normalized tags from external providers (currently Last.fm), then falls
  /// back to Spotify's deprecated artist genres when they exist.
  ///
  /// A play can contribute to multiple family buckets when its primary artist
  /// has several tags. That's intentional: this powers "sound weather," not
  /// exact accounting.
  func topGenres(limit: Int = 8, since: Int64? = nil, until: Int64? = nil) throws -> [GenreRow] {
    try dbq.read { db in
      var rangeFilters: [String] = []
      var arguments: [Int64] = []
      if let since {
        rangeFilters.append("AND p.played_at >= ?")
        arguments.append(since)
      }
      if let until {
        rangeFilters.append("AND p.played_at < ?")
        arguments.append(until)
      }
      arguments.append(Int64(limit))
      return try Row.fetchAll(db, sql: """
        WITH normalized_artist_families AS (
          SELECT nt.entity_uri AS artist_uri,
                 LOWER(TRIM(nt.family)) AS genre,
                 GROUP_CONCAT(DISTINCT nt.raw_tag) AS detail_tags,
                 MAX(nt.score) AS score
          FROM normalized_tags nt
          WHERE nt.entity_type = 'artist'
            AND nt.family IS NOT NULL
            AND TRIM(nt.family) <> ''
          GROUP BY nt.entity_uri, LOWER(TRIM(nt.family))
        ),
        spotify_artist_genres AS (
          SELECT a.uri AS artist_uri,
                 LOWER(TRIM(j.value)) AS genre,
                 LOWER(TRIM(j.value)) AS detail_tags,
                 0 AS score
          FROM artists a, json_each(a.genres_json) j
          WHERE a.genres_json IS NOT NULL
            AND json_valid(a.genres_json) = 1
            AND TRIM(j.value) <> ''
        ),
        artist_genres AS (
          SELECT artist_uri, genre, detail_tags, score
          FROM normalized_artist_families
          UNION ALL
          SELECT sag.artist_uri, sag.genre, sag.detail_tags, sag.score
          FROM spotify_artist_genres sag
          WHERE NOT EXISTS (
            SELECT 1
            FROM normalized_artist_families naf
            WHERE naf.artist_uri = sag.artist_uri
          )
        ),
        primary_artists AS (
          SELECT t.uri AS track_uri,
                 COALESCE(alias.canonical_uri, json_extract(t.artists_json, '$[0].uri')) AS artist_uri
          FROM tracks t
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                       THEN json_extract(t.artists_json, '$[0].uri')
                                       ELSE NULL END
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
        )
        SELECT ag.genre AS genre,
               COUNT(*) AS plays,
               COUNT(DISTINCT ag.artist_uri) AS artists,
               GROUP_CONCAT(DISTINCT ag.detail_tags) AS detail_tags
        FROM plays p
        JOIN primary_artists pa ON pa.track_uri = p.track_uri
        JOIN artist_genres ag ON ag.artist_uri = pa.artist_uri
        WHERE 1 = 1
          \(rangeFilters.joined(separator: "\n          "))
        GROUP BY ag.genre
        ORDER BY plays DESC, artists DESC, genre ASC
        LIMIT ?
      """, arguments: StatementArguments(arguments)).map { row in
        let genre: String = row["genre"]
        let detailTags = Self.splitTags(row["detail_tags"])
        return GenreRow(
          genre: genre,
          playCount: row["plays"],
          artistCount: row["artists"],
          detailTags: detailTags,
          theme: SoundThemeResolver.theme(forRawTags: detailTags, fallbackFamily: genre))
      }
    }
  }

  /// Resolves the current artist into one of the brand mockup shell themes.
  /// This is intentionally coarse: Dial should feel like the device changed
  /// cartridges, not like every microgenre got its own random color.
  func soundTheme(forArtistUri artistUri: String?) throws -> DialThemeID {
    guard let artistUri, !artistUri.isEmpty else { return .classic }
    return try soundTheme(forArtistUris: [artistUri])
  }

  func soundTheme(forArtistUris artistUris: [String]) throws -> DialThemeID {
    try soundThemeDecision(forArtistUris: artistUris, allowRecentFallback: true)?.theme ?? .classic
  }

  func directSoundTheme(forArtistUris artistUris: [String]) throws -> DialThemeID? {
    try soundThemeDecision(forArtistUris: artistUris, allowRecentFallback: false)?.theme
  }

  func soundThemeDecision(
    forArtistUris artistUris: [String],
    trackName: String? = nil,
    artistName: String? = nil,
    albumName: String? = nil,
    allowRecentFallback: Bool = true
  ) throws -> SoundThemeDecision? {
    try SoundThemeResolver(dbq: dbq).decision(
      forArtistUris: artistUris,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      allowRecentFallback: allowRecentFallback)
  }

  static func soundThemeHint(trackName: String, artistName: String, albumName: String) -> DialThemeID? {
    SoundThemeResolver.metadataDecision(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName)?.theme
  }

  // MARK: - Weekly Memory

  /// A lightweight "Wrapped, but alive" read: one trait, one memento, one
  /// room object, and one recap line for the current listening week.
  func weeklyMemory(now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> WeeklyMemorySnapshot? {
    let bounds = Self.weekBounds(containing: now)
    return try weeklyMemory(weekStart: bounds.start, weekEnd: bounds.end)
  }

  func weeklyMemory(weekStart: Int64, weekEnd: Int64) throws -> WeeklyMemorySnapshot? {
    let totals = try totals(since: weekStart, until: weekEnd)
    guard totals.plays > 0 else { return nil }

    let genres = try topGenres(limit: 3, since: weekStart, until: weekEnd)
    let dominantGenre = genres.first?.genre
    let family = dominantGenre.flatMap { DialTagNormalizer.normalize($0)?.family } ?? dominantGenre
    let lateNightPlays = try countLateNightPlays(since: weekStart, until: weekEnd)
    let topTrack = try topTracks(limit: 1, since: weekStart, until: weekEnd).first
    let topArtist = try topArtists(limit: 1, since: weekStart, until: weekEnd).first
    let newArtists = try countNewArtists(since: weekStart, until: weekEnd)

    let weeklyTheme = SoundThemeResolver.theme(
      forRawTags: genres.first?.detailTags ?? [],
      fallbackFamily: family) ?? .classic

    let blueprint = Self.weeklyBlueprint(
      family: family,
      theme: weeklyTheme,
      plays: totals.plays,
      listeningMs: totals.listeningMs,
      uniqueArtists: totals.uniqueArtists,
      lateNightPlays: lateNightPlays,
      newArtists: newArtists,
      topTrack: topTrack,
      topArtist: topArtist)

    return WeeklyMemorySnapshot(
      weekStart: weekStart,
      weekEnd: weekEnd,
      trait: blueprint.trait,
      memento: blueprint.memento,
      recapLine: blueprint.recap,
      roomObjectName: blueprint.roomObjectName,
      dominantGenre: dominantGenre,
      theme: weeklyTheme,
      playCount: totals.plays,
      listeningMs: totals.listeningMs,
      uniqueArtists: totals.uniqueArtists,
      newArtists: newArtists)
  }

  private static func splitTags(_ value: String?) -> [String] {
    guard let value else { return [] }
    return value
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func countLateNightPlays(since: Int64, until: Int64? = nil) throws -> Int {
    try dbq.read { db in
      let untilFilter = until == nil ? "" : "AND played_at < ?"
      var arguments = [since]
      if let until { arguments.append(until) }
      return try Int.fetchOne(db, sql: """
        SELECT COUNT(*)
        FROM plays
        WHERE played_at >= ?
          \(untilFilter)
          AND (
            CAST(strftime('%H', played_at, 'unixepoch', 'localtime') AS INTEGER) >= 22
            OR CAST(strftime('%H', played_at, 'unixepoch', 'localtime') AS INTEGER) <= 4
          )
      """, arguments: StatementArguments(arguments)) ?? 0
    }
  }

  private func countNewArtists(since: Int64, until: Int64? = nil) throws -> Int {
    try dbq.read { db in
      let untilFilter = until == nil ? "" : "AND first_seen < ?"
      var arguments = [since]
      if let until { arguments.append(until) }
      return try Int.fetchOne(db, sql: """
        WITH artist_first AS (
          SELECT COALESCE(
                   NULLIF(LOWER(TRIM(alias.canonical_uri)), ''),
                   CASE WHEN json_extract(t.artists_json, '$[0].uri') LIKE 'spotify:artist:%'
                        THEN NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].uri'))), '')
                        ELSE NULL END,
                   NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), ''),
                   json_extract(t.artists_json, '$[0].uri')
                 ) AS artist_key,
                 MIN(p.played_at) AS first_seen
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                       THEN json_extract(t.artists_json, '$[0].uri')
                                       ELSE NULL END
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_key
        )
        SELECT COUNT(*)
        FROM artist_first
        WHERE first_seen >= ?
          \(untilFilter)
      """, arguments: StatementArguments(arguments)) ?? 0
    }
  }

  static func weekBounds(containing epoch: Int64) -> (start: Int64, end: Int64) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    calendar.firstWeekday = 2
    let date = Date(timeIntervalSince1970: TimeInterval(epoch))
    let interval = calendar.dateInterval(of: .weekOfYear, for: date)
    let start = interval?.start ?? calendar.startOfDay(for: date)
    let end = interval?.end ?? calendar.date(byAdding: .day, value: 7, to: start) ?? date
    return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970))
  }

  private static func weeklyBlueprint(
    family: String?,
    theme: DialThemeID,
    plays: Int,
    listeningMs: Int64,
    uniqueArtists: Int,
    lateNightPlays: Int,
    newArtists: Int,
    topTrack: TopRow?,
    topArtist: TopRow?
  ) -> (trait: String, memento: String, recap: String, roomObjectName: String) {
    let lateShare = plays > 0 ? Double(lateNightPlays) / Double(plays) : 0
    let artistShare = plays > 0 ? Double(topArtist?.count ?? 0) / Double(plays) : 0
    let hours = max(1, Int((Double(listeningMs) / 3_600_000.0).rounded()))

    if plays >= 6, lateShare >= 0.34 {
      return (
        "Nocturnal",
        "Moonlit Tape",
        "\(lateNightPlays) late-night plays made the room glow after dark.",
        "desk_lamp")
    }

    if theme == .slime {
      return (
        "Pulsebound",
        "Signal Cube",
        "The week leaned into \(family ?? "electronic") pressure.",
        "stereo")
    }

    if plays >= 8, artistShare >= 0.32 || (topTrack?.count ?? 0) >= max(5, Int((Double(plays) * 0.24).rounded())) {
      let name = topArtist?.name ?? topTrack?.subtitle ?? "one signal"
      return (
        "Loyal",
        "Repeat Charm",
        "\(name) kept orbiting this week.",
        "record_cube")
    }

    if newArtists >= max(4, Int((Double(max(1, uniqueArtists)) * 0.34).rounded())) {
      return (
        "Curious",
        "Fresh Sticker",
        "\(newArtists) artists entered your history this week.",
        "plant")
    }

    switch family {
    case "ambient", "acoustic", "r&b", "jazz":
      return (
        "Tender",
        "Soft Lamp",
        "\(hours)h of softer listening tuned the room down.",
        "cone_floor_lamp")
    case "metal", "punk/emo", "rap", "reggaeton", "corridos":
      return (
        "Charged",
        "Blown Speaker",
        "High-pressure tracks left a louder object behind.",
        "speaker")
    case "indie", "pop", "rock", "latin", "electronic", "experimental", "soundtrack":
      return (
        "Bright",
        "Shelf Sticker",
        "\(uniqueArtists) artists kept the room moving.",
        "mcm_hifi_console")
    default:
      return (
        "Steady",
        "Listening Crate",
        "\(plays) plays became this week's floor texture.",
        "record_cube")
    }
  }

  /// Top artists by play count. Collapses imported synthetic artist IDs and
  /// later Spotify IDs by normalized display name so rankings never show the
  /// same artist twice.
  func topArtists(limit: Int = 10, since: Int64? = nil, until: Int64? = nil) throws -> [TopRow] {
    try dbq.read { db in
      var rangeFilters: [String] = []
      var arguments: [Int64] = []
      if let since {
        rangeFilters.append("AND p.played_at >= ?")
        arguments.append(since)
      }
      if let until {
        rangeFilters.append("AND p.played_at < ?")
        arguments.append(until)
      }
      arguments.append(Int64(limit))
      return try Row.fetchAll(db, sql: """
        WITH normalized AS (
          SELECT
            COALESCE(
              NULLIF(alias.canonical_uri, ''),
              NULLIF(TRIM(json_extract(t.artists_json, '$[0].uri')), '')
            ) AS artist_uri,
            COALESCE(
              NULLIF(alias.canonical_name, ''),
              NULLIF(TRIM(json_extract(t.artists_json, '$[0].name')), '')
            ) AS artist_name,
            COALESCE(
              NULLIF(LOWER(TRIM(alias.canonical_name)), ''),
              NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), ''),
              NULLIF(LOWER(TRIM(alias.canonical_uri)), ''),
              NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].uri'))), ''),
              'unknown'
            ) AS artist_key,
            p.played_at
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                       THEN json_extract(t.artists_json, '$[0].uri')
                                       ELSE NULL END
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
            \(rangeFilters.joined(separator: "\n            "))
        )
        SELECT
          COALESCE(
            MIN(CASE WHEN artist_uri LIKE 'spotify:artist:%' THEN artist_uri END),
            MIN(NULLIF(artist_uri, '')),
            'artist-name:' || artist_key
          ) AS artist_uri,
          COALESCE(
            MIN(CASE WHEN artist_uri LIKE 'spotify:artist:%' THEN artist_name END),
            MIN(artist_name),
            MIN(NULLIF(artist_uri, '')),
            'Unknown'
          ) AS name,
          COUNT(*) AS play_count
        FROM normalized
        WHERE artist_name IS NOT NULL OR artist_uri IS NOT NULL
        GROUP BY artist_key
        ORDER BY play_count DESC, MAX(played_at) DESC, name ASC
        LIMIT ?
      """, arguments: StatementArguments(arguments)).map { row in
        TopRow(uri: row["artist_uri"] ?? "", name: row["name"] ?? "Unknown", count: row["play_count"],
               artUrl: nil, subtitle: nil)
      }
    }
  }

  // MARK: - Totals

  struct Totals {
    let plays: Int
    let listeningMs: Int64
    let uniqueTracks: Int
    let uniqueArtists: Int
  }

  func totals(since: Int64? = nil, until: Int64? = nil) throws -> Totals {
    try dbq.read { db in
      var playFilters: [String] = []
      var artistFilters: [String] = []
      var arguments: [Int64] = []
      if let since {
        playFilters.append("played_at >= ?")
        artistFilters.append("AND p.played_at >= ?")
        arguments.append(since)
      }
      if let until {
        playFilters.append("played_at < ?")
        artistFilters.append("AND p.played_at < ?")
        arguments.append(until)
      }
      let playsFilter = playFilters.isEmpty ? "" : "WHERE \(playFilters.joined(separator: " AND "))"
      let artistRangeFilter = artistFilters.joined(separator: "\n          ")
      let statementArguments = StatementArguments(arguments)
      // One scan of `plays` for the three play-derived metrics — was three
      // separate scans, which at 193k rows is 3× the work for no reason.
      // COUNT, SUM, and COUNT(DISTINCT) all share the same row stream and
      // SQLite handles them in a single pass when issued together.
      let row = try Row.fetchOne(db, sql: """
        SELECT COUNT(*) AS plays,
               COALESCE(SUM(ms_played), 0) AS total_ms,
               COUNT(DISTINCT track_uri) AS uniq_tracks
        FROM plays
        \(playsFilter)
      """, arguments: statementArguments)
      // Artists live in a different table, so this stays as a separate
      // query. Filter to rows with VALID `artists_json` — some imported
      // rows have malformed JSON (unescaped backslashes in URIs) which
      // makes `json_extract` throw "malformed JSON" mid-query. Before
      // the `json_valid` guard, ONE bad row would crash the whole
      // `totals()` call and the view's `try?` would silently fall back
      // to all zeros — making Stats look completely broken to the user.
      let artists = try Int.fetchOne(db, sql: """
        WITH primary_artists AS (
          SELECT COALESCE(
                   NULLIF(alias.canonical_uri, ''),
                   NULLIF(TRIM(json_extract(t.artists_json, '$[0].uri')), '')
                 ) AS artist_uri,
                 p.played_at
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                       THEN json_extract(t.artists_json, '$[0].uri')
                                       ELSE NULL END
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
            \(artistRangeFilter)
        )
        SELECT COUNT(DISTINCT artist_uri)
        FROM primary_artists
        WHERE artist_uri IS NOT NULL
      """, arguments: statementArguments) ?? 0
      return Totals(
        plays: row?["plays"] ?? 0,
        listeningMs: row?["total_ms"] ?? 0,
        uniqueTracks: row?["uniq_tracks"] ?? 0,
        uniqueArtists: artists)
    }
  }

  // MARK: - Rhythm

  struct RhythmBucket: Identifiable, Hashable {
    let index: Int
    let label: String
    let count: Int
    let occurrences: Int
    let value: Double
    var id: Int { index }
  }

  func weekdayRhythm(
    since: Int64? = nil,
    now: Int64 = Int64(Date().timeIntervalSince1970)
  ) throws -> [RhythmBucket] {
    try dbq.read { db in
      let filter = since == nil ? "" : "WHERE played_at >= ?"
      let arguments = since.map { StatementArguments([$0]) } ?? StatementArguments()
      let rows = try Row.fetchAll(db, sql: """
        SELECT CAST(strftime('%w', played_at, 'unixepoch', 'localtime') AS INTEGER) AS dow,
               COUNT(*) AS c
        FROM plays
        \(filter)
        GROUP BY dow
      """, arguments: arguments)
      let counts = Dictionary(uniqueKeysWithValues: rows.map { row -> (Int, Int) in
        let day: Int = row["dow"]
        let count: Int = row["c"]
        return (day, count)
      })
      let firstPlay = try Int64.fetchOne(db, sql: "SELECT MIN(played_at) FROM plays")
      let start = since ?? firstPlay ?? now
      let occurrences = Self.weekdayOccurrences(from: min(start, now), through: now)
      let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
      let sqliteDays = [1, 2, 3, 4, 5, 6, 0]
      return labels.enumerated().map { idx, label in
        let dow = sqliteDays[idx]
        let count = counts[dow, default: 0]
        let occurrenceCount = max(1, occurrences[dow, default: 1])
        return RhythmBucket(
          index: idx,
          label: label,
          count: count,
          occurrences: occurrenceCount,
          value: Double(count) / Double(occurrenceCount))
      }
    }
  }

  func recentDailyRhythm(
    days: Int = 7,
    now: Int64 = Int64(Date().timeIntervalSince1970)
  ) throws -> [RhythmBucket] {
    let clampedDays = max(1, days)
    let endDate = Date(timeIntervalSince1970: TimeInterval(now))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let endDay = calendar.startOfDay(for: endDate)
    let startDay = calendar.date(byAdding: .day, value: -(clampedDays - 1), to: endDay) ?? endDay
    let startEpoch = Int64(startDay.timeIntervalSince1970)

    return try dbq.read { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT strftime('%Y-%m-%d', played_at, 'unixepoch', 'localtime') AS day,
               COUNT(*) AS c
        FROM plays
        WHERE played_at >= ? AND played_at <= ?
        GROUP BY day
      """, arguments: [startEpoch, now])
      let counts = Dictionary(uniqueKeysWithValues: rows.map { row -> (String, Int) in
        let day: String = row["day"]
        let count: Int = row["c"]
        return (day, count)
      })

      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "EEE"

      return (0..<clampedDays).map { offset in
        let date = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
        let key = Self.localDayKey(for: date, calendar: calendar)
        let count = counts[key, default: 0]
        let isToday = calendar.isDate(date, inSameDayAs: endDate)
        let label = isToday ? "TODAY" : formatter.string(from: date).uppercased()
        return RhythmBucket(
          index: offset,
          label: label,
          count: count,
          occurrences: 1,
          value: Double(count))
      }
    }
  }

  private static func weekdayOccurrences(from startEpoch: Int64, through endEpoch: Int64) -> [Int: Int] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    var cursor = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(startEpoch)))
    let endDay = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(endEpoch)))
    var counts: [Int: Int] = [:]

    while cursor <= endDay {
      // SQLite's %w uses Sunday = 0. Calendar uses Sunday = 1, Monday = 2.
      let sqliteDow = (calendar.component(.weekday, from: cursor) + 6) % 7
      counts[sqliteDow, default: 0] += 1
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return counts
  }

  private static func localDayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0)
  }

  // MARK: - Enrichment progress

  struct EnrichmentProgress: Equatable {
    let total: Int     // distinct spotify track URIs seen in plays
    let enriched: Int  // those with album_art_url populated in tracks
    let trackArtistResolved: Int
    let trackArtistDirect: Int
    let trackArtistAliased: Int
    let artistIdentityAliases: Int
    let artistTotal: Int
    let artistEnriched: Int
    let tagArtistTotal: Int
    let tagArtistChecked: Int
    let tagArtistTagged: Int
  }

  struct RecentPlaySyncHealth: Equatable {
    let lastPlayedAtMs: Int64
    let lastSyncedAt: Int64
    let lastResponseCount: Int
    let lastResponseSaturated: Bool
    let consecutiveSaturated: Int
    let lastInsertedCount: Int
  }

  struct EnrichmentQueueHealth: Equatable {
    let metadataFailed: Int
    let metadataLimited: Int
    let metadataPartial: Int
    let metadataRetryReady: Int
    let tagFailed: Int
    let tagLimited: Int
    let tagEmpty: Int
    let tagRetryReady: Int
    let staleTrackMetadata: Int
    let staleArtistMetadata: Int

    var retryReadyTotal: Int {
      metadataRetryReady + tagRetryReady
    }

    var retryWaitingTotal: Int {
      metadataFailed + metadataLimited + metadataPartial + tagFailed + tagLimited
    }

    var staleMetadataTotal: Int {
      staleTrackMetadata + staleArtistMetadata
    }
  }

  /// Counts distinct Spotify track URIs seen in `plays` and how many of
  /// those have been enriched (album_art_url populated by MetadataEnricher).
  /// Surfaced in the Settings diagnostic panel as "47,234 / 49,229 tracks"
  /// so the user can see the backfill progress without tailing logs.
  ///
  /// Single scan via a CASE expression — at 193k plays we don't want two
  /// separate full-table joins.
  func enrichmentProgress() throws -> EnrichmentProgress {
    try dbq.read { db in
      let row = try Row.fetchOne(db, sql: """
        SELECT
          COUNT(DISTINCT p.track_uri) AS total,
          COUNT(DISTINCT CASE WHEN t.album_art_url IS NOT NULL
                              THEN p.track_uri END) AS enriched,
          COUNT(DISTINCT CASE
            WHEN t.artists_json IS NOT NULL
             AND json_valid(t.artists_json) = 1
             AND json_extract(t.artists_json, '$[0].uri') LIKE 'spotify:artist:%'
            THEN p.track_uri END) AS track_artist_direct,
          COUNT(DISTINCT CASE
            WHEN t.artists_json IS NOT NULL
             AND json_valid(t.artists_json) = 1
             AND json_extract(t.artists_json, '$[0].uri') NOT LIKE 'spotify:artist:%'
             AND alias.source_uri IS NOT NULL
            THEN p.track_uri END) AS track_artist_aliased
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        LEFT JOIN artist_identity_aliases alias
          ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                     THEN json_extract(t.artists_json, '$[0].uri')
                                     ELSE NULL END
        WHERE p.track_uri LIKE 'spotify:track:%'
      """)
      let artistRow = try Row.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT DISTINCT
                 COALESCE(alias.canonical_uri, json_extract(j.value, '$.uri')) AS artist_uri
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(CASE WHEN json_valid(t.artists_json) = 1 THEN t.artists_json ELSE '[]' END) j
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = json_extract(j.value, '$.uri')
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
        )
        SELECT COUNT(*) AS total,
               COUNT(CASE
                 WHEN a.genres_json IS NOT NULL
                  AND json_valid(a.genres_json) = 1
                  AND json_array_length(a.genres_json) > 0
                 THEN 1 END) AS enriched
        FROM track_artists ta
        LEFT JOIN artists a ON a.uri = ta.artist_uri
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
      """)
      let tagRow = try Row.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT COALESCE(alias.canonical_uri, json_extract(j.value, '$.uri')) AS artist_uri,
                 COALESCE(MAX(alias.canonical_name), MAX(json_extract(j.value, '$.name'))) AS artist_name
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(CASE WHEN json_valid(t.artists_json) = 1 THEN t.artists_json ELSE '[]' END) j
          LEFT JOIN artist_identity_aliases alias
            ON alias.source_uri = json_extract(j.value, '$.uri')
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_uri
        ),
        taggable_artists AS (
          SELECT ta.artist_uri
          FROM track_artists ta
          LEFT JOIN artists a ON a.uri = ta.artist_uri
          WHERE COALESCE(NULLIF(a.name, ''), NULLIF(ta.artist_name, '')) IS NOT NULL
        ),
        tagged_artists AS (
          SELECT DISTINCT entity_uri
          FROM normalized_tags
          WHERE entity_type = 'artist'
        )
        SELECT COUNT(*) AS total,
               COUNT(CASE WHEN s.status IN ('success', 'empty') THEN 1 END) AS checked,
               COUNT(CASE WHEN tagged.entity_uri IS NOT NULL THEN 1 END) AS tagged
        FROM taggable_artists ta
        LEFT JOIN tag_enrichment_state s
          ON s.entity_uri = ta.artist_uri
         AND s.entity_type = 'artist'
         AND s.provider = 'lastfm'
        LEFT JOIN tagged_artists tagged ON tagged.entity_uri = ta.artist_uri
      """)
      let aliasCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM artist_identity_aliases") ?? 0
      let direct: Int = row?["track_artist_direct"] ?? 0
      let aliased: Int = row?["track_artist_aliased"] ?? 0
      return EnrichmentProgress(
        total: row?["total"] ?? 0,
        enriched: row?["enriched"] ?? 0,
        trackArtistResolved: direct + aliased,
        trackArtistDirect: direct,
        trackArtistAliased: aliased,
        artistIdentityAliases: aliasCount,
        artistTotal: artistRow?["total"] ?? 0,
        artistEnriched: artistRow?["enriched"] ?? 0,
        tagArtistTotal: tagRow?["total"] ?? 0,
        tagArtistChecked: tagRow?["checked"] ?? 0,
        tagArtistTagged: tagRow?["tagged"] ?? 0)
    }
  }

  func recentPlaySyncHealth() throws -> RecentPlaySyncHealth? {
    try dbq.read { db in
      guard let row = try Row.fetchOne(db, sql: """
        SELECT last_played_at_ms,
               last_synced_at,
               last_response_count,
               last_response_saturated,
               consecutive_saturated,
               last_inserted_count
        FROM recent_play_sync_state
        WHERE id = 1
        """)
      else { return nil }

      return RecentPlaySyncHealth(
        lastPlayedAtMs: row["last_played_at_ms"],
        lastSyncedAt: row["last_synced_at"],
        lastResponseCount: row["last_response_count"],
        lastResponseSaturated: (row["last_response_saturated"] as Int) == 1,
        consecutiveSaturated: row["consecutive_saturated"],
        lastInsertedCount: row["last_inserted_count"])
    }
  }

  func enrichmentQueueHealth(now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> EnrichmentQueueHealth {
    let retryFailedBefore = now - 86_400
    let retryLimitedBefore = now - 900
    let staleTrackBefore = now - 90 * 86_400
    let staleArtistBefore = now - 60 * 86_400

    return try dbq.read { db in
      let metadata = try Row.fetchOne(db, sql: """
        SELECT
          COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed,
          COUNT(CASE WHEN status = 'limited' THEN 1 END) AS limited,
          COUNT(CASE WHEN status = 'partial' THEN 1 END) AS partial,
          COUNT(CASE
            WHEN status IN ('failed', 'partial') AND fetched_at <= ? THEN 1
            WHEN status = 'limited' AND fetched_at <= ? THEN 1
          END) AS retry_ready,
          COUNT(CASE
            WHEN entity_type = 'track'
             AND status = 'success'
             AND fetched_at <= ?
            THEN 1
          END) AS stale_track,
          COUNT(CASE
            WHEN entity_type = 'artist'
             AND status = 'success'
             AND fetched_at <= ?
            THEN 1
          END) AS stale_artist
        FROM metadata_enrichment_state
        WHERE provider = 'spotify'
      """, arguments: [
        retryFailedBefore,
        retryLimitedBefore,
        staleTrackBefore,
        staleArtistBefore
      ])

      let tags = try Row.fetchOne(db, sql: """
        SELECT
          COUNT(CASE WHEN status = 'failed' THEN 1 END) AS failed,
          COUNT(CASE WHEN status = 'limited' THEN 1 END) AS limited,
          COUNT(CASE WHEN status = 'empty' THEN 1 END) AS empty,
          COUNT(CASE
            WHEN status = 'failed' AND fetched_at <= ? THEN 1
            WHEN status = 'limited' AND fetched_at <= ? THEN 1
          END) AS retry_ready
        FROM tag_enrichment_state
        WHERE provider = 'lastfm'
      """, arguments: [
        retryFailedBefore,
        retryLimitedBefore
      ])

      return EnrichmentQueueHealth(
        metadataFailed: metadata?["failed"] ?? 0,
        metadataLimited: metadata?["limited"] ?? 0,
        metadataPartial: metadata?["partial"] ?? 0,
        metadataRetryReady: metadata?["retry_ready"] ?? 0,
        tagFailed: tags?["failed"] ?? 0,
        tagLimited: tags?["limited"] ?? 0,
        tagEmpty: tags?["empty"] ?? 0,
        tagRetryReady: tags?["retry_ready"] ?? 0,
        staleTrackMetadata: metadata?["stale_track"] ?? 0,
        staleArtistMetadata: metadata?["stale_artist"] ?? 0)
    }
  }

  // MARK: - Badge memories

  struct BadgeSummary: Identifiable, Hashable {
    let category: BadgeCategory
    let count: Int
    var id: BadgeCategory { category }
  }

  struct BadgeMemoryRow: Identifiable, Hashable {
    let id: Int64
    let kind: BadgeMemoryKind
    let category: BadgeCategory
    let earnedAt: Int64
    let trackUri: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
  }

  func badgeSummaries(since: Int64? = nil) throws -> [BadgeSummary] {
    try dbq.read { db in
      let filter = since == nil ? "" : "WHERE earned_at >= ?"
      let arguments = since.map { StatementArguments([$0]) } ?? StatementArguments()
      let counts = try Row.fetchAll(db, sql: """
        SELECT category, COUNT(*) AS c
        FROM badge_events
        \(filter)
        GROUP BY category
      """, arguments: arguments).reduce(into: [BadgeCategory: Int]()) { acc, row in
        let raw: String = row["category"]
        guard let category = BadgeCategory(rawValue: raw) else { return }
        acc[category] = row["c"]
      }
      return BadgeCategory.allCases.compactMap { category in
        guard let count = counts[category], count > 0 else { return nil }
        return BadgeSummary(category: category, count: count)
      }
    }
  }

  func recentBadgeMemories(limit: Int = 5) throws -> [BadgeMemoryRow] {
    try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT b.id, b.kind, b.category, b.earned_at, b.track_uri,
               COALESCE(t.name, b.track_uri) AS track_name,
               COALESCE(
                 CASE WHEN json_valid(t.artists_json) = 1
                      THEN json_extract(t.artists_json, '$[0].name')
                      ELSE NULL END,
                 ''
               ) AS artist_name,
               COALESCE(b.album_name, t.album_name) AS album_name
        FROM badge_events b
        LEFT JOIN tracks t ON t.uri = b.track_uri
        ORDER BY b.earned_at DESC, b.id DESC
        LIMIT ?
      """, arguments: [limit]).compactMap { row in
        let rawKind: String = row["kind"]
        let rawCategory: String = row["category"]
        guard let kind = BadgeMemoryKind(rawValue: rawKind),
              let category = BadgeCategory(rawValue: rawCategory)
        else { return nil }
        let artistName: String = row["artist_name"]
        return BadgeMemoryRow(
          id: row["id"],
          kind: kind,
          category: category,
          earnedAt: row["earned_at"],
          trackUri: row["track_uri"],
          trackName: row["track_name"],
          artistName: artistName.isEmpty ? nil : artistName,
          albumName: row["album_name"])
      }
    }
  }

  // MARK: - Live observation

  /// Fires whenever the `plays` table changes. Window views observe this to refresh.
  func observePlaysChanges() -> ValueObservation<ValueReducers.Fetch<Int>> {
    ValueObservation.tracking { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") ?? 0
    }
  }
}
