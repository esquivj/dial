import Foundation
import Observation

/// Observable bag of derived readouts for the currently-playing track. Views
/// (dropdown, menubar) read from this; `AppCoordinator` calls `refresh()`
/// whenever the playing track changes or a new play is recorded.
@Observable
final class AggregationsCache {
  var plays30d: Int = 0
  var rank7d: Int? = nil
  var firstListen: Bool = false
  var rediscovered: Bool = false
  var onStreak: Bool = false
  var artistRank7d: Int? = nil
  var last60Min: [PlayAggregations.SessionPlay] = []

  private let agg: PlayAggregations
  init(agg: PlayAggregations) { self.agg = agg }

  /// Recompute every derived value for `(trackUri, artistUri)`. Pass `nil`
  /// for both when nothing is playing — leaves all readouts at their defaults
  /// except `last60Min`, which still reflects the rolling hour.
  func refresh(trackUri: String?, artistUri: String?) {
    do {
      plays30d     = try trackUri.flatMap { try agg.plays30d(trackUri: $0) } ?? 0
      rank7d       = try trackUri.flatMap { try agg.rank7d(trackUri: $0) }
      firstListen  = try trackUri.flatMap { try agg.firstListen(trackUri: $0) } ?? false
      rediscovered = try trackUri.flatMap { try agg.rediscovered(trackUri: $0) } ?? false
      onStreak     = try trackUri.flatMap { try agg.onStreak(trackUri: $0) } ?? false
      artistRank7d = try artistUri.flatMap { try agg.artistRank7d(artistUri: $0) }
      last60Min    = try agg.last60MinTracks()
    } catch {
      print("[AggregationsCache] refresh failed: \(error)")
    }
  }
}
