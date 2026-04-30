// Dial/Pet/PetBehavior.swift
import Foundation

enum PetBehavior: Equatable {
  case idle
  case walk                  // ambient 2-frame loop while music plays (no BPM)
  case beatSync(bpm: Double) // beat-driven bob, when BPM is known
  case expressed(PetExpression, motion: PetMotion)
  case sparkStep
  case memorySpin
  case beatBounce
  case firstListen
  case rediscovered
  case eating                // brief animation triggered by a counted play
  case paused
  case dormant
  case levelUp
}

enum PetMotion: Equatable {
  case idle
  case walk
  case beatSync(bpm: Double)

  var behavior: PetBehavior {
    switch self {
    case .idle: return .idle
    case .walk: return .walk
    case let .beatSync(bpm): return .beatSync(bpm: bpm)
    }
  }
}

enum PetExpression: Equatable {
  case firstListen
  case rediscovered
  case levelUp
}

struct PetContext {
  let playing: Bool
  let paused: Bool
  let firstListen: Bool
  let rediscovered: Bool
  let eating: Bool           // true for ~600ms after a counted play
  let leveledUp: Bool
  let ambientTrick: PetBehavior?
  let lastPlayAt: Int64?
  let now: Int64
  let bpm: Double?
}

enum PetBehaviorResolver {
  /// Priority (highest first):
  ///   levelUp expression > firstListen expression > rediscovered expression
  ///     > eating > ambient trick > paused > dormant > beatSync > walk > idle
  ///
  /// `walk` is the new default while music is playing without known BPM —
  /// keeps the pet moving so it never sits still mid-track.
  static func resolve(_ c: PetContext) -> PetBehavior {
    let motion = activeMotion(c)
    if c.leveledUp { return .expressed(.levelUp, motion: motion) }
    if c.firstListen { return .expressed(.firstListen, motion: motion) }
    if c.rediscovered { return .expressed(.rediscovered, motion: motion) }
    if c.eating { return .eating }
    if let ambientTrick = c.ambientTrick { return ambientTrick }
    if c.paused { return .paused }
    if let lp = c.lastPlayAt, c.now - lp >= 7 * 86_400 { return .dormant }
    return motion.behavior
  }

  private static func activeMotion(_ c: PetContext) -> PetMotion {
    guard c.playing else { return .idle }
    if let bpm = c.bpm { return .beatSync(bpm: bpm) }
    return .walk
  }
}
