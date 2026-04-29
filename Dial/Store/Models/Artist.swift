// Dial/Store/Models/Artist.swift
import GRDB

struct Artist: Codable, FetchableRecord, PersistableRecord, Equatable {
  var uri: String
  var name: String?
  var genresJson: String?
  var imageUrl: String?

  enum CodingKeys: String, CodingKey {
    case uri
    case name
    case genresJson = "genres_json"
    case imageUrl   = "image_url"
  }

  static let databaseTableName = "artists"

  /// Merge-style upsert for fetched Spotify artist metadata. Empty genre arrays
  /// are stored as `"[]"` so Dial knows the artist was checked and does not
  /// refetch the same empty result every launch.
  func mergeUpsert(_ db: Database) throws {
    try db.execute(sql: """
      INSERT INTO artists (uri, name, genres_json, image_url)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(uri) DO UPDATE SET
        name        = COALESCE(excluded.name,        name),
        genres_json = COALESCE(excluded.genres_json, genres_json),
        image_url   = COALESCE(excluded.image_url,   image_url)
      """, arguments: [uri, name, genresJson, imageUrl])
  }
}
