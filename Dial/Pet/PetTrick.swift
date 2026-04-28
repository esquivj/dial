import Foundation

enum PetTrick: String, Codable, CaseIterable, Hashable {
  case sparkStep = "spark_step"
  case memorySpin = "memory_spin"
  case beatBounce = "beat_bounce"

  var label: String {
    switch self {
    case .sparkStep: return "Spark Step"
    case .memorySpin: return "Memory Spin"
    case .beatBounce: return "Beat Bounce"
    }
  }

  var shortLabel: String {
    switch self {
    case .sparkStep: return "Spark"
    case .memorySpin: return "Memory"
    case .beatBounce: return "Bounce"
    }
  }

  var description: String {
    switch self {
    case .sparkStep: return "A tiny celebration move for discovery runs."
    case .memorySpin: return "A recall move for rediscovered tracks."
    case .beatBounce: return "A rhythm move for active listening sessions."
    }
  }

  var displayBehavior: PetBehavior {
    switch self {
    case .sparkStep: return .sparkStep
    case .memorySpin: return .memorySpin
    case .beatBounce: return .beatBounce
    }
  }

  static func nextLocked(unlocked: [PetTrick]) -> PetTrick? {
    let unlockedSet = Set(unlocked)
    return allCases.first { !unlockedSet.contains($0) }
  }
}
