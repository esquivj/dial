import Foundation
import Observation
import os.log

private let aggregationsLog = Logger(subsystem: "com.dial.Dial", category: "AggregationsCache")

/// Observable bag of derived readouts for the currently-playing track. Views
/// (dropdown, menubar) read from this; `AppCoordinator` calls `refresh()`
/// whenever the playing track changes or a new play is recorded.
@Observable
final class AggregationsCache {
  var playsYTD: Int = 0
  var rank7d: Int? = nil
  var lastPlayedAt: Int64? = nil
  var firstListen: Bool = false
  var rediscovered: Bool = false
  var onStreak: Bool = false
  var currentBadgeInsight: BadgeInsight?
  var artistRank7d: Int? = nil
  var artistLifetimePlays: Int = 0
  var last60Min: [PlayAggregations.SessionPlay] = []

  private let agg: PlayAggregations
  init(agg: PlayAggregations) { self.agg = agg }

  /// Recompute every derived value for `(trackUri, artistUri)`. Pass `nil`
  /// for both when nothing is playing — leaves all readouts at their defaults
  /// except `last60Min`, which still reflects the rolling hour.
  func refresh(trackUri: String?, artistUri: String?, currentPlayAt: Int64? = nil) {
    do {
      playsYTD     = try trackUri.flatMap { try agg.playsYTD(trackUri: $0) } ?? 0
      rank7d       = try trackUri.flatMap { try agg.rank7d(trackUri: $0) }
      lastPlayedAt = try trackUri.flatMap { try agg.lastPlayedAt(trackUri: $0, before: currentPlayAt) }
      firstListen  = try trackUri.flatMap { try agg.firstListen(trackUri: $0) } ?? false
      rediscovered = try trackUri.flatMap { try agg.rediscovered(trackUri: $0) } ?? false
      onStreak     = try trackUri.flatMap { try agg.onStreak(trackUri: $0) } ?? false
      currentBadgeInsight = try trackUri.flatMap { try agg.currentBadgeInsight(trackUri: $0, currentPlayAt: currentPlayAt) }
      artistRank7d = try artistUri.flatMap { try agg.artistRank7d(artistUri: $0) }
      artistLifetimePlays = try artistUri.flatMap { try agg.artistLifetimePlays(artistUri: $0) } ?? 0
      last60Min    = try agg.last60MinTracks()
    } catch {
      aggregationsLog.error("refresh failed: \(String(describing: error), privacy: .public)")
    }
  }
}
