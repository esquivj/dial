// Dial/Store/Models/Artist.swift
import GRDB

struct Artist: Codable, FetchableRecord, PersistableRecord, Equatable {
  var uri: String
  var name: String?
  var genresJson: String?
  var imageUrl: String?

  static let databaseTableName = "artists"
}
