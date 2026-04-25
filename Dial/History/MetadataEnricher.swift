// Dial/History/MetadataEnricher.swift
import GRDB
import Foundation

/// After import, walks tracks that have no `album_art_url` and fetches metadata
/// from Spotify's `/v1/tracks` endpoint in batches of 50, rate-limited to 5 req/s.
/// Idempotent — running again is a no-op once everything is enriched.
final class MetadataEnricher {
  private let dbq: DatabaseQueue
  private let client: SpotifyClient

  init(dbq: DatabaseQueue, client: SpotifyClient) {
    self.dbq = dbq
    self.client = client
  }

  func enrichMissing(batchSize: Int = 50, rateLimitPerSec: Double = 5) async throws {
    let missing: [String] = try await dbq.read { db in
      try String.fetchAll(db,
        sql: "SELECT t.uri FROM tracks t WHERE t.album_art_url IS NULL")
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
