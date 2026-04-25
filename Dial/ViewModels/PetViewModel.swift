// Dial/ViewModels/PetViewModel.swift
import Observation
import GRDB
import Foundation

@Observable
final class PetViewModel {
  var stage: PetStage = .egg
  var xp: Int64 = 0
  var streakDays: Int64 = 0
  var lastPlayAt: Int64? = nil
  var behavior: PetBehavior = .idle
  var currentBPM: Double? = nil
  var justLeveledUp: Bool = false

  /// Reads the persisted pet state and pulls it into the observable view model.
  /// Sets `justLeveledUp` for ~1.2s if the stage advanced — the menubar/dropdown
  /// use this flag to play the level-up animation, then it auto-clears.
  func syncFromStore(dbq: DatabaseQueue) {
    guard let s = try? PetStateDAO(dbq: dbq).get() else { return }
    let wasStage = stage
    stage = s.stage
    xp = s.xp
    streakDays = s.streakDays
    lastPlayAt = s.lastPlayAt
    if wasStage != s.stage {
      justLeveledUp = true
      Task {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        justLeveledUp = false
      }
    }
  }
}
