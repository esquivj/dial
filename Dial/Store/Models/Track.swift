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
}
