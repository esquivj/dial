// Dial/Store/Models/BadgeEvent.swift
import Foundation
import GRDB

enum BadgeCategory: String, Codable, CaseIterable {
  case discovery
  case pattern
  case milestone

  var label: String {
    switch self {
    case .discovery: return "Discovery"
    case .pattern: return "Pattern"
    case .milestone: return "Milestone"
    }
  }
}

enum BadgeMemoryKind: String, Codable, CaseIterable {
  case firstListen = "first_listen"
  case newArtist = "new_artist"
  case rediscovered
  case deepCut = "deep_cut"
  case onStreak = "on_streak"
  case repeatTrack = "repeat_track"
  case albumMode = "album_mode"
  case play10 = "play_10"
  case play50 = "play_50"
  case play100 = "play_100"
  case anniversary

  var label: String {
    switch self {
    case .firstListen: return "First listen"
    case .newArtist: return "New artist"
    case .rediscovered: return "Rediscovered"
    case .deepCut: return "Deep cut"
    case .onStreak: return "On streak"
    case .repeatTrack: return "Repeat"
    case .albumMode: return "Album mode"
    case .play10: return "10th play"
    case .play50: return "50th play"
    case .play100: return "100th play"
    case .anniversary: return "Anniversary"
    }
  }

  var category: BadgeCategory {
    switch self {
    case .firstListen, .newArtist, .rediscovered, .deepCut:
      return .discovery
    case .onStreak, .repeatTrack, .albumMode:
      return .pattern
    case .play10, .play50, .play100, .anniversary:
      return .milestone
    }
  }
}

struct BadgeInsight: Equatable {
  let kind: BadgeMemoryKind
  let detail: String
}

struct BadgeEvent: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
  var id: Int64?
  var kind: BadgeMemoryKind
  var category: BadgeCategory
  var trackUri: String?
  var artistUri: String?
  var albumName: String?
  var earnedAt: Int64
  var payloadJson: String?
  var scopeKey: String

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case category
    case trackUri = "track_uri"
    case artistUri = "artist_uri"
    case albumName = "album_name"
    case earnedAt = "earned_at"
    case payloadJson = "payload_json"
    case scopeKey = "scope_key"
  }

  enum Columns {
    static let id = Column("id")
    static let kind = Column("kind")
    static let category = Column("category")
    static let trackUri = Column("track_uri")
    static let artistUri = Column("artist_uri")
    static let albumName = Column("album_name")
    static let earnedAt = Column("earned_at")
    static let payloadJson = Column("payload_json")
    static let scopeKey = Column("scope_key")
  }

  static let databaseTableName = "badge_events"

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
