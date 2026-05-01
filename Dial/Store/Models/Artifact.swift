import Foundation
import GRDB

enum ArtifactSource: String, Codable {
  case badge
  case trick
  case weeklyMemory = "weekly_memory"
}

enum ArtifactKind: String, Codable, CaseIterable, Identifiable {
  case firstListenSpark = "first_listen_spark"
  case newArtistToken = "new_artist_token"
  case rediscoveredCassette = "rediscovered_cassette"
  case deepCutGem = "deep_cut_gem"
  case streakFlame = "streak_flame"
  case repeatLoop = "repeat_loop"
  case albumStack = "album_stack"
  case play10Trophy = "play_10_trophy"
  case play50Trophy = "play_50_trophy"
  case play100Trophy = "play_100_trophy"
  case anniversaryRelic = "anniversary_relic"
  case beatBounceCharm = "beat_bounce_charm"
  case moonlitTape = "moonlit_tape"
  case signalCube = "signal_cube"
  case repeatCharm = "repeat_charm"
  case freshSticker = "fresh_sticker"
  case softLamp = "soft_lamp"
  case blownSpeaker = "blown_speaker"
  case shelfSticker = "shelf_sticker"
  case listeningCrate = "listening_crate"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .firstListenSpark: return "First Spark"
    case .newArtistToken: return "New Artist"
    case .rediscoveredCassette: return "Cassette"
    case .deepCutGem: return "Deep Gem"
    case .streakFlame: return "Streak Flame"
    case .repeatLoop: return "Repeat Loop"
    case .albumStack: return "Album Stack"
    case .play10Trophy: return "10 Play"
    case .play50Trophy: return "50 Play"
    case .play100Trophy: return "100 Play"
    case .anniversaryRelic: return "Anniversary"
    case .beatBounceCharm: return "Beat Charm"
    case .moonlitTape: return "Moonlit Tape"
    case .signalCube: return "Signal Cube"
    case .repeatCharm: return "Repeat Charm"
    case .freshSticker: return "Fresh Sticker"
    case .softLamp: return "Soft Lamp"
    case .blownSpeaker: return "Blown Speaker"
    case .shelfSticker: return "Shelf Sticker"
    case .listeningCrate: return "Listening Crate"
    }
  }

  var assetName: String {
    switch self {
    case .moonlitTape:
      "rediscovered_cassette"
    case .signalCube:
      "deep_cut_gem"
    case .repeatCharm:
      "repeat_loop"
    case .freshSticker:
      "new_artist_token"
    case .softLamp:
      "first_listen_spark"
    case .blownSpeaker:
      "album_stack"
    case .shelfSticker:
      "new_artist_token"
    case .listeningCrate:
      "album_stack"
    default:
      rawValue
    }
  }

  init?(badgeKind: BadgeMemoryKind) {
    switch badgeKind {
    case .firstListen: self = .firstListenSpark
    case .newArtist: self = .newArtistToken
    case .rediscovered: self = .rediscoveredCassette
    case .deepCut: self = .deepCutGem
    case .onStreak: self = .streakFlame
    case .repeatTrack: self = .repeatLoop
    case .albumMode: self = .albumStack
    case .play10: self = .play10Trophy
    case .play50: self = .play50Trophy
    case .play100: self = .play100Trophy
    case .anniversary: self = .anniversaryRelic
    }
  }

  init?(trick: PetTrick) {
    switch trick {
    case .beatBounce:
      self = .beatBounceCharm
    case .sparkStep:
      self = .firstListenSpark
    case .memorySpin:
      self = .rediscoveredCassette
    }
  }

  init?(memento: String) {
    switch memento {
    case "Moonlit Tape":
      self = .moonlitTape
    case "Signal Cube":
      self = .signalCube
    case "Repeat Charm":
      self = .repeatCharm
    case "Fresh Sticker":
      self = .freshSticker
    case "Soft Lamp":
      self = .softLamp
    case "Blown Speaker":
      self = .blownSpeaker
    case "Shelf Sticker":
      self = .shelfSticker
    case "Listening Crate":
      self = .listeningCrate
    default:
      return nil
    }
  }
}

struct Artifact: Codable, FetchableRecord, PersistableRecord, Equatable, Identifiable {
  var kind: ArtifactKind
  var source: ArtifactSource
  var unlockedAt: Int64
  var sourceBadgeEventId: Int64?
  var trackUri: String?
  var artistUri: String?
  var detail: String?
  var sourceWeekStart: Int64? = nil

  var id: ArtifactKind { kind }

  enum CodingKeys: String, CodingKey {
    case kind
    case source
    case unlockedAt = "unlocked_at"
    case sourceBadgeEventId = "source_badge_event_id"
    case trackUri = "track_uri"
    case artistUri = "artist_uri"
    case detail
    case sourceWeekStart = "source_week_start"
  }

  enum Columns {
    static let kind = Column("kind")
    static let source = Column("source")
    static let unlockedAt = Column("unlocked_at")
    static let sourceBadgeEventId = Column("source_badge_event_id")
    static let trackUri = Column("track_uri")
    static let artistUri = Column("artist_uri")
    static let detail = Column("detail")
    static let sourceWeekStart = Column("source_week_start")
  }

  static let databaseTableName = "artifacts"
}
