import GRDB

struct PetTrickUnlock: Codable, FetchableRecord, PersistableRecord, Equatable, Identifiable {
  var trick: PetTrick
  var unlockedAt: Int64
  var sourceBadge: String?

  var id: PetTrick { trick }

  enum CodingKeys: String, CodingKey {
    case trick
    case unlockedAt = "unlocked_at"
    case sourceBadge = "source_badge"
  }

  static let databaseTableName = "pet_trick_unlocks"
}
