// Dial/Pet/XPFormula.swift
import Foundation

enum VarietyBonus { case none, newAlbum, newArtist }

enum XPFormula {
  /// XP awarded for a single qualified play.
  ///
  /// `base = ms_played / 60_000`  (1 XP per minute)
  /// `variety = +50 newArtist | +25 newAlbum | 0`
  /// `streak multiplier = 1 + (streakDays - 2) * 0.25`, active when streakDays ≥ 3, capped at 2.0.
  /// Result: `(base + variety) * mult`, truncated to Int64.
  static func compute(msPlayed: Int64, variety: VarietyBonus, streakDays: Int64) -> Int64 {
    let base = Double(msPlayed) / 60_000.0
    let varietyXP: Double = switch variety {
      case .none:      0
      case .newAlbum:  25
      case .newArtist: 50
    }
    let mult: Double = streakDays < 3 ? 1.0 : min(1 + Double(streakDays - 2) * 0.25, 2.0)
    return Int64((base + varietyXP) * mult)
  }
}
