// Dial/Pet/PetStageTable.swift
enum PetStageTable {
  /// XP thresholds for each life stage. Listed in ascending order.
  static let thresholds: [(stage: PetStage, xp: Int64)] = [
    (.egg,        0),
    (.hatching,   500),
    (.hatchling,  1_000),
    (.juvenile,   5_000),
    (.companion,  25_000),
    (.elder,      100_000)
  ]

  /// Resolves the stage for `xp`. If `elderUnlocked` is false, caps at `companion`
  /// even if XP would qualify for `elder` — the elder stage is gated behind 30
  /// calendar days of live use (see `PetEngine.installedAt`).
  static func stage(forXP xp: Int64, elderUnlocked: Bool = true) -> PetStage {
    var out: PetStage = .egg
    for (stage, threshold) in thresholds where xp >= threshold { out = stage }
    if out == .elder, !elderUnlocked { return .companion }
    return out
  }
}
