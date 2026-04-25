// Dial/Pet/PetBehavior.swift
import Foundation

enum PetBehavior: Equatable {
  case idle
  case beatSync(bpm: Double)
  case firstListen
  case rediscovered
  case paused
  case dormant
  case levelUp
}

struct PetContext {
  let playing: Bool
  let paused: Bool
  let firstListen: Bool
  let rediscovered: Bool
  let leveledUp: Bool
  let lastPlayAt: Int64?
  let now: Int64
  let bpm: Double?
}

enum PetBehaviorResolver {
  /// Priority: levelUp > firstListen > rediscovered > paused > dormant > beatSync > idle.
  static func resolve(_ c: PetContext) -> PetBehavior {
    if c.leveledUp { return .levelUp }
    if c.firstListen { return .firstListen }
    if c.rediscovered { return .rediscovered }
    if c.paused { return .paused }
    if let lp = c.lastPlayAt, c.now - lp >= 7 * 86_400 { return .dormant }
    if c.playing { return c.bpm.map(PetBehavior.beatSync) ?? .idle }
    return .idle
  }
}
