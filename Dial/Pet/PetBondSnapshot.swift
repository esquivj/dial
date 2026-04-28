import Foundation

struct PetBondInputs: Equatable {
  let xp: Int64
  let streakDays: Int64
  let playsYTDForCurrentTrack: Int
  let playbackState: MenubarDisplayState
  let todayListeningMs: Int64
  let recentBadgeCounts: [BadgeCategory: Int]
  let currentBadge: BadgeInsight?
  let currentTrackName: String?
  let unlockedTricks: [PetTrick]
}

enum PetBondPrimaryAction: Equatable {
  case rememberThis
  case teachTrick(PetTrick)
  case wakeUp
  case showFavorite
  case showTrick(PetTrick)
  case syncToBeat
  case checkIn

  var label: String {
    switch self {
    case .rememberThis: return "REMEMBER THIS"
    case .teachTrick(let trick): return "TEACH \(trick.shortLabel.uppercased())"
    case .wakeUp: return "WAKE UP"
    case .showFavorite: return "SHOW FAVORITE"
    case .showTrick(let trick): return "SHOW \(trick.shortLabel.uppercased())"
    case .syncToBeat: return "SYNC"
    case .checkIn: return "CHECK IN"
    }
  }
}

struct PetBondSnapshot: Equatable {
  let bondScore: Double
  let discoveryScore: Double
  let energyScore: Double
  let moodLabel: String
  let reason: String
  let primaryAction: PetBondPrimaryAction

  static func make(_ input: PetBondInputs) -> PetBondSnapshot {
    let xpScore = clamp(Double(input.xp) / 25_000)
    let streakScore = clamp(Double(input.streakDays) / 14)
    let repeatScore = clamp(Double(input.playsYTDForCurrentTrack) / 12)
    let bondScore = clamp((xpScore * 0.58) + (streakScore * 0.26) + (repeatScore * 0.16))

    let recentDiscovery = input.recentBadgeCounts[.discovery, default: 0]
    let recentMilestones = input.recentBadgeCounts[.milestone, default: 0]
    let currentDiscoveryBoost = input.currentBadge?.kind.category == .discovery ? 0.35 : 0
    let discoveryScore = clamp(
      (Double(recentDiscovery) / 6) +
      (Double(recentMilestones) / 18) +
      currentDiscoveryBoost)

    let todayMinutes = Double(input.todayListeningMs) / 60_000
    let listeningScore = clamp(todayMinutes / 90)
    let energyScore: Double = switch input.playbackState {
    case .playing:
      clamp((listeningScore * 0.75) + 0.25)
    case .paused:
      clamp((listeningScore * 0.65) + 0.05)
    case .nothingPlaying:
      clamp(listeningScore * 0.45)
    }

    let action = primaryAction(
      bondScore: bondScore,
      discoveryScore: discoveryScore,
      energyScore: energyScore,
      playbackState: input.playbackState,
      currentBadge: input.currentBadge,
      unlockedTricks: input.unlockedTricks)
    let mood = mood(
      bondScore: bondScore,
      discoveryScore: discoveryScore,
      energyScore: energyScore,
      playbackState: input.playbackState,
      currentBadge: input.currentBadge)
    let reason = reason(
      for: mood,
      trackName: input.currentTrackName,
      currentBadge: input.currentBadge,
      todayMinutes: todayMinutes)

    return PetBondSnapshot(
      bondScore: bondScore,
      discoveryScore: discoveryScore,
      energyScore: energyScore,
      moodLabel: mood,
      reason: reason,
      primaryAction: action)
  }

  private static func primaryAction(
    bondScore: Double,
    discoveryScore: Double,
    energyScore: Double,
    playbackState: MenubarDisplayState,
    currentBadge: BadgeInsight?,
    unlockedTricks: [PetTrick]
  ) -> PetBondPrimaryAction {
    if currentBadge != nil { return .rememberThis }
    if discoveryScore >= 0.85, let trick = PetTrick.nextLocked(unlocked: unlockedTricks) {
      return .teachTrick(trick)
    }
    if energyScore < 0.22 { return .wakeUp }
    if let trick = unlockedTricks.first, playbackState == .playing { return .showTrick(trick) }
    if bondScore >= 0.82 { return .showFavorite }
    if playbackState == .playing { return .syncToBeat }
    return .checkIn
  }

  private static func mood(
    bondScore: Double,
    discoveryScore: Double,
    energyScore: Double,
    playbackState: MenubarDisplayState,
    currentBadge: BadgeInsight?
  ) -> String {
    if let currentBadge { return currentBadge.kind.label }
    if energyScore < 0.22 { return "Low power" }
    if discoveryScore >= 0.85 { return "Curious" }
    if bondScore >= 0.82 { return "Bonded" }
    if playbackState == .playing { return "In rhythm" }
    if playbackState == .paused { return "Holding pattern" }
    return "Quiet"
  }

  private static func reason(
    for mood: String,
    trackName: String?,
    currentBadge: BadgeInsight?,
    todayMinutes: Double
  ) -> String {
    if let currentBadge {
      return "\(currentBadge.kind.label): \(currentBadge.detail)"
    }

    switch mood {
    case "Low power":
      return "Music has been quiet today."
    case "Curious":
      return "Recent badges are pushing discovery up."
    case "Bonded":
      return trackName.map { "Strong history with \($0)." } ?? "Your listening history is strong."
    case "In rhythm":
      return trackName.map { "Moving with \($0)." } ?? "Playback is active."
    case "Holding pattern":
      return "Paused, but today's session still counts."
    default:
      let minutes = Int(todayMinutes.rounded())
      return minutes > 0 ? "\(minutes) min logged today." : "Waiting for the first play today."
    }
  }

  private static func clamp(_ value: Double) -> Double {
    min(1, max(0, value))
  }
}
