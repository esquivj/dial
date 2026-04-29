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

  func topTracks(limit: Int = 10, since: Int64? = nil) throws -> [TopRow] {
    try dbq.read { db in
      let filter = since == nil ? "" : "WHERE p.played_at >= ?"
      let arguments = since.map { [$0, Int64(limit)] } ?? [Int64(limit)]
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
    var id: String { genre }
  }

  /// Top artist-derived sound signals for the selected range. Dial prefers
  /// normalized tags from external providers (currently Last.fm), then falls
  /// back to Spotify's deprecated artist genres when they exist.
  ///
  /// A play can contribute to multiple family buckets when its primary artist
  /// has several tags. That's intentional: this powers "sound weather," not
  /// exact accounting.
  func topGenres(limit: Int = 8, since: Int64? = nil) throws -> [GenreRow] {
    try dbq.read { db in
      let rangeFilter = since == nil ? "" : "AND p.played_at >= ?"
      let arguments = since.map { [$0, Int64(limit)] } ?? [Int64(limit)]
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
          \(rangeFilter)
        GROUP BY ag.genre
        ORDER BY plays DESC, artists DESC, genre ASC
        LIMIT ?
      """, arguments: StatementArguments(arguments)).map { row in
        GenreRow(
          genre: row["genre"],
          playCount: row["plays"],
          artistCount: row["artists"],
          detailTags: Self.splitTags(row["detail_tags"]))
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
    try resolvedSoundTheme(forArtistUris: artistUris, allowRecentFallback: true) ?? .classic
  }

  func directSoundTheme(forArtistUris artistUris: [String]) throws -> DialThemeID? {
    try resolvedSoundTheme(forArtistUris: artistUris, allowRecentFallback: false)
  }

  private func resolvedSoundTheme(forArtistUris artistUris: [String], allowRecentFallback: Bool) throws -> DialThemeID? {
    var seenArtistUris = Set<String>()
    let artistUris = artistUris.filter { uri in
      guard !uri.isEmpty, !seenArtistUris.contains(uri) else { return false }
      seenArtistUris.insert(uri)
      return true
    }
    guard !artistUris.isEmpty else { return nil }

    return try dbq.read { db in
      let placeholders = Array(repeating: "?", count: artistUris.count).joined(separator: ",")
      let rows = try Row.fetchAll(db, sql: """
        SELECT nt.entity_uri AS artist_uri,
               LOWER(TRIM(nt.raw_tag)) AS raw_tag,
               MAX(nt.score) AS score,
               MIN(rt.rank) AS rank
        FROM normalized_tags nt
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
        return Self.themeSignal(
          rawTag: rawTag,
          score: row["score"] ?? 0,
          rank: row["rank"],
          artistIndex: artistIndex)
      }
      if let theme = Self.theme(forSignals: signals) {
        return theme
      }

      let genreRows = try Row.fetchAll(db, sql: """
        SELECT genres_json
        FROM artists
        WHERE uri IN (\(placeholders))
          AND genres_json IS NOT NULL
          AND json_valid(genres_json) = 1
      """, arguments: StatementArguments(artistUris))
      let spotifyFamilies = genreRows.flatMap { row in
        Self.spotifyFamilies(from: row["genres_json"])
      }
      if let theme = Self.theme(forFamilies: spotifyFamilies.map { ($0, 1) }) {
        return theme
      }

      if allowRecentFallback {
        return try Self.recentSessionTheme(db: db, excludingArtistUris: artistUris)
      }
      return nil
    }
  }

  private static func theme(forFamilies families: [(String, Int)]) -> DialThemeID? {
    let scores = themeScores(forFamilies: families)
    return scores
      .sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return themePriority(lhs.key) < themePriority(rhs.key)
      }
      .first?
      .key
  }

  private static func themeScores(forFamilies families: [(String, Int)]) -> [DialThemeID: Int] {
    var scores: [DialThemeID: Int] = [:]
    for (family, score) in families {
      guard let theme = theme(forFamily: family) else { continue }
      scores[theme, default: 0] += max(1, score)
    }
    return scores
  }

  private static func recentSessionTheme(db: Database, excludingArtistUris artistUris: [String]) throws -> DialThemeID? {
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
               json_extract(j.value, '$.uri') AS artist_uri
        FROM recent_plays rp
        CROSS JOIN json_each(rp.artists_json) j
        WHERE json_extract(j.value, '$.uri') LIKE 'spotify:artist:%'
      ),
      normalized_artist_families AS (
        SELECT nt.entity_uri AS artist_uri,
               LOWER(TRIM(nt.family)) AS family
        FROM normalized_tags nt
        WHERE nt.entity_type = 'artist'
          AND nt.family IS NOT NULL
          AND TRIM(nt.family) <> ''
        GROUP BY nt.entity_uri, LOWER(TRIM(nt.family))
      )
      SELECT naf.family AS family,
             COUNT(DISTINCT ra.play_id) AS plays
      FROM recent_artists ra
      JOIN normalized_artist_families naf ON naf.artist_uri = ra.artist_uri
      WHERE 1 = 1
        \(exclusion)
      GROUP BY naf.family
    """, arguments: StatementArguments(arguments))

    let families: [(String, Int)] = rows.map { row in
      (row["family"], row["plays"])
    }
    let scores = themeScores(forFamilies: families)
    guard !scores.isEmpty else { return nil }

    let ordered = scores.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return themePriority(lhs.key) < themePriority(rhs.key)
    }
    guard let winner = ordered.first else { return nil }
    let total = scores.values.reduce(0, +)
    let winnerShare = Double(winner.value) / Double(max(1, total))

    guard total >= 4, winner.value >= 3, winnerShare >= 0.60 else { return nil }
    return winner.key
  }

  private struct ThemeSignal {
    let theme: DialThemeID
    let score: Double
    let rank: Int
    let strong: Bool
  }

  private static func themeSignal(rawTag: String, score: Double, rank: Int?, artistIndex: Int) -> ThemeSignal? {
    let tag = normalizedTagText(rawTag)
    guard !tag.isEmpty, !ambiguousColorTags.contains(tag) else { return nil }

    if containsAny(tag, strongElectronicTags) {
      return ThemeSignal(theme: .slime, score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: 1.45), rank: rank ?? 999, strong: true)
    }
    if containsAny(tag, strongPunkTags) {
      return ThemeSignal(theme: .ember, score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: 1.2), rank: rank ?? 999, strong: true)
    }
    guard let family = DialTagNormalizer.normalize(tag)?.family,
          let theme = theme(forFamily: family)
    else { return nil }

    let multiplier: Double = {
      switch theme {
      case .slime:
        return 1.08
      case .ember:
        return 1.0
      case .aqua:
        return 0.92
      case .classic:
        return 1.0
      }
    }()
    return ThemeSignal(theme: theme, score: weightedScore(score, rank: rank, artistIndex: artistIndex, multiplier: multiplier), rank: rank ?? 999, strong: false)
  }

  private static func theme(forSignals signals: [ThemeSignal]) -> DialThemeID? {
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
    guard let winner = ordered.first else { return nil }

    if let slime = scores[.slime], slime >= 24 {
      let rival = max(scores[.ember] ?? 0, scores[.aqua] ?? 0)
      let slimeStrong = strongScores[.slime] ?? 0
      // Electronic tags are often more specific than broad Last.fm labels
      // like "latin", "alternative", or "hardcore". If slime has concrete
      // evidence and is in the same neighborhood as the winner, keep the HUD
      // in the electronic cartridge instead of flashing a wrong color.
      if slimeStrong >= 24, slime >= rival * 0.55 {
        return .slime
      }
    }

    return winner.key
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

  private static let ambiguousColorTags: Set<String> = [
    "hardcore", "beatdown hardcore", "alternative", "seen live"
  ]

  private static let strongElectronicTags = [
    "electronic", "electronica", "electro", "techno", "hard techno",
    "industrial techno", "house", "hardstyle", "rawstyle", "gabber",
    "hard dance", "trance", "dubstep", "drum and bass", "dnb",
    "breakbeat", "breaks", "edm", "idm", "synthpop", "synth pop"
  ]

  private static let strongPunkTags = [
    "hardcore punk", "post hardcore", "post-hardcore", "pop punk", "screamo"
  ]

  private static func theme(forFamily family: String) -> DialThemeID? {
    switch family {
    case "electronic", "ambient", "experimental", "soundtrack":
      return .slime
    case "indie", "pop", "acoustic", "r&b", "rock", "jazz":
      return .aqua
    case "latin", "corridos", "reggaeton", "rap", "punk/emo", "metal":
      return .ember
    default:
      return nil
    }
  }

  private static func themePriority(_ theme: DialThemeID) -> Int {
    switch theme {
    case .ember:   return 0
    case .slime:   return 1
    case .aqua:    return 2
    case .classic: return 3
    }
  }

  private static func spotifyFamilies(from genresJson: String?) -> [String] {
    guard
      let genresJson,
      let data = genresJson.data(using: .utf8),
      let genres = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return genres.compactMap { DialTagNormalizer.normalize($0)?.family }
  }

  private static func splitTags(_ value: String?) -> [String] {
    guard let value else { return [] }
    return value
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// Top artists by play count. Filters to rows with VALID `artists_json`
  /// (some imported rows have malformed JSON that crashes json_extract).
  ///
  /// **Alias note**: the column alias is `artist_uri`, not `uri`. SQLite's
  /// GROUP BY resolves `uri` to the unambiguous `tracks.uri` column (track
  /// URI — unique per track) instead of our extracted-artist alias, which
  /// produced one row per track (not per artist). Symptom in the UI:
  /// the same artist (e.g. "Junior H") appearing multiple times in
  /// top-artists with different play counts that don't sum to the artist's
  /// actual total. Renaming the alias avoids the collision.
  func topArtists(limit: Int = 10, since: Int64? = nil) throws -> [TopRow] {
    try dbq.read { db in
      let rangeFilter = since == nil ? "" : "AND p.played_at >= ?"
      let arguments = since.map { [$0, Int64(limit)] } ?? [Int64(limit)]
      return try Row.fetchAll(db, sql: """
        SELECT
          json_extract(t.artists_json, '$[0].uri')  AS artist_uri,
          json_extract(t.artists_json, '$[0].name') AS name,
          COUNT(*) AS c
        FROM plays p JOIN tracks t ON t.uri = p.track_uri
        WHERE t.artists_json IS NOT NULL AND json_valid(t.artists_json) = 1
          \(rangeFilter)
        GROUP BY artist_uri
        ORDER BY c DESC, MAX(p.played_at) DESC
        LIMIT ?
      """, arguments: StatementArguments(arguments)).map { row in
        TopRow(uri: row["artist_uri"] ?? "", name: row["name"] ?? "Unknown", count: row["c"],
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

  func totals(since: Int64? = nil) throws -> Totals {
    try dbq.read { db in
      let playsFilter = since == nil ? "" : "WHERE played_at >= ?"
      let artistRangeFilter = since == nil ? "" : "AND p.played_at >= ?"
      let arguments = since.map { StatementArguments([$0]) } ?? StatementArguments()
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
      """, arguments: arguments)
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
      """, arguments: arguments) ?? 0
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
                 CASE WHEN json_valid(artists_json) = 1
                      THEN json_extract(artists_json, '$[0].uri')
                      ELSE NULL END AS artist_uri
          FROM tracks
          WHERE artists_json IS NOT NULL
            AND json_valid(artists_json) = 1
        )
        SELECT COUNT(*) AS total,
               COUNT(CASE WHEN a.genres_json IS NOT NULL THEN 1 END) AS enriched
        FROM track_artists ta
        LEFT JOIN artists a ON a.uri = ta.artist_uri
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
      """)
      let tagRow = try Row.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT DISTINCT
                 CASE WHEN json_valid(artists_json) = 1
                      THEN json_extract(artists_json, '$[0].uri')
                      ELSE NULL END AS artist_uri
          FROM tracks
          WHERE artists_json IS NOT NULL
            AND json_valid(artists_json) = 1
        ),
        tagged_artists AS (
          SELECT DISTINCT entity_uri
          FROM normalized_tags
          WHERE entity_type = 'artist'
        )
        SELECT COUNT(*) AS total,
               COUNT(CASE WHEN s.status IN ('success', 'empty') THEN 1 END) AS checked,
               COUNT(CASE WHEN tagged.entity_uri IS NOT NULL THEN 1 END) AS tagged
        FROM track_artists ta
        LEFT JOIN tag_enrichment_state s
          ON s.entity_uri = ta.artist_uri
         AND s.entity_type = 'artist'
         AND s.provider = 'lastfm'
        LEFT JOIN tagged_artists tagged ON tagged.entity_uri = ta.artist_uri
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
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
