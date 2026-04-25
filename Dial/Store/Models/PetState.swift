// Dial/Store/Models/PetState.swift
import GRDB

enum PetStage: String, Codable, CaseIterable {
  case egg, hatching, hatchling, juvenile, companion, elder
}

struct PetState: Codable, FetchableRecord, PersistableRecord, Equatable {
  var id: Int64 = 1
  var xp: Int64 = 0
  var stage: PetStage = .egg
  var hatchedAt: Int64?
  var lastPlayAt: Int64?
  var streakDays: Int64 = 0
  var streakAnchorDate: String?
  var elderUnlockedAt: Int64?
  var installedAt: Int64

  static let databaseTableName = "pet_state"
}
