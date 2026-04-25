// Dial/Store/Models/Track.swift
import GRDB

struct Track: Codable, FetchableRecord, PersistableRecord, Equatable {
  var uri: String
  var name: String?
  var albumName: String?
  var albumArtUrl: String?
  var durationMs: Int64?
  var artistsJson: String?       // JSON array of {name,uri}

  static let databaseTableName = "tracks"
}
