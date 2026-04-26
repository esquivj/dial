// Dial/Store/Models/Track.swift
import GRDB

struct Track: Codable, FetchableRecord, PersistableRecord, Equatable {
  var uri: String
  var name: String?
  var albumName: String?
  var albumArtUrl: String?
  var durationMs: Int64?
  var artistsJson: String?       // JSON array of {name,uri}

  enum CodingKeys: String, CodingKey {
    case uri
    case name
    case albumName    = "album_name"
    case albumArtUrl  = "album_art_url"
    case durationMs   = "duration_ms"
    case artistsJson  = "artists_json"
  }

  static let databaseTableName = "tracks"

  /// COALESCE-style upsert: insert if the row is new, otherwise only fill
  /// in columns where the new value is non-NULL. Preserves enriched
  /// metadata against partial-data overwrites.
  ///
  /// Why this exists: GRDB's `save()` is INSERT OR REPLACE, which clobbers
  /// the entire row on conflict. The MetadataEnricher fills in album art
  /// / artists / duration for tracks that arrived bare from live polls or
  /// the Streaming History import. Without merge semantics, the next
  /// time the user plays a track, the live-poll path's `try TracksDAO.upsert`
  /// would overwrite all the enriched fields with whatever Spotify's
  /// `currently-playing` happened to return (or NULL where it didn't) —
  /// silently erasing the enricher's work, song by song.
  ///
  /// Used by TracksDAO.upsert, Importer.importBatch, and
  /// MetadataEnricher.enrichMissing to keep the merge contract consistent
  /// across every code path that writes the `tracks` table.
  func mergeUpsert(_ db: Database) throws {
    try db.execute(sql: """
      INSERT INTO tracks (uri, name, album_name, album_art_url, duration_ms, artists_json)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(uri) DO UPDATE SET
        name          = COALESCE(excluded.name,          name),
        album_name    = COALESCE(excluded.album_name,    album_name),
        album_art_url = COALESCE(excluded.album_art_url, album_art_url),
        duration_ms   = COALESCE(excluded.duration_ms,   duration_ms),
        artists_json  = COALESCE(excluded.artists_json,  artists_json)
      """, arguments: [uri, name, albumName, albumArtUrl, durationMs, artistsJson])
  }
}
