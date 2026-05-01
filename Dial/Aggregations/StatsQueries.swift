// Dial/Aggregations/StatsQueries.swift
import GRDB
import Foundation

enum SoundThemeSource: String, Equatable {
  case artistTags
  case spotifyGenres
  case trackMetadata
  case recentSession
  case held

  var label: String {
    switch self {
    case .artistTags:    "Artist tags"
    case .spotifyGenres: "Spotify fallback"
    case .trackMetadata: "Track text"
    case .recentSession: "Recent session"
    case .held:          "Holding"
    }
  }
}

struct SoundThemeDecision: Equatable {
  let theme: DialThemeID
  let confidence: Double
  let source: SoundThemeSource
  let reason: String

  static func holding(theme: DialThemeID) -> SoundThemeDecision {
    SoundThemeDecision(
      theme: theme,
      confidence: 0,
      source: .held,
      reason: "Keeping the previous cartridge until Dial sees a confident sound signal.")
  }
}

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
        )
        SELECT ag.genre AS genre,
               COUNT(*) AS plays,
               COUNT(DISTINCT ag.artist_uri) AS artists,
               GROUP_CONCAT(DISTINCT ag.detail_tags) AS detail_tags
        FROM plays p
        JOIN tracks t ON t.uri = p.track_uri
        JOIN artist_genres ag ON ag.artist_uri =
          CASE WHEN json_valid(t.artists_json) = 1
               THEN json_extract(t.artists_json, '$[0].uri')
               ELSE NULL END
        WHERE t.artists_json IS NOT NULL
          AND json_valid(t.artists_json) = 1
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
                   NULLIF(LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))), ''),
                   json_extract(t.artists_json, '$[0].uri')
                 ) AS artist_key,
                 MIN(p.played_at) AS first_seen
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
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
        WITH artist_plays AS (
          SELECT
            NULLIF(TRIM(json_extract(t.artists_json, '$[0].uri')), '') AS artist_uri,
            NULLIF(TRIM(json_extract(t.artists_json, '$[0].name')), '') AS artist_name,
            p.played_at
          FROM plays p
          JOIN tracks t ON t.uri = p.track_uri
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
            \(rangeFilters.joined(separator: "\n            "))
        ),
        normalized AS (
          SELECT
            artist_uri,
            COALESCE(artist_name, artist_uri, 'Unknown') AS display_name,
            COALESCE(
              NULLIF(LOWER(TRIM(artist_name)), ''),
              NULLIF(LOWER(TRIM(artist_uri)), ''),
              'unknown'
            ) AS artist_key,
            played_at
          FROM artist_plays
          WHERE artist_name IS NOT NULL OR artist_uri IS NOT NULL
        ),
        canonical AS (
          SELECT
            artist_key,
            COALESCE(
              MIN(CASE WHEN artist_uri LIKE 'spotify:artist:%' THEN artist_uri END),
              MIN(NULLIF(artist_uri, '')),
              'artist-name:' || artist_key
            ) AS canonical_uri,
            COALESCE(
              MIN(CASE WHEN artist_uri LIKE 'spotify:artist:%' THEN display_name END),
              MIN(display_name),
              'Unknown'
            ) AS canonical_name
          FROM normalized
          GROUP BY artist_key
        )
        SELECT
          canon.canonical_uri AS artist_uri,
          canon.canonical_name AS name,
          COUNT(*) AS play_count
        FROM normalized n
        JOIN canonical canon ON canon.artist_key = n.artist_key
        GROUP BY n.artist_key, canon.canonical_uri, canon.canonical_name
        ORDER BY play_count DESC, MAX(n.played_at) DESC, canon.canonical_name ASC
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
        SELECT COUNT(DISTINCT json_extract(artists_json, '$[0].uri'))
        FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE t.artists_json IS NOT NULL AND json_valid(t.artists_json) = 1
          \(artistRangeFilter)
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
    let artistTotal: Int
    let artistEnriched: Int
    let tagArtistTotal: Int
    let tagArtistChecked: Int
    let tagArtistTagged: Int
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
            THEN p.track_uri END) AS track_artist_resolved
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.track_uri LIKE 'spotify:track:%'
      """)
      let artistRow = try Row.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT DISTINCT
                 json_extract(j.value, '$.uri') AS artist_uri
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(t.artists_json) j
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
        )
        SELECT COUNT(*) AS total,
               COUNT(CASE WHEN a.genres_json IS NOT NULL THEN 1 END) AS enriched
        FROM track_artists ta
        LEFT JOIN artists a ON a.uri = ta.artist_uri
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
      """)
      let tagRow = try Row.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT json_extract(j.value, '$.uri') AS artist_uri,
                 MAX(json_extract(j.value, '$.name')) AS artist_name
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(t.artists_json) j
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_uri
        ),
        taggable_artists AS (
          SELECT ta.artist_uri
          FROM track_artists ta
          LEFT JOIN artists a ON a.uri = ta.artist_uri
          WHERE ta.artist_uri LIKE 'spotify:artist:%'
            AND COALESCE(NULLIF(a.name, ''), NULLIF(ta.artist_name, '')) IS NOT NULL
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
      return EnrichmentProgress(
        total: row?["total"] ?? 0,
        enriched: row?["enriched"] ?? 0,
        trackArtistResolved: row?["track_artist_resolved"] ?? 0,
        artistTotal: artistRow?["total"] ?? 0,
        artistEnriched: artistRow?["enriched"] ?? 0,
        tagArtistTotal: tagRow?["total"] ?? 0,
        tagArtistChecked: tagRow?["checked"] ?? 0,
        tagArtistTagged: tagRow?["tagged"] ?? 0)
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

private struct SoundThemeResolver {
  let dbq: DatabaseQueue

  func decision(
    forArtistUris artistUris: [String],
    trackName: String?,
    artistName: String?,
    albumName: String?,
    allowRecentFallback: Bool
  ) throws -> SoundThemeDecision? {
    let metadata = Self.metadataDecision(
      trackName: trackName ?? "",
      artistName: artistName ?? "",
      albumName: albumName ?? "")

    let artistUris = Self.dedupedArtistUris(artistUris)
    guard !artistUris.isEmpty else { return metadata }

    return try dbq.read { db in
      if let artistDecision = try Self.artistTagDecision(db: db, artistUris: artistUris) {
        return Self.resolveConflict(artistDecision: artistDecision, metadataDecision: metadata)
      }

      if let spotifyDecision = try Self.spotifyGenreDecision(db: db, artistUris: artistUris) {
        return Self.resolveConflict(artistDecision: spotifyDecision, metadataDecision: metadata)
      }

      if let metadata {
        return metadata
      }

      if allowRecentFallback {
        return try Self.recentSessionDecision(db: db, excludingArtistUris: artistUris)
      }
      return nil
    }
  }

  static func metadataDecision(trackName: String, artistName: String, albumName: String) -> SoundThemeDecision? {
    let parts = [trackName, artistName, albumName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let text = normalizedTagText(parts.joined(separator: " "))
    guard !text.isEmpty else { return nil }

    let electronicMatch = firstMatch(in: text, from: strongElectronicTags + strongTrackElectronicTags)
    if let electronicMatch {
      return SoundThemeDecision(
        theme: .slime,
        confidence: 0.74,
        source: .trackMetadata,
        reason: "Track text contains \(electronicMatch).")
    }

    let heavyMatch = firstMatch(in: text, from: strongPunkTags + strongHeavyTags)
      ?? (containsWholeWord(text, "punk") ? "punk" : nil)
    if let heavyMatch {
      return SoundThemeDecision(
        theme: .ember,
        confidence: 0.68,
        source: .trackMetadata,
        reason: "Track text contains \(heavyMatch).")
    }

    let latinMatch = firstMatch(in: text, from: latinCulturalTags)
    if let latinMatch {
      return SoundThemeDecision(
        theme: .classic,
        confidence: 0.62,
        source: .trackMetadata,
        reason: "Track text contains Latin/Spanish marker \(latinMatch).")
    }
    return nil
  }

  private static func artistTagDecision(db: Database, artistUris: [String]) throws -> SoundThemeDecision? {
    let placeholders = Array(repeating: "?", count: artistUris.count).joined(separator: ",")
    let rows = try Row.fetchAll(db, sql: """
      SELECT nt.entity_uri AS artist_uri,
             COALESCE(NULLIF(a.name, ''), nt.entity_uri) AS artist_name,
             LOWER(TRIM(nt.raw_tag)) AS raw_tag,
             MAX(nt.score) AS score,
             MIN(rt.rank) AS rank
      FROM normalized_tags nt
      LEFT JOIN artists a ON a.uri = nt.entity_uri
      LEFT JOIN raw_tags rt
        ON rt.entity_uri = nt.entity_uri
       AND rt.entity_type = nt.entity_type
       AND rt.provider = nt.provider
       AND LOWER(TRIM(rt.raw_tag)) = LOWER(TRIM(nt.raw_tag))
      WHERE nt.entity_uri IN (\(placeholders))
        AND nt.entity_type = 'artist'
        AND nt.raw_tag IS NOT NULL
        AND TRIM(nt.raw_tag) <> ''
      GROUP BY nt.entity_uri, LOWER(TRIM(nt.raw_tag))
      ORDER BY score DESC, raw_tag ASC
    """, arguments: StatementArguments(artistUris))

    let signals: [ThemeSignal] = rows.compactMap { row in
      let artistUri: String = row["artist_uri"]
      let artistIndex = artistUris.firstIndex(of: artistUri) ?? 0
      let rawTag: String = row["raw_tag"]
      let artistName: String = row["artist_name"]
      return themeSignal(
        rawTag: rawTag,
        artistName: artistName,
        score: row["score"] ?? 0,
        rank: row["rank"],
        artistIndex: artistIndex)
    }
    guard let decision = decision(forSignals: signals, source: .artistTags) else { return nil }
    return try coreLibraryAdjustedDecision(
      decision,
      signals: signals,
      db: db,
      artistUris: artistUris)
  }

  private static func spotifyGenreDecision(db: Database, artistUris: [String]) throws -> SoundThemeDecision? {
    let placeholders = Array(repeating: "?", count: artistUris.count).joined(separator: ",")
    let rows = try Row.fetchAll(db, sql: """
      SELECT COALESCE(NULLIF(a.name, ''), a.uri) AS artist_name,
             j.value AS genre
      FROM artists a, json_each(a.genres_json) j
      WHERE a.uri IN (\(placeholders))
        AND a.genres_json IS NOT NULL
        AND json_valid(a.genres_json) = 1
        AND TRIM(j.value) <> ''
    """, arguments: StatementArguments(artistUris))

    let signals: [ThemeSignal] = rows.compactMap { row in
      let rawTag: String = row["genre"]
      let artistName: String = row["artist_name"]
      return themeSignal(
        rawTag: rawTag,
        artistName: artistName,
        score: 1,
        rank: 999,
        artistIndex: 0)
    }
    guard let decision = decision(forSignals: signals, source: .spotifyGenres) else { return nil }
    return try coreLibraryAdjustedDecision(
      decision,
      signals: signals,
      db: db,
      artistUris: artistUris)
  }

  private static func recentSessionDecision(db: Database, excludingArtistUris artistUris: [String]) throws -> SoundThemeDecision? {
    let cutoff = Int64(Date().timeIntervalSince1970) - 3 * 3_600
    let excluded = Set(artistUris.filter { !$0.isEmpty })
    let exclusion = excluded.isEmpty ? "" : "AND ra.artist_uri NOT IN (\(Array(repeating: "?", count: excluded.count).joined(separator: ",")))"
    var arguments: [DatabaseValueConvertible] = [cutoff]
    arguments.append(contentsOf: Array(excluded).sorted())

    let rows = try Row.fetchAll(db, sql: """
      WITH recent_plays AS (
        SELECT p.id AS play_id,
               p.played_at,
               t.artists_json
        FROM plays p
        JOIN tracks t ON t.uri = p.track_uri
        WHERE p.played_at >= ?
          AND t.artists_json IS NOT NULL
          AND json_valid(t.artists_json) = 1
        ORDER BY p.played_at DESC
        LIMIT 30
      ),
      recent_artists AS (
        SELECT rp.play_id,
               json_extract(j.value, '$.uri') AS artist_uri,
               json_extract(j.value, '$.name') AS artist_name
        FROM recent_plays rp
        CROSS JOIN json_each(rp.artists_json) j
        WHERE json_extract(j.value, '$.uri') LIKE 'spotify:artist:%'
      ),
      recent_artist_tags AS (
        SELECT nt.entity_uri AS artist_uri,
               LOWER(TRIM(nt.family)) AS family,
               LOWER(TRIM(nt.raw_tag)) AS raw_tag,
               MAX(nt.score) AS score
        FROM normalized_tags nt
        WHERE nt.entity_type = 'artist'
          AND nt.family IS NOT NULL
          AND TRIM(nt.family) <> ''
          AND nt.raw_tag IS NOT NULL
          AND TRIM(nt.raw_tag) <> ''
        GROUP BY nt.entity_uri, LOWER(TRIM(nt.family)), LOWER(TRIM(nt.raw_tag))
      )
      SELECT ra.artist_uri AS artist_uri,
             COALESCE(NULLIF(ra.artist_name, ''), ra.artist_uri) AS artist_name,
             rat.family AS family,
             rat.raw_tag AS raw_tag,
             rat.score AS score,
             COUNT(DISTINCT ra.play_id) AS plays
      FROM recent_artists ra
      JOIN recent_artist_tags rat ON rat.artist_uri = ra.artist_uri
      WHERE 1 = 1
        \(exclusion)
      GROUP BY ra.artist_uri, ra.artist_name, rat.family, rat.raw_tag, rat.score
    """, arguments: StatementArguments(arguments))

    let signals: [ThemeSignal] = rows.compactMap { row in
      let plays: Int = row["plays"]
      let score: Double = row["score"] ?? 0
      return themeSignal(
        rawTag: row["raw_tag"],
        artistName: row["artist_name"],
        score: max(1, Double(plays)) * max(1, score / 25),
        rank: nil,
        artistIndex: 0)
    }
    guard let decision = decision(forSignals: signals, source: .recentSession) else { return nil }
    let totalRecentPlays = rows.reduce(0) { partial, row in
      max(partial, row["plays"] as Int)
    }
    guard totalRecentPlays >= 3 else { return nil }
    return SoundThemeDecision(
      theme: decision.theme,
      confidence: min(0.72, decision.confidence),
      source: .recentSession,
      reason: "No current tags yet; recent listening is \(familyLabel(decision.theme)).")
  }

  private static func resolveConflict(
    artistDecision: SoundThemeDecision,
    metadataDecision: SoundThemeDecision?
  ) -> SoundThemeDecision {
    guard let metadataDecision, metadataDecision.theme != artistDecision.theme else {
      return artistDecision
    }

    if artistDecision.theme == .classic,
       metadataDecision.source == .trackMetadata,
       metadataDecision.confidence >= 0.68
    {
      return SoundThemeDecision(
        theme: metadataDecision.theme,
        confidence: metadataDecision.confidence,
        source: metadataDecision.source,
        reason: "\(metadataDecision.reason) Overrides Latin/Spanish Smoke Gel fallback.")
    }

    if metadataDecision.confidence >= artistDecision.confidence + 0.18 {
      return SoundThemeDecision(
        theme: metadataDecision.theme,
        confidence: metadataDecision.confidence,
        source: metadataDecision.source,
        reason: "\(metadataDecision.reason) Overrides weaker \(artistDecision.source.label.lowercased()) signal.")
    }
    return artistDecision
  }

  private struct ThemeSignal {
    let theme: DialThemeID
    let score: Double
    let rank: Int
    let strong: Bool
    let rawTag: String
    let artistName: String
  }

  private static func themeSignal(
    rawTag: String,
    artistName: String,
    score: Double,
    rank: Int?,
    artistIndex: Int
  ) -> ThemeSignal? {
    let tag = normalizedTagText(rawTag)
    guard !tag.isEmpty, !ambiguousColorTags.contains(tag) else { return nil }

    if containsAny(tag, strongElectronicTags) {
      return ThemeSignal(
        theme: .slime,
        score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: 1.45),
        rank: rank ?? 999,
        strong: true,
        rawTag: tag,
        artistName: artistName)
    }
    if containsAny(tag, strongPunkTags + strongHeavyTags) || containsWholeWord(tag, "punk") {
      return ThemeSignal(
        theme: .ember,
        score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: 1.2),
        rank: rank ?? 999,
        strong: true,
        rawTag: tag,
        artistName: artistName)
    }
    if containsAny(tag, strongAggressiveRapTags + strongHarshTags) {
      return ThemeSignal(
        theme: .ember,
        score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: 1.12),
        rank: rank ?? 999,
        strong: true,
        rawTag: tag,
        artistName: artistName)
    }
    guard let family = DialTagNormalizer.normalize(tag)?.family,
          let theme = theme(forFamily: family)
    else { return nil }

    let multiplier: Double = {
      switch theme {
      case .slime:   return 1.08
      case .ember:   return 1.0
      case .aqua:    return 0.92
      case .classic: return 1.12
      }
    }()
    return ThemeSignal(
      theme: theme,
      score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: multiplier),
      rank: rank ?? 999,
      strong: false,
      rawTag: tag,
      artistName: artistName)
  }

  private static func decision(forSignals signals: [ThemeSignal], source: SoundThemeSource) -> SoundThemeDecision? {
    guard !signals.isEmpty else { return nil }
    var scores: [DialThemeID: Double] = [:]
    var strongScores: [DialThemeID: Double] = [:]
    var bestRank: [DialThemeID: Int] = [:]

    for signal in signals {
      scores[signal.theme, default: 0] += max(1, signal.score)
      if signal.strong {
        strongScores[signal.theme, default: 0] += max(1, signal.score)
      }
      bestRank[signal.theme] = min(bestRank[signal.theme] ?? 999, signal.rank)
    }

    let ordered = scores.sorted { lhs, rhs in
      if abs(lhs.value - rhs.value) > 0.001 { return lhs.value > rhs.value }
      let lhsRank = bestRank[lhs.key] ?? 999
      let rhsRank = bestRank[rhs.key] ?? 999
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return themePriority(lhs.key) < themePriority(rhs.key)
    }
    guard var winner = ordered.first else { return nil }

    if let slime = scores[.slime], slime >= 24 {
      let rival = max(scores[.ember] ?? 0, scores[.aqua] ?? 0)
      let slimeStrong = strongScores[.slime] ?? 0
      if slimeStrong >= 24, slime >= rival * 0.55 {
        winner = (key: .slime, value: slime)
      }
    }

    let total = scores.values.reduce(0, +)
    let winnerShare = winner.value / max(1, total)
    let strongLift = min(0.18, (strongScores[winner.key] ?? 0) / max(1, winner.value) * 0.18)
    let confidence = min(0.98, max(0.50, 0.46 + winnerShare * 0.36 + strongLift))
    let reason = reason(for: winner.key, signals: signals)

    return SoundThemeDecision(
      theme: winner.key,
      confidence: confidence,
      source: source,
      reason: reason)
  }

  private static func reason(for theme: DialThemeID, signals: [ThemeSignal]) -> String {
    let winners = signals
      .filter { $0.theme == theme }
      .sorted { lhs, rhs in
        if lhs.strong != rhs.strong { return lhs.strong && !rhs.strong }
        return lhs.score > rhs.score
      }

    let details = winners.reduce(into: [(String, String)]()) { acc, signal in
      guard !acc.contains(where: { $0.0 == signal.rawTag && $0.1 == signal.artistName }) else { return }
      acc.append((signal.rawTag, signal.artistName))
    }
      .prefix(3)
      .map { "\($0.0) from \($0.1)" }
      .joined(separator: "; ")

    if details.isEmpty {
      return "Matched \(familyLabel(theme)) tags."
    }
    return "\(theme.label) from \(details)."
  }

  private static func themeScores(forFamilies families: [(String, Int)]) -> [DialThemeID: Int] {
    var scores: [DialThemeID: Int] = [:]
    for (family, score) in families {
      guard let theme = theme(forFamily: family) else { continue }
      scores[theme, default: 0] += max(1, score)
    }
    return scores
  }

  private static func orderedScores(_ scores: [DialThemeID: Int]) -> [(key: DialThemeID, value: Int)] {
    scores.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return themePriority(lhs.key) < themePriority(rhs.key)
    }
  }

  private static func weightedScore(_ score: Double, rank: Int?, artistIndex: Int, multiplier: Double) -> Double {
    let rankWeight: Double = {
      switch rank ?? 999 {
      case 1: 1.25
      case 2: 1.15
      case 3: 1.08
      case 4...5: 1.0
      default: 0.9
      }
    }()
    let artistWeight = artistIndex == 0 ? 1.0 : 0.78
    return max(1, score) * rankWeight * artistWeight * multiplier
  }

  private static func coreLibraryAdjustedDecision(
    _ decision: SoundThemeDecision,
    signals: [ThemeSignal],
    db: Database,
    artistUris: [String]
  ) throws -> SoundThemeDecision {
    guard decision.theme != .classic else { return decision }
    guard !signals.contains(where: { $0.theme == decision.theme && $0.strong }) else {
      return decision
    }

    let plays = try artistPlayCount(db: db, artistUris: artistUris)
    guard plays >= coreLibraryPlayThreshold else { return decision }

    return SoundThemeDecision(
      theme: .classic,
      confidence: min(0.86, max(0.64, decision.confidence)),
      source: decision.source,
      reason: "Smoke Gel because this is a core-library artist (\(plays) plays); weak \(decision.theme.label) signal held back.")
  }

  private static func artistPlayCount(db: Database, artistUris: [String]) throws -> Int {
    let artistUris = dedupedArtistUris(artistUris)
    guard !artistUris.isEmpty else { return 0 }
    let placeholders = Array(repeating: "?", count: artistUris.count).joined(separator: ",")
    return try Int.fetchOne(db, sql: """
      WITH artist_tracks AS (
        SELECT DISTINCT t.uri AS track_uri
        FROM tracks t, json_each(t.artists_json) j
        WHERE t.artists_json IS NOT NULL
          AND json_valid(t.artists_json) = 1
          AND json_extract(j.value, '$.uri') IN (\(placeholders))
      )
      SELECT COUNT(*)
      FROM plays p
      JOIN artist_tracks at ON at.track_uri = p.track_uri
    """, arguments: StatementArguments(artistUris)) ?? 0
  }

  private static func dedupedArtistUris(_ artistUris: [String]) -> [String] {
    var seen = Set<String>()
    return artistUris.filter { uri in
      guard uri.hasPrefix("spotify:artist:"), !seen.contains(uri) else { return false }
      seen.insert(uri)
      return true
    }
  }

  private static func normalizedTagText(_ raw: String) -> String {
    raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
  }

  private static func containsAny(_ tag: String, _ needles: [String]) -> Bool {
    needles.contains { tag.contains($0) }
  }

  private static func firstMatch(in tag: String, from needles: [String]) -> String? {
    needles.sorted { $0.count > $1.count }.first { tag.contains($0) }
  }

  private static func containsWholeWord(_ tag: String, _ word: String) -> Bool {
    tag
      .split { !$0.isLetter && !$0.isNumber }
      .contains { String($0) == word }
  }

  private static func familyLabel(_ theme: DialThemeID) -> String {
    switch theme {
    case .slime:   return "electronic"
    case .aqua:    return "aqua/indie"
    case .ember:   return "magenta/heavy"
    case .classic: return "smoke gel"
    }
  }

  private static let ambiguousColorTags: Set<String> = [
    "hardcore", "beatdown hardcore", "alternative", "seen live"
  ]

  private static let strongElectronicTags = [
    "techno", "hard techno", "industrial techno",
    "house", "hardstyle", "rawstyle", "gabber",
    "hard dance", "trance", "dubstep", "drum and bass", "dnb",
    "breakbeat", "breaks", "edm", "idm"
  ]

  private static let strongTrackElectronicTags = [
    "acid", "bassline", "breakcore", "club mix", "dance mix", "dj mix",
    "eurodance", "garage", "hard bass", "jungle", "rave", "ukg"
  ]

  private static let strongPunkTags = [
    "hardcore punk", "post hardcore", "post-hardcore", "pop punk", "screamo"
  ]

  private static let strongHeavyTags = [
    "metal", "black metal", "death metal", "doom metal", "heavy metal", "metalcore"
  ]

  private static let strongAggressiveRapTags = [
    "drill", "rage rap", "horrorcore", "trap metal", "industrial hip hop", "industrial rap"
  ]

  private static let strongHarshTags = [
    "noise", "power electronics", "harsh noise", "industrial"
  ]

  private static let latinCulturalTags = [
    "corridos tumbados", "corridos", "regional mexican",
    "reggaeton", "reggaetón", "urbano latino", "latin urban", "dembow",
    "latin", "latino", "mexican", "spanish",
    "salsa", "bachata", "cumbia", "merengue", "bolero", "bossa nova"
  ]

  fileprivate static func theme(forRawTags rawTags: [String], fallbackFamily: String?) -> DialThemeID? {
    let signals = rawTags.compactMap {
      themeSignal(rawTag: $0, artistName: "weekly memory", score: 1, rank: nil, artistIndex: 0)
    }
    if let decision = decision(forSignals: signals, source: .artistTags) {
      return decision.theme
    }
    return fallbackFamily.flatMap { theme(forFamily: $0) }
  }

  fileprivate static func theme(forFamily family: String) -> DialThemeID? {
    switch family {
    case "indie", "rock", "jazz", "ambient", "electronic", "experimental", "soundtrack":
      return .aqua
    case "latin", "corridos", "reggaeton", "rap", "r&b", "pop", "acoustic":
      return .classic
    case "punk/emo", "metal":
      return .ember
    default:
      return nil
    }
  }

  private static func themePriority(_ theme: DialThemeID) -> Int {
    switch theme {
    case .slime:   return 0
    case .ember:   return 1
    case .classic: return 2
    case .aqua:    return 3
    }
  }

  private static let coreLibraryPlayThreshold = 50
}
