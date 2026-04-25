// Dial/Pet/PetBehavior.swift
import Foundation

enum PetBehavior: Equatable {
  case idle
  case walk                  // ambient 2-frame loop while music plays (no BPM)
  case beatSync(bpm: Double) // beat-driven bob, when BPM is known
  case firstListen
  case rediscovered
  case eating                // brief animation triggered by a counted play
  case paused
  case dormant
  case levelUp
}

struct PetContext {
  let playing: Bool
  let paused: Bool
  let firstListen: Bool
  let rediscovered: Bool
  let eating: Bool           // true for ~600ms after a counted play
  let leveledUp: Bool
  let lastPlayAt: Int64?
  let now: Int64
  let bpm: Double?
}

enum PetBehaviorResolver {
  /// Priority (highest first):
  ///   levelUp > firstListen > rediscovered > eating > paused > dormant
  ///         > beatSync > walk > idle
  ///
  /// `walk` is the new default while music is playing without known BPM —
  /// keeps the pet moving so it never sits still mid-track.
  static func resolve(_ c: PetContext) -> PetBehavior {
    if c.leveledUp { return .levelUp }
    if c.firstListen { return .firstListen }
    if c.rediscovered { return .rediscovered }
    if c.eating { return .eating }
    if c.paused { return .paused }
    if let lp = c.lastPlayAt, c.now - lp >= 7 * 86_400 { return .dormant }
    if c.playing { return c.bpm.map(PetBehavior.beatSync) ?? .walk }
    return .idle
  }
}
