// Dial/Aggregations/SoundThemeResolver.swift
import Foundation
import GRDB

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

struct SoundThemeResolver {
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

  static func theme(forRawTags rawTags: [String], fallbackFamily: String?) -> DialThemeID? {
    let signals = rawTags.compactMap {
      themeSignal(rawTag: $0, artistName: "weekly memory", score: 1, rank: nil, artistIndex: 0)
    }
    if let decision = decision(forSignals: signals, source: .artistTags) {
      return decision.theme
    }
    return fallbackFamily.flatMap { theme(forFamily: $0) }
  }

  static func theme(forFamily family: String) -> DialThemeID? {
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
