// Dial/History/MetadataEnricher.swift
import GRDB
import Foundation

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

  func enrichMissing(batchSize: Int = 50, rateLimitPerSec: Double = 5) async throws {
    let missing: [String] = try await dbq.read { db in
      // Backfill includes:
      // - Tracks referenced in `plays` with no row in `tracks` at all
      //   (plays recorded before the AppCoordinator track-upsert fix landed)
      // - Tracks with rows but missing `album_art_url`
      // Filter to spotify track URIs only — local files / podcast URIs aren't
      // resolvable via /v1/tracks and would fail the batch.
      try String.fetchAll(db, sql: """
        SELECT DISTINCT p.track_uri
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.track_uri LIKE 'spotify:track:%'
          AND (t.uri IS NULL OR t.album_art_url IS NULL)
      """)
    }
    for chunk in missing.chunked(into: batchSize) {
      let metas = try await client.tracks(uris: chunk)
      try await dbq.write { db in
        for m in metas {
          try Track(
            uri: m.uri,
            name: m.name,
            albumName: m.album.name,
            albumArtUrl: m.album.images.first?.url,
            durationMs: Int64(m.duration_ms),
            artistsJson: try Self.encodeArtists(m.artists)
          ).save(db)
        }
      }
      try await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 / rateLimitPerSec))
    }
  }

  private static func encodeArtists(_ a: [TrackMeta.Artist]) throws -> String {
    struct E: Encodable { let name: String; let uri: String }
    let data = try JSONEncoder().encode(a.map { E(name: $0.name, uri: $0.uri) })
    return String(data: data, encoding: .utf8) ?? "[]"
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
