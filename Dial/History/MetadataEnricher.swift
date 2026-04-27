// Dial/History/MetadataEnricher.swift
import GRDB
import Foundation
import os.log

private let enricherLog = Logger(subsystem: "com.dial.Dial", category: "MetadataEnricher")

/// Walks every track URI referenced from `plays` whose metadata is incomplete
/// (no row in `tracks` at all, or row exists but `album_art_url` is null) and
/// fetches it from Spotify's `/v1/tracks` endpoint in batches of 50, rate-limited
/// to 5 req/s. Idempotent — running again is a no-op once everything is enriched.
final class MetadataEnricher {
  private let dbq: DatabaseQueue
  private let client: SpotifyClient

  init(dbq: DatabaseQueue, client: SpotifyClient) {
    self.dbq = dbq
    self.client = client
  }

  /// Default rate is 5 req/sec for the public oEmbed endpoint. There's
  /// no documented rate limit but we throttle politely so we don't get
  /// IP-blocked. At 5 req/sec, 49k tracks completes in ~2.7 hours;
  /// recent plays (HistoryView) get art within seconds since the queue
  /// is ordered by `MAX(p.played_at) DESC`.
  ///
  /// **Endpoint choice**: this used to hit `/v1/tracks` (batched, 50
  /// per request, full metadata). Spotify's November 2024 Web API
  /// changes restricted that endpoint to apps in Extended Quota Mode —
  /// Development Mode apps get 403 Forbidden every time. `oembed` is
  /// the only public, unrestricted endpoint that returns album art
  /// without auth. Tradeoffs:
  ///   * No batching (one request per track, slower per-track)
  ///   * Returns title + thumbnail only (no artist URI, no duration)
  ///   * No auth, no rate limit headers, no scope requirements
  /// We accept the per-track cost because it's the only path that
  /// actually works for the user's app under current restrictions.
  ///
  /// `batchSize` is unused (kept in the signature for ABI compatibility
  /// with any callers that pass it explicitly).
  func enrichMissing(batchSize: Int = 50, rateLimitPerSec: Double = 5) async throws {
    enricherLog.notice("enrichMissing started")
    let missing: [String] = try await dbq.read { db in
      // Order by most-recent play DESC so HistoryView's visible rows
      // get album art first; the ~49k-track backfill takes hours, but
      // the recently-played stuff lands within seconds.
      try String.fetchAll(db, sql: """
        SELECT p.track_uri
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.track_uri LIKE 'spotify:track:%'
          AND (t.uri IS NULL OR t.album_art_url IS NULL)
        GROUP BY p.track_uri
        ORDER BY MAX(p.played_at) DESC
      """)
    }
    let total = missing.count
    let nominalDelay = UInt64(1_000_000_000.0 / rateLimitPerSec)
    enricherLog.notice("\(total) missing tracks (oEmbed mode, ~\(Int(Double(total) / rateLimitPerSec))s ETA)")

    var consecutiveFailures = 0

    for (idx, uri) in missing.enumerated() {
      do {
        let oembed = try await client.trackOEmbed(uri: uri)
        try await dbq.write { db in
          // Use mergeUpsert so existing fields (artist URIs from imports,
          // album_name from prior live-poll inserts) aren't clobbered.
          // We only have title + thumbnail to contribute from oEmbed.
          try Track(
            uri: uri,
            name: oembed.title,
            albumName: nil,
            albumArtUrl: oembed.thumbnail_url,
            durationMs: nil,
            artistsJson: nil
          ).mergeUpsert(db)
        }
        consecutiveFailures = 0
        if (idx + 1) % 25 == 0 || idx == 0 {
          enricherLog.notice("track \(idx + 1)/\(total) ok")
        }
      } catch {
        consecutiveFailures += 1
        enricherLog.error("track \(idx + 1)/\(total) (\(uri, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
        // Bail if the endpoint is consistently failing — better to stop
        // than burn through 49k requests at full speed against a wall.
        // Next launch's enrichMissing() will re-attempt.
        if consecutiveFailures >= 20 {
          enricherLog.error("aborting backfill after \(consecutiveFailures) consecutive failures")
          return
        }
      }
      try await Task.sleep(nanoseconds: nominalDelay)
    }
    enricherLog.notice("enrichMissing finished: \(total) tracks attempted")
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
