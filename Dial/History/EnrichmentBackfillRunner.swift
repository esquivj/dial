import Foundation
import GRDB

struct EnrichmentBackfillAudit: Equatable {
  let totalTracks: Int
  let albumArtTracks: Int
  let resolvedTrackArtists: Int
  let spotifyArtistTotal: Int
  let spotifyArtistGenres: Int
  let lastFMArtistTotal: Int
  let lastFMArtistChecked: Int
  let lastFMArtistTagged: Int
  let eligibleTrackBacklog: Int
  let eligibleArtistBacklog: Int
  let eligibleTagBacklog: Int
  let spotifyStateCounts: [String: Int]
  let lastFMStateCounts: [String: Int]
  let spotifyCooldownUntil: Date?

  var hasWork: Bool {
    eligibleTrackBacklog > 0 || eligibleArtistBacklog > 0 || eligibleTagBacklog > 0
  }

  var spotifyCooldownRemaining: TimeInterval {
    guard let spotifyCooldownUntil else { return 0 }
    return max(0, spotifyCooldownUntil.timeIntervalSinceNow)
  }

  var compactSummary: String {
    let cooldown = spotifyCooldownRemaining
    let cooldownText = cooldown > 0 ? ", Spotify cooldown \(Self.duration(cooldown))" : ""
    return [
      "tracks: \(resolvedTrackArtists.formatted())/\(totalTracks.formatted()) artist IDs",
      "art: \(albumArtTracks.formatted())/\(totalTracks.formatted())",
      "artist genres: \(spotifyArtistGenres.formatted())/\(spotifyArtistTotal.formatted())",
      "Last.fm: \(lastFMArtistTagged.formatted()) tagged / \(lastFMArtistChecked.formatted()) checked",
      "eligible now: \(eligibleTrackBacklog.formatted()) tracks, \(eligibleArtistBacklog.formatted()) artists, \(eligibleTagBacklog.formatted()) tags\(cooldownText)"
    ].joined(separator: " | ")
  }

  private static func duration(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(Int(ceil(seconds)))s" }
    if seconds < 3600 { return "\(Int(ceil(seconds / 60)))m" }
    return "\(Int(ceil(seconds / 3600)))h"
  }
}

final class EnrichmentBackfillRunner {
  private let dbq: DatabaseQueue
  private let client: SpotifyClient
  private let lastFMKey: String
  private let logger: (String) -> Void

  private enum QueuePolicy {
    static let retryFailedAfter: Int64 = 24 * 60 * 60
    static let retryPartialAfter: Int64 = 24 * 60 * 60
    static let retryLimitedAfter: Int64 = 15 * 60
    static let refreshTrackAfter: Int64 = 90 * 24 * 60 * 60
    static let refreshArtistAfter: Int64 = 60 * 24 * 60 * 60
    static let refreshTagsAfter: Int64 = 60 * 24 * 60 * 60
    static let recentFirstWindow: Int64 = 45 * 24 * 60 * 60
  }

  init(
    dbq: DatabaseQueue,
    client: SpotifyClient,
    lastFMKey: String,
    logger: @escaping (String) -> Void
  ) {
    self.dbq = dbq
    self.client = client
    self.lastFMKey = lastFMKey
    self.logger = logger
  }

  func audit() async throws -> EnrichmentBackfillAudit {
    let progress = try StatsQueries(dbq: dbq).enrichmentProgress()
    let now = Int64(Date().timeIntervalSince1970)
    let retryFailedBefore = now - QueuePolicy.retryFailedAfter
    let retryPartialBefore = now - QueuePolicy.retryPartialAfter
    let retryLimitedBefore = now - QueuePolicy.retryLimitedAfter
    let refreshTrackBefore = now - QueuePolicy.refreshTrackAfter
    let refreshArtistBefore = now - QueuePolicy.refreshArtistAfter
    let refreshTagsBefore = now - QueuePolicy.refreshTagsAfter
    let recentCutoff = now - QueuePolicy.recentFirstWindow

    let eligibleTracks = try await dbq.read { db in
      try Int.fetchOne(db, sql: """
        SELECT COUNT(*)
        FROM (
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
        )
        """, arguments: [
          refreshTrackBefore,
          recentCutoff,
          retryFailedBefore,
          retryPartialBefore,
          retryLimitedBefore,
          refreshTrackBefore,
          recentCutoff
        ]) ?? 0
    }

    let eligibleArtists = try await dbq.read { db in
      try Int.fetchOne(db, sql: """
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
        SELECT COUNT(*)
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
        """, arguments: [
          retryFailedBefore,
          retryLimitedBefore,
          refreshArtistBefore,
          recentCutoff
        ]) ?? 0
    }

    let eligibleTags = try await dbq.read { db in
      try Int.fetchOne(db, sql: """
        WITH track_artists AS (
          SELECT json_extract(j.value, '$.uri') AS artist_uri,
                 json_extract(j.value, '$.name') AS artist_name,
                 MAX(p.played_at) AS last_played
          FROM tracks t
          JOIN plays p ON p.track_uri = t.uri
          CROSS JOIN json_each(t.artists_json) j
          WHERE t.artists_json IS NOT NULL
            AND json_valid(t.artists_json) = 1
          GROUP BY artist_uri
        )
        SELECT COUNT(*)
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
        """, arguments: [
          retryFailedBefore,
          retryLimitedBefore,
          refreshTagsBefore,
          recentCutoff
        ]) ?? 0
    }

    let spotifyCounts = try await Self.stateCounts(dbq: dbq, table: "metadata_enrichment_state", provider: "spotify")
    let lastFMCounts = try await Self.stateCounts(dbq: dbq, table: "tag_enrichment_state", provider: "lastfm")
    let cooldownUntil = await SpotifyRateLimitGate.shared.cooldownUntilDate()

    return EnrichmentBackfillAudit(
      totalTracks: progress.total,
      albumArtTracks: progress.enriched,
      resolvedTrackArtists: progress.trackArtistResolved,
      spotifyArtistTotal: progress.artistTotal,
      spotifyArtistGenres: progress.artistEnriched,
      lastFMArtistTotal: progress.tagArtistTotal,
      lastFMArtistChecked: progress.tagArtistChecked,
      lastFMArtistTagged: progress.tagArtistTagged,
      eligibleTrackBacklog: eligibleTracks,
      eligibleArtistBacklog: eligibleArtists,
      eligibleTagBacklog: eligibleTags,
      spotifyStateCounts: spotifyCounts,
      lastFMStateCounts: lastFMCounts,
      spotifyCooldownUntil: cooldownUntil)
  }

  func run(continuous: Bool, maxAttempts: Int?) async throws {
    let metadata = MetadataEnricher(dbq: dbq, client: client)
    let tagger = lastFMKey.isEmpty ? nil : TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: lastFMKey))
    var remainingAttempts = maxAttempts

    while !Task.isCancelled {
      let before = try await audit()
      logger("audit: \(before.compactSummary)")

      if let wait = before.spotifyCooldownRemaining.nonZero {
        logger("Spotify asked us to cool down for \(Self.duration(wait)); sleeping instead of retry-spamming.")
        try await Task.sleep(nanoseconds: Self.nanoseconds(wait))
        continue
      }

      guard before.hasWork else {
        logger("backfill complete: no eligible enrichment work right now.")
        return
      }

      var attempted = 0

      if before.eligibleTrackBacklog > 0, let cap = nextBatch(max: 80, remaining: remainingAttempts) {
        logger("tracks: attempting \(cap) at 0.20 req/s")
        let count = try await metadata.enrichMissing(rateLimitPerSec: 0.20, limit: cap)
        attempted += count
        remainingAttempts = remainingAttempts.map { max(0, $0 - count) }
      }

      if (remainingAttempts ?? 1) > 0,
         before.eligibleArtistBacklog > 0,
         await SpotifyRateLimitGate.shared.cooldownRemaining() <= 0,
         let cap = nextBatch(max: 40, remaining: remainingAttempts) {
        logger("artists: attempting \(cap) at 0.25 req/s")
        let count = try await metadata.enrichMissingArtists(rateLimitPerSec: 0.25, limit: cap)
        attempted += count
        remainingAttempts = remainingAttempts.map { max(0, $0 - count) }
      }

      if (remainingAttempts ?? 1) > 0,
         before.eligibleTagBacklog > 0,
         let tagger,
         let cap = nextBatch(max: 80, remaining: remainingAttempts) {
        logger("tags: attempting \(cap) at 0.75 req/s")
        let count = try await tagger.enrichMissingArtists(rateLimitPerSec: 0.75, limit: cap)
        attempted += count
        remainingAttempts = remainingAttempts.map { max(0, $0 - count) }
      }

      let after = try await audit()
      logger("after: \(after.compactSummary)")

      if let remainingAttempts, remainingAttempts <= 0 {
        logger("attempt cap reached.")
        return
      }

      if let wait = after.spotifyCooldownRemaining.nonZero {
        logger("Spotify cooldown now active for \(Self.duration(wait)).")
        if !continuous { return }
        try await Task.sleep(nanoseconds: Self.nanoseconds(wait))
      } else if attempted == 0 {
        logger("nothing eligible moved; retry window is probably in the future.")
        if !continuous { return }
        try await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
      } else if !continuous {
        return
      } else {
        try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
      }
    }
  }

  private func nextBatch(max batchSize: Int, remaining: Int?) -> Int? {
    guard let remaining else { return batchSize }
    guard remaining > 0 else { return nil }
    return min(batchSize, remaining)
  }

  private static func stateCounts(
    dbq: DatabaseQueue,
    table: String,
    provider: String
  ) async throws -> [String: Int] {
    try await dbq.read { db in
      let rows = try Row.fetchAll(db, sql: """
        SELECT status, COUNT(*) AS count
        FROM \(table)
        WHERE provider = ?
        GROUP BY status
        """, arguments: [provider])
      return Dictionary(uniqueKeysWithValues: rows.map { row in
        let status: String = row["status"]
        let count: Int = row["count"]
        return (status, count)
      })
    }
  }

  private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64(max(0, seconds) * 1_000_000_000)
  }

  private static func duration(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(Int(ceil(seconds)))s" }
    if seconds < 3600 { return "\(Int(ceil(seconds / 60)))m" }
    return "\(Int(ceil(seconds / 3600)))h"
  }
}

private extension TimeInterval {
  var nonZero: TimeInterval? {
    self > 0 ? self : nil
  }
}
