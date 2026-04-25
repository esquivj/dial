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
}
