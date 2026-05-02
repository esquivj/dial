// Dial/History/MetadataEnricher.swift
import GRDB
import Foundation
import os.log

private let enricherLog = Logger(subsystem: "com.dial.Dial", category: "MetadataEnricher")

/// Walks local Spotify history and fills in metadata Dial can use for the
/// Wrapped-style memory layer:
///   * track rows get album art, album name, duration, and real artist URIs
///   * artist rows get genre arrays and image URLs
///
/// Spotify's batched catalog endpoints currently return 403 for this app in
/// development quota mode, but single-track and single-artist calls work. That
/// makes the backfill slower, but reliable and easy to throttle.
final class MetadataEnricher {
  private let dbq: DatabaseQueue
  private let client: SpotifyClient

  private enum QueuePolicy {
    static let retryFailedAfter: Int64 = 24 * 60 * 60
    static let retryPartialAfter: Int64 = 24 * 60 * 60
    static let retryLimitedAfter: Int64 = 15 * 60
    static let refreshTrackAfter: Int64 = 90 * 24 * 60 * 60
    static let refreshArtistAfter: Int64 = 60 * 24 * 60 * 60
    static let recentFirstWindow: Int64 = 45 * 24 * 60 * 60
  }

  init(dbq: DatabaseQueue, client: SpotifyClient) {
    self.dbq = dbq
    self.client = client
  }

  /// Default rate is 5 req/sec. At 5 req/sec, 49k tracks completes in ~2.7 hours;
  /// recent plays (HistoryView) get art within seconds since the queue
  /// is ordered by `MAX(p.played_at) DESC`.
  ///
  /// Endpoint choice: prefer authenticated `GET /v1/tracks/{id}` because it
  /// returns real artist URIs, album names, duration, and art. If auth/catalog
  /// access fails, fall back to public oEmbed so album art still improves.
  ///
  /// `batchSize` is unused (kept in the signature for ABI compatibility with
  /// any callers that pass it explicitly). `limit` lets launch-time warmups
  /// enrich recent tracks without turning every app start into a multi-hour
  /// backfill job.
  @discardableResult
  func enrichMissing(
    batchSize: Int = 50,
    rateLimitPerSec: Double = 5,
    limit: Int? = nil,
    respectSpotifyCooldown: Bool = true
  ) async throws -> Int {
    enricherLog.notice("enrichMissing started")
    let now = Int64(Date().timeIntervalSince1970)
    let retryFailedBefore = now - QueuePolicy.retryFailedAfter
    let retryPartialBefore = now - QueuePolicy.retryPartialAfter
    let retryLimitedBefore = now - QueuePolicy.retryLimitedAfter
    let refreshSuccessBefore = now - QueuePolicy.refreshTrackAfter
    let recentCutoff = now - QueuePolicy.recentFirstWindow
    let missing: [String] = try await dbq.read { db in
      // Order by most-recent play DESC so visible/recent rows get upgraded
      // first. "Missing" now includes rows that already have oEmbed art but
      // still only carry synthetic import artist IDs (`artist:Name`), because
      // genre enrichment needs real `spotify:artist:*` URIs. It also includes
      // a tiny stale-success queue for recent tracks so album art/duration/
      // artist IDs do not freeze forever after one old fetch.
      var sql = """
        SELECT p.track_uri
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        LEFT JOIN metadata_enrichment_state s
          ON s.entity_uri = p.track_uri
         AND s.entity_type = 'track'
         AND s.provider = 'spotify'
        WHERE p.track_uri LIKE 'spotify:track:%'
          AND (
            t.uri IS NULL
            OR t.album_art_url IS NULL
            OR t.artists_json IS NULL
            OR json_valid(t.artists_json) = 0
            OR COALESCE(
              CASE WHEN json_valid(t.artists_json) = 1
                   THEN json_extract(t.artists_json, '$[0].uri')
                   ELSE NULL END,
              ''
            ) NOT LIKE 'spotify:artist:%'
            OR (s.status = 'success' AND s.fetched_at < ? AND p.played_at >= ?)
          )
          AND (
            s.entity_uri IS NULL
            OR (s.status = 'failed' AND s.fetched_at < ?)
            OR (s.status = 'partial' AND s.fetched_at < ?)
            OR (s.status = 'limited' AND s.fetched_at < ?)
            OR (s.status = 'success' AND s.fetched_at < ? AND p.played_at >= ?)
          )
        GROUP BY p.track_uri
        ORDER BY MAX(p.played_at) DESC
      """
      var arguments: [DatabaseValueConvertible] = [
        refreshSuccessBefore,
        recentCutoff,
        retryFailedBefore,
        retryPartialBefore,
        retryLimitedBefore,
        refreshSuccessBefore,
        recentCutoff
      ]
      if let limit {
        sql += "\nLIMIT ?"
        arguments.append(max(0, limit))
      }
      return try String.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }
    let total = missing.count
    let effectiveRateLimit = max(0.1, rateLimitPerSec)
    let nominalDelay = UInt64(1_000_000_000.0 / effectiveRateLimit)
    let limitLabel = limit.map { ", capped at \($0)" } ?? ""
    enricherLog.notice("\(total) missing tracks\(limitLabel) (~\(Int(Double(total) / effectiveRateLimit))s ETA)")

    var consecutiveFailures = 0

    for (idx, uri) in missing.enumerated() {
      do {
        do {
          let meta = try await client.track(uri: uri, respectRateLimitGate: respectSpotifyCooldown)
          let track = try Self.track(from: meta)
          try await dbq.write { db in
            try track.mergeUpsert(db)
            try Self.storeMetadataState(db, entityUri: uri, entityType: "track", provider: "spotify", status: "success", fetchedAt: now, error: nil)
          }
        } catch let catalogError {
          if Self.isRateLimited(catalogError) {
            throw catalogError
          }
          enricherLog.debug("track catalog fetch failed for \(uri, privacy: .public); falling back to oEmbed")
          let oembed = try await client.trackOEmbed(uri: uri)
          let track = Track(
            uri: uri,
            name: oembed.title,
            albumName: nil,
            albumArtUrl: oembed.thumbnail_url,
            durationMs: nil,
            artistsJson: nil)
          try await dbq.write { db in
            try track.mergeUpsert(db)
            try Self.storeMetadataState(db, entityUri: uri, entityType: "track", provider: "spotify", status: "partial", fetchedAt: now, error: String(describing: catalogError))
          }
        }
        consecutiveFailures = 0
        if (idx + 1) % 25 == 0 || idx == 0 {
          enricherLog.notice("track \(idx + 1)/\(total) ok")
        }
      } catch {
        consecutiveFailures += 1
        try? await dbq.write { db in
          try Self.storeMetadataState(
            db,
            entityUri: uri,
            entityType: "track",
            provider: "spotify",
            status: Self.isRateLimited(error) ? "limited" : "failed",
            fetchedAt: now,
            error: String(describing: error))
        }
        enricherLog.warning("track \(idx + 1)/\(total) (\(uri, privacy: .public)) skipped: \(String(describing: error), privacy: .public)")
        if Self.isRateLimited(error) {
          enricherLog.error("pausing track backfill after Spotify rate limit")
          return idx + 1
        }
        // Bail if the endpoint is consistently failing — better to stop
        // than burn through 49k requests at full speed against a wall.
        // Next launch's enrichMissing() will re-attempt.
        if consecutiveFailures >= 20 {
          enricherLog.error("aborting backfill after \(consecutiveFailures) consecutive failures")
          return idx + 1
        }
      }
      try await Task.sleep(nanoseconds: nominalDelay)
    }
    enricherLog.notice("enrichMissing finished: \(total) tracks attempted")
    return total
  }

  /// Fetch genres/images for real Spotify artist IDs already present in
  /// `tracks.artists_json`. Imported rows originally contain synthetic
  /// `artist:Name` identifiers; those become enrichable after `enrichMissing`
  /// upgrades their track metadata through `GET /v1/tracks/{id}`.
  @discardableResult
  func enrichMissingArtists(
    rateLimitPerSec: Double = 5,
    limit: Int? = nil,
    respectSpotifyCooldown: Bool = true
  ) async throws -> Int {
    enricherLog.notice("enrichMissingArtists started")
    let now = Int64(Date().timeIntervalSince1970)
    let retryFailedBefore = now - QueuePolicy.retryFailedAfter
    let retryLimitedBefore = now - QueuePolicy.retryLimitedAfter
    let refreshSuccessBefore = now - QueuePolicy.refreshArtistAfter
    let recentCutoff = now - QueuePolicy.recentFirstWindow
    let candidates: [String] = try await dbq.read { db in
      var sql = """
        WITH track_artists AS (
          SELECT json_extract(j.value, '$.uri') AS artist_uri,
                 MAX(p.played_at) AS last_played
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(t.artists_json) j
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_uri
        )
        SELECT ta.artist_uri
        FROM track_artists ta
        LEFT JOIN artists a ON a.uri = ta.artist_uri
        LEFT JOIN metadata_enrichment_state s
          ON s.entity_uri = ta.artist_uri
         AND s.entity_type = 'artist'
         AND s.provider = 'spotify'
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
          AND (
            a.uri IS NULL
            OR a.genres_json IS NULL
            OR s.entity_uri IS NULL
            OR (s.status = 'failed' AND s.fetched_at < ?)
            OR (s.status = 'limited' AND s.fetched_at < ?)
            OR (s.status = 'success' AND s.fetched_at < ? AND ta.last_played >= ?)
          )
        ORDER BY ta.last_played DESC
      """
      if limit != nil {
        sql += "\nLIMIT ?"
      }
      var arguments: [DatabaseValueConvertible] = [
        retryFailedBefore,
        retryLimitedBefore,
        refreshSuccessBefore,
        recentCutoff
      ]
      if let limit { arguments.append(max(0, limit)) }
      return try String.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }

    return try await enrichArtists(
      uris: candidates,
      rateLimitPerSec: rateLimitPerSec,
      respectSpotifyCooldown: respectSpotifyCooldown)
  }

  /// Immediate small-batch artist warmup for the current track. The normal
  /// background queue is play-history driven; the currently playing track may
  /// not have been recorded as a play yet, so warm it directly.
  @discardableResult
  func enrichArtists(
    uris: [String],
    rateLimitPerSec: Double = 5,
    respectSpotifyCooldown: Bool = true
  ) async throws -> Int {
    let candidates = Array(Set(uris.filter { $0.hasPrefix("spotify:artist:") })).sorted()
    let total = candidates.count
    let effectiveRateLimit = max(0.1, rateLimitPerSec)
    let nominalDelay = UInt64(1_000_000_000.0 / effectiveRateLimit)
    enricherLog.notice("\(total) Spotify artist candidates (~\(Int(Double(total) / effectiveRateLimit))s ETA)")

    var consecutiveFailures = 0

    for (idx, uri) in candidates.enumerated() {
      do {
        let meta = try await client.artist(uri: uri, respectRateLimitGate: respectSpotifyCooldown)
        let artist = try Self.artist(from: meta)
        try await dbq.write { db in
          try artist.mergeUpsert(db)
          try Self.storeMetadataState(db, entityUri: uri, entityType: "artist", provider: "spotify", status: "success", fetchedAt: Int64(Date().timeIntervalSince1970), error: nil)
        }
        consecutiveFailures = 0
        if (idx + 1) % 25 == 0 || idx == 0 {
          enricherLog.notice("artist \(idx + 1)/\(total) ok")
        }
      } catch {
        consecutiveFailures += 1
        try? await dbq.write { db in
          try Self.storeMetadataState(
            db,
            entityUri: uri,
            entityType: "artist",
            provider: "spotify",
            status: Self.isRateLimited(error) ? "limited" : "failed",
            fetchedAt: Int64(Date().timeIntervalSince1970),
            error: String(describing: error))
        }
        enricherLog.warning("artist \(idx + 1)/\(total) (\(uri, privacy: .public)) skipped: \(String(describing: error), privacy: .public)")
        if Self.isRateLimited(error) {
          enricherLog.error("pausing artist backfill after Spotify rate limit")
          return idx + 1
        }
        if consecutiveFailures >= 20 {
          enricherLog.error("aborting artist backfill after \(consecutiveFailures) consecutive failures")
          return idx + 1
        }
      }
      try await Task.sleep(nanoseconds: nominalDelay)
    }
    enricherLog.notice("enrichMissingArtists finished: \(total) artists attempted")
    return total
  }

  private static func storeMetadataState(
    _ db: Database,
    entityUri: String,
    entityType: String,
    provider: String,
    status: String,
    fetchedAt: Int64,
    error: String?
  ) throws {
    try db.execute(sql: """
      INSERT INTO metadata_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(entity_uri, entity_type, provider) DO UPDATE SET
        status = excluded.status,
        fetched_at = excluded.fetched_at,
        error = excluded.error
      """, arguments: [entityUri, entityType, provider, status, fetchedAt, error.map { String($0.prefix(240)) }])
  }

  private static func isRateLimited(_ error: Error) -> Bool {
    if case SpotifyAPIError.httpStatus(429) = error { return true }
    if case SpotifyAPIError.rateLimited = error { return true }
    return false
  }

  private static func track(from meta: TrackMeta) throws -> Track {
    let artists = meta.artists.map { EnrichedTrackArtist(name: $0.name, uri: $0.uri) }
    let artistsData = try JSONEncoder().encode(artists)
    return Track(
      uri: meta.uri,
      name: meta.name,
      albumName: meta.album.name,
      albumArtUrl: meta.album.images.first?.url,
      durationMs: Int64(meta.duration_ms),
      artistsJson: String(data: artistsData, encoding: .utf8))
  }

  private static func artist(from meta: ArtistMeta) throws -> Artist {
    let genresData = try JSONEncoder().encode(meta.genres)
    return Artist(
      uri: meta.uri,
      name: meta.name,
      genresJson: String(data: genresData, encoding: .utf8),
      imageUrl: meta.images.first?.url)
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}

private struct EnrichedTrackArtist: Encodable {
  let name: String
  let uri: String
}

// MARK: - Tag intelligence

struct LastFMTag: Equatable {
  let name: String
  let count: Double
  let url: String?
}

enum LastFMError: Error, Equatable {
  case httpStatus(Int)
  case api(Int, String)
  case invalidResponse
}

final class LastFMClient {
  private let apiKey: String
  private let session: URLSession

  init(apiKey: String, session: URLSession = .shared) {
    self.apiKey = apiKey
    self.session = session
  }

  func artistTopTags(name: String) async throws -> [LastFMTag] {
    var comps = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
    comps.queryItems = [
      URLQueryItem(name: "method", value: "artist.getTopTags"),
      URLQueryItem(name: "artist", value: name),
      URLQueryItem(name: "api_key", value: apiKey),
      URLQueryItem(name: "format", value: "json"),
      URLQueryItem(name: "autocorrect", value: "1")
    ]
    guard let url = comps.url else { throw LastFMError.invalidResponse }
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse else {
      throw LastFMError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw LastFMError.httpStatus(http.statusCode)
    }
    let envelope = try JSONDecoder().decode(LastFMTopTagsEnvelope.self, from: data)
    if let code = envelope.error {
      throw LastFMError.api(code, envelope.message ?? "Last.fm error")
    }
    return (envelope.toptags?.tag ?? [])
      .map { LastFMTag(name: $0.name, count: $0.count, url: $0.url) }
      .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
        return lhs.count > rhs.count
      }
  }
}

final class TagEnricher {
  private let dbq: DatabaseQueue
  private let lastFM: LastFMClient

  private enum QueuePolicy {
    static let retryFailedAfter: Int64 = 24 * 60 * 60
    static let retryLimitedAfter: Int64 = 15 * 60
    static let refreshAfter: Int64 = 60 * 24 * 60 * 60
    static let recentFirstWindow: Int64 = 45 * 24 * 60 * 60
  }

  init(dbq: DatabaseQueue, lastFM: LastFMClient) {
    self.dbq = dbq
    self.lastFM = lastFM
  }

  @discardableResult
  func enrichMissingArtists(rateLimitPerSec: Double = 1, limit: Int? = nil) async throws -> Int {
    let now = Int64(Date().timeIntervalSince1970)
    let retryFailedBefore = now - QueuePolicy.retryFailedAfter
    let retryLimitedBefore = now - QueuePolicy.retryLimitedAfter
    let refreshBefore = now - QueuePolicy.refreshAfter
    let recentCutoff = now - QueuePolicy.recentFirstWindow
    let candidates: [ArtistTagCandidate] = try await dbq.read { db in
      var sql = """
        WITH track_artists AS (
          SELECT json_extract(j.value, '$.uri') AS artist_uri,
                 json_extract(j.value, '$.name') AS artist_name,
                 COUNT(*) AS play_count,
                 MAX(p.played_at) AS last_played
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(t.artists_json) j
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_uri
        )
        SELECT ta.artist_uri AS uri,
               COALESCE(NULLIF(a.name, ''), ta.artist_name) AS name
        FROM track_artists ta
        LEFT JOIN artists a ON a.uri = ta.artist_uri
        LEFT JOIN tag_enrichment_state s
          ON s.entity_uri = ta.artist_uri
         AND s.entity_type = 'artist'
         AND s.provider = 'lastfm'
        WHERE ta.artist_uri LIKE 'spotify:artist:%'
          AND COALESCE(NULLIF(a.name, ''), ta.artist_name) IS NOT NULL
          AND COALESCE(NULLIF(a.name, ''), ta.artist_name) <> ''
          AND (
            s.entity_uri IS NULL
            OR (s.status = 'failed' AND s.fetched_at < ?)
            OR (s.status = 'limited' AND s.fetched_at < ?)
            OR (s.status IN ('success', 'empty') AND s.fetched_at < ? AND ta.last_played >= ?)
          )
        ORDER BY ta.last_played DESC, ta.play_count DESC
      """
      var arguments: [DatabaseValueConvertible] = [
        retryFailedBefore,
        retryLimitedBefore,
        refreshBefore,
        recentCutoff
      ]
      if let limit {
        sql += "\nLIMIT ?"
        arguments.append(max(0, limit))
      }
      return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map {
        ArtistTagCandidate(uri: $0["uri"], name: $0["name"])
      }
    }

    return try await enrichArtists(candidates, rateLimitPerSec: rateLimitPerSec)
  }

  /// Immediate Last.fm warmup for the current track's artists. This bypasses
  /// the play-history queue so a new track can get its sound cartridge without
  /// waiting until it has been counted as a full play.
  @discardableResult
  func enrichArtists(_ candidates: [ArtistTagCandidate], rateLimitPerSec: Double = 1) async throws -> Int {
    let now = Int64(Date().timeIntervalSince1970)
    var seen = Set<String>()
    let candidates = candidates.filter { candidate in
      candidate.uri.hasPrefix("spotify:artist:")
        && !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && seen.insert(candidate.uri).inserted
    }
    let total = candidates.count
    let effectiveRateLimit = max(0.1, rateLimitPerSec)
    let nominalDelay = UInt64(1_000_000_000.0 / effectiveRateLimit)
    enricherLog.notice("\(total) Last.fm artist tag candidates (~\(Int(Double(total) / effectiveRateLimit))s ETA)")

    for (idx, candidate) in candidates.enumerated() {
      do {
        let tags = try await lastFM.artistTopTags(name: candidate.name)
        try await dbq.write { db in
          try Self.store(
            db,
            artistUri: candidate.uri,
            tags: Array(tags.prefix(20)),
            fetchedAt: now)
        }
        if (idx + 1) % 25 == 0 || idx == 0 {
          enricherLog.notice("Last.fm artist \(idx + 1)/\(total) ok")
        }
      } catch {
        try await dbq.write { db in
          try Self.storeFailure(
            db,
            artistUri: candidate.uri,
            error: String(describing: error),
            fetchedAt: now)
        }
        enricherLog.warning("Last.fm artist \(idx + 1)/\(total) (\(candidate.name, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
        if Self.isRateLimited(error) {
          enricherLog.error("pausing Last.fm tag backfill after rate limit")
          return idx + 1
        }
      }
      try await Task.sleep(nanoseconds: nominalDelay)
    }
    enricherLog.notice("Last.fm artist tag enrichment finished: \(total) artists attempted")
    return total
  }

  private static func isRateLimited(_ error: Error) -> Bool {
    if case LastFMError.httpStatus(429) = error { return true }
    return false
  }

  private static func store(
    _ db: Database,
    artistUri: String,
    tags: [LastFMTag],
    fetchedAt: Int64
  ) throws {
    try db.execute(sql: """
      DELETE FROM raw_tags
      WHERE entity_uri = ? AND entity_type = 'artist' AND provider = 'lastfm'
      """, arguments: [artistUri])
    try db.execute(sql: """
      DELETE FROM normalized_tags
      WHERE entity_uri = ? AND entity_type = 'artist' AND provider = 'lastfm'
      """, arguments: [artistUri])

    for (idx, tag) in tags.enumerated() {
      let rawTag = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !rawTag.isEmpty else { continue }
      try db.execute(sql: """
        INSERT INTO raw_tags (entity_uri, entity_type, provider, raw_tag, score, rank, source_url, fetched_at)
        VALUES (?, 'artist', 'lastfm', ?, ?, ?, ?, ?)
        ON CONFLICT(entity_uri, entity_type, provider, raw_tag) DO UPDATE SET
          score = excluded.score,
          rank = excluded.rank,
          source_url = excluded.source_url,
          fetched_at = excluded.fetched_at
        """, arguments: [artistUri, rawTag, tag.count, idx + 1, tag.url, fetchedAt])

      guard let normalized = DialTagNormalizer.normalize(rawTag) else { continue }
      try db.execute(sql: """
        INSERT INTO normalized_tags (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        VALUES (?, 'artist', 'lastfm', ?, ?, ?, ?)
        ON CONFLICT(entity_uri, entity_type, provider, family, raw_tag) DO UPDATE SET
          score = excluded.score,
          updated_at = excluded.updated_at
        """, arguments: [artistUri, normalized.family, normalized.rawTag, tag.count, fetchedAt])
    }

    let status = tags.isEmpty ? "empty" : "success"
    try db.execute(sql: """
      INSERT INTO tag_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
      VALUES (?, 'artist', 'lastfm', ?, ?, NULL)
      ON CONFLICT(entity_uri, entity_type, provider) DO UPDATE SET
        status = excluded.status,
        fetched_at = excluded.fetched_at,
        error = NULL
      """, arguments: [artistUri, status, fetchedAt])
  }

  private static func storeFailure(
    _ db: Database,
    artistUri: String,
    error: String,
    fetchedAt: Int64
  ) throws {
    try db.execute(sql: """
      INSERT INTO tag_enrichment_state (entity_uri, entity_type, provider, status, fetched_at, error)
          VALUES (?, 'artist', 'lastfm', ?, ?, ?)
      ON CONFLICT(entity_uri, entity_type, provider) DO UPDATE SET
        status = excluded.status,
        fetched_at = excluded.fetched_at,
        error = excluded.error
      """, arguments: [artistUri, error.contains("httpStatus(429)") ? "limited" : "failed", fetchedAt, String(error.prefix(240))])
  }
}

struct NormalizedTag: Equatable {
  let family: String
  let rawTag: String
}

enum DialTagNormalizer {
  static func normalize(_ raw: String) -> NormalizedTag? {
    let tag = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
    guard !tag.isEmpty, !ignoredTags.contains(where: tag.contains) else { return nil }

    for rule in rules where rule.matches.contains(where: tag.contains) {
      return NormalizedTag(family: rule.family, rawTag: tag)
    }
    return nil
  }

  private static let ignoredTags = [
    "seen live", "favorite", "favourite", "favorites", "favourites",
    "spotify", "last.fm", "albums i own", "under 2000 listeners"
  ]

  private static let rules: [Rule] = [
    .init("corridos", ["corridos", "corridos tumbados", "regional mexican", "musica mexicana", "música mexicana", "banda", "norteno", "norteño", "ranchera", "sierreño", "sierreno"]),
    .init("reggaeton", ["reggaeton", "reggaetón", "urbano latino", "latin urban", "dembow"]),
    .init("latin", ["latin", "latino", "mexican", "spanish", "salsa", "bachata", "cumbia", "merengue", "bolero", "bossa nova"]),
    .init("ambient", ["ambient", "drone", "new age", "soundscape", "downtempo", "chillout", "chillwave"]),
    .init("electronic", ["electronic", "electronica", "electro", "electroclash", "edm", "techno", "hard techno", "industrial techno", "house", "dance", "hard dance", "hardstyle", "rawstyle", "gabber", "hardcore techno", "trance", "garage", "breakbeat", "breaks", "drum and bass", "dnb", "dubstep", "future bass", "bass music", "synthpop", "synth pop", "idm"]),
    .init("r&b", ["r&b", "rnb", "soul", "neo soul", "funk"]),
    .init("rap", ["hip hop", "hip-hop", "rap", "trap", "drill", "cloud rap", "boom bap"]),
    .init("indie", ["indie", "bedroom pop", "dream pop", "shoegaze", "alternative", "lo fi", "lo-fi", "slacker rock"]),
    .init("punk/emo", ["punk", "emo", "pop punk", "hardcore punk", "post hardcore", "post-hardcore", "screamo"]),
    .init("metal", ["metal", "black metal", "death metal", "doom metal", "metalcore"]),
    .init("rock", ["rock", "grunge", "psychedelic", "post rock", "classic rock", "garage rock"]),
    .init("acoustic", ["folk", "acoustic", "singer songwriter", "singer-songwriter", "americana", "country", "bluegrass"]),
    .init("jazz", ["jazz", "bebop", "fusion"]),
    .init("experimental", ["experimental", "avant garde", "avant-garde", "noise", "industrial"]),
    .init("soundtrack", ["soundtrack", "score", "ost", "film score", "video game music"]),
    .init("pop", ["pop", "k pop", "k-pop", "j pop", "j-pop", "electropop"])
  ]
}

private struct Rule {
  let family: String
  let matches: [String]

  init(_ family: String, _ matches: [String]) {
    self.family = family
    self.matches = matches
  }
}

struct ArtistTagCandidate {
  let uri: String
  let name: String
}

private struct LastFMTopTagsEnvelope: Decodable {
  let toptags: LastFMTopTags?
  let error: Int?
  let message: String?
}

private struct LastFMTopTags: Decodable {
  let tag: [LastFMTagPayload]

  private enum CodingKeys: String, CodingKey {
    case tag
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let tags = try? container.decode([LastFMTagPayload].self, forKey: .tag) {
      tag = tags
    } else if let single = try? container.decode(LastFMTagPayload.self, forKey: .tag) {
      tag = [single]
    } else {
      tag = []
    }
  }
}

private struct LastFMTagPayload: Decodable {
  let name: String
  let count: Double
  let url: String?

  private enum CodingKeys: String, CodingKey {
    case name, count, url
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    url = try container.decodeIfPresent(String.self, forKey: .url)
    if let int = try? container.decode(Int.self, forKey: .count) {
      count = Double(int)
    } else if let double = try? container.decode(Double.self, forKey: .count) {
      count = double
    } else if let string = try? container.decode(String.self, forKey: .count),
              let double = Double(string) {
      count = double
    } else {
      count = 0
    }
  }
}
