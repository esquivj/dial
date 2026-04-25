// Dial/Views/PixelSprite/PetSprites.swift
import Foundation

enum PetSprites {
  typealias Grid = [[Int]]

  /// Lookup the sprite grid for a given (stage, behavior). Behavior-specific sprites
  /// are only defined for the `.companion` stage; other stages fall back to their idle.
  static func grid(for stage: PetStage, behavior: PetBehavior) -> Grid {
    let key = SpriteKey(stage: stage, behavior: behavior.canonical)
    return map[key]
        ?? map[SpriteKey(stage: stage, behavior: .idle)]
        ?? idleCompanion
  }

  // MARK: - Stage idles

  static let eggIdle: Grid = grid14(filled: [
    (5, 2, 4, 1), (4, 3, 6, 1), (3, 4, 8, 7), (4, 11, 6, 1), (5, 12, 4, 1)
  ])

  static let hatchingIdle: Grid = grid14(
    filled: [(3, 7, 1, 1), (5, 7, 1, 1), (7, 7, 1, 1), (9, 7, 1, 1),
             (3, 8, 8, 3), (4, 11, 6, 1), (5, 12, 4, 1)],
    dots:   [(5, 4), (8, 3)],
    holes:  [(5, 9, 1, 1), (8, 9, 1, 1)])

  static let hatchlingIdle: Grid = grid14(
    filled: [(4, 3, 6, 1), (3, 4, 8, 6), (4, 10, 6, 1),
             (4, 11, 1, 2), (9, 11, 1, 2)],
    holes:  [(5, 6, 1, 1), (8, 6, 1, 1)])

  static let juvenileIdle: Grid = grid14(
    filled: [(3, 1, 1, 2), (3, 3, 7, 1), (2, 4, 9, 6),
             (3, 10, 2, 2), (8, 10, 2, 2)],
    holes:  [(4, 6, 1, 1), (8, 6, 1, 1), (6, 8, 1, 1)])

  static let idleCompanion: Grid = grid14(
    filled: [(3, 0, 1, 2), (10, 0, 1, 2), (3, 2, 8, 1), (2, 3, 10, 7),
             (3, 10, 8, 1), (3, 11, 2, 2), (9, 11, 2, 2)],
    holes:  [(4, 5, 2, 2), (8, 5, 2, 2), (6, 8, 2, 1)])

  static let elderIdle: Grid = grid14(
    filled: [(2, 0, 1, 2), (11, 0, 1, 2), (2, 2, 10, 1), (1, 3, 12, 8),
             (2, 11, 10, 1), (2, 12, 2, 2), (10, 12, 2, 2)],
    holes:  [(3, 5, 3, 1), (8, 5, 3, 1), (4, 9, 6, 1), (5, 10, 4, 1)])

  // MARK: - Companion behaviors

  static let companionBeatSync: Grid = grid14(
    filled: [(1, 3, 1, 2), (0, 2, 1, 1), (12, 3, 1, 2), (13, 2, 1, 1),
             (3, 1, 1, 2), (10, 1, 1, 2), (3, 3, 8, 1), (2, 4, 10, 6),
             (3, 10, 2, 2), (9, 10, 2, 2)],
    holes:  [(4, 6, 2, 1), (8, 6, 2, 1), (6, 8, 2, 1)])

  static let companionFirstListen: Grid = grid14(
    filled: [(7, 0, 1, 2), (7, 3, 1, 1), (3, 2, 1, 2), (10, 2, 1, 2),
             (3, 4, 8, 1), (2, 5, 10, 6), (3, 11, 2, 2), (9, 11, 2, 2)],
    dots:   [(4, 7), (9, 7)],
    holes:  [(3, 7, 3, 2), (8, 7, 3, 2), (6, 10, 2, 1)])

  static let companionRediscovered: Grid = grid14(
    filled: [(3, 2, 1, 2), (9, 2, 1, 2), (3, 4, 7, 1), (2, 5, 9, 6),
             (3, 11, 2, 2), (8, 11, 2, 2)],
    dots:   [(10, 2), (12, 1), (13, 0), (4, 6), (7, 6)],
    holes:  [(4, 6, 2, 2), (7, 6, 2, 2), (5, 9, 1, 1), (6, 10, 1, 1)])

  static let companionPaused: Grid = grid14(
    filled: [(11, 1, 2, 1), (12, 2, 1, 1), (11, 3, 1, 1), (11, 4, 2, 1),
             (3, 3, 1, 2), (10, 3, 1, 2), (3, 5, 8, 1), (2, 6, 10, 5),
             (3, 11, 8, 2)],
    holes:  [(4, 7, 2, 1), (8, 7, 2, 1), (6, 9, 2, 1)])

  static let companionDormant: Grid = grid14(
    filled: [(1, 9, 3, 3), (4, 8, 7, 4)],
    dots:   [(6, 0), (7, 1), (6, 2), (9, 1), (10, 2), (9, 3), (12, 2), (13, 3), (12, 4)],
    holes:  [(2, 10, 2, 1)])

  static let companionLevelUp: Grid = idleCompanion       // base silhouette; effect layered at view level

  // MARK: - Dispatch map

  struct SpriteKey: Hashable { let stage: PetStage; let behavior: PetBehaviorKey }

  enum PetBehaviorKey: Hashable {
    case idle, beatSync, firstListen, rediscovered, paused, dormant, levelUp
  }

  static let map: [SpriteKey: Grid] = [
    SpriteKey(stage: .egg,       behavior: .idle):          eggIdle,
    SpriteKey(stage: .hatching,  behavior: .idle):          hatchingIdle,
    SpriteKey(stage: .hatchling, behavior: .idle):          hatchlingIdle,
    SpriteKey(stage: .juvenile,  behavior: .idle):          juvenileIdle,
    SpriteKey(stage: .companion, behavior: .idle):          idleCompanion,
    SpriteKey(stage: .elder,     behavior: .idle):          elderIdle,
    SpriteKey(stage: .companion, behavior: .beatSync):      companionBeatSync,
    SpriteKey(stage: .companion, behavior: .firstListen):   companionFirstListen,
    SpriteKey(stage: .companion, behavior: .rediscovered):  companionRediscovered,
    SpriteKey(stage: .companion, behavior: .paused):        companionPaused,
    SpriteKey(stage: .companion, behavior: .dormant):       companionDormant,
    SpriteKey(stage: .companion, behavior: .levelUp):       companionLevelUp,
  ]

  // MARK: - Grid building helpers

  /// Builds a 14×14 sprite from declarative shape descriptors.
  /// `filled`  — `(x, y, width, height)` rectangles painted amber (color 1)
  /// `dots`    — `(x, y)` single amber pixels
  /// `holes`   — `(x, y, width, height)` rectangles cut to transparent (color 0)
  static func grid14(
    filled: [(Int, Int, Int, Int)] = [],
    dots: [(Int, Int)] = [],
    holes: [(Int, Int, Int, Int)] = []
  ) -> Grid {
    var g = Array(repeating: Array(repeating: 0, count: 14), count: 14)
    for (x, y, w, h) in filled where (0..<14).contains(y) && (0..<14).contains(x) {
      for dy in 0..<h where y + dy < 14 {
        for dx in 0..<w where x + dx < 14 {
          g[y + dy][x + dx] = 1
        }
      }
    }
    for (x, y) in dots where (0..<14).contains(x) && (0..<14).contains(y) {
      g[y][x] = 1
    }
    for (x, y, w, h) in holes {
      for dy in 0..<h where y + dy >= 0 && y + dy < 14 {
        for dx in 0..<w where x + dx >= 0 && x + dx < 14 {
          g[y + dy][x + dx] = 0
        }
      }
    }
    return g
  }
}

extension PetBehavior {
  /// Maps the runtime behavior enum onto the legacy pixel-sprite key system.
  /// `walk` and `eating` (introduced for the bulldog renderer) fall back to
  /// `idle` here — the legacy 14×14 pixel renderer doesn't have frames for them.
  var canonical: PetSprites.PetBehaviorKey {
    switch self {
    case .idle, .walk, .eating: .idle
    case .beatSync: .beatSync
    case .firstListen: .firstListen
    case .rediscovered: .rediscovered
    case .paused: .paused
    case .dormant: .dormant
    case .levelUp: .levelUp
    }
  }
}
