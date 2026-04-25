// Dial/Store/Models/Play.swift
import Foundation
import GRDB

struct Play: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
  var id: Int64?
  var playedAt: Int64      // unix seconds
  var trackUri: String
  var msPlayed: Int64
  var source: String       // "live" | "import"

  enum Columns {
    static let id        = Column("id")
    static let playedAt  = Column("played_at")
    static let trackUri  = Column("track_uri")
    static let msPlayed  = Column("ms_played")
    static let source    = Column("source")
  }
  static let databaseTableName = "plays"
  mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
