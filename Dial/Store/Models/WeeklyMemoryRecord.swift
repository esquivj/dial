import Foundation
import GRDB

struct WeeklyMemoryRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Identifiable {
  var weekStart: Int64
  var weekEnd: Int64
  var trait: String
  var memento: String
  var recapLine: String
  var roomObjectName: String
  var dominantGenre: String?
  var theme: DialThemeID
  var playCount: Int
  var listeningMs: Int64
  var uniqueArtists: Int
  var newArtists: Int
  var createdAt: Int64
  var updatedAt: Int64

  var id: Int64 { weekStart }

  init(snapshot: StatsQueries.WeeklyMemorySnapshot, now: Int64) {
    self.weekStart = snapshot.weekStart
    self.weekEnd = snapshot.weekEnd
    self.trait = snapshot.trait
    self.memento = snapshot.memento
    self.recapLine = snapshot.recapLine
    self.roomObjectName = snapshot.roomObjectName
    self.dominantGenre = snapshot.dominantGenre
    self.theme = snapshot.theme
    self.playCount = snapshot.playCount
    self.listeningMs = snapshot.listeningMs
    self.uniqueArtists = snapshot.uniqueArtists
    self.newArtists = snapshot.newArtists
    self.createdAt = now
    self.updatedAt = now
  }

  enum CodingKeys: String, CodingKey {
    case weekStart = "week_start"
    case weekEnd = "week_end"
    case trait
    case memento
    case recapLine = "recap_line"
    case roomObjectName = "room_object_name"
    case dominantGenre = "dominant_genre"
    case theme
    case playCount = "play_count"
    case listeningMs = "listening_ms"
    case uniqueArtists = "unique_artists"
    case newArtists = "new_artists"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  enum Columns {
    static let weekStart = Column("week_start")
    static let weekEnd = Column("week_end")
    static let trait = Column("trait")
    static let memento = Column("memento")
    static let recapLine = Column("recap_line")
    static let roomObjectName = Column("room_object_name")
    static let dominantGenre = Column("dominant_genre")
    static let theme = Column("theme")
    static let playCount = Column("play_count")
    static let listeningMs = Column("listening_ms")
    static let uniqueArtists = Column("unique_artists")
    static let newArtists = Column("new_artists")
    static let createdAt = Column("created_at")
    static let updatedAt = Column("updated_at")
  }

  static let databaseTableName = "weekly_memories"
}

extension StatsQueries.WeeklyMemorySnapshot {
  init(record: WeeklyMemoryRecord) {
    self.init(
      weekStart: record.weekStart,
      weekEnd: record.weekEnd,
      trait: record.trait,
      memento: record.memento,
      recapLine: record.recapLine,
      roomObjectName: record.roomObjectName,
      dominantGenre: record.dominantGenre,
      theme: record.theme,
      playCount: record.playCount,
      listeningMs: record.listeningMs,
      uniqueArtists: record.uniqueArtists,
      newArtists: record.newArtists)
  }
}
