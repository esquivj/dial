import SwiftUI

/// When set, time-driven animations (sprite frames, reaction overlays, the BPM
/// bob) render the single frame for this date instead of following the clock.
/// The app never sets it; visual regression tests do, so snapshots are
/// deterministic.
private struct DialFrozenDateKey: EnvironmentKey {
  static let defaultValue: Date? = nil
}

extension EnvironmentValues {
  var dialFrozenDate: Date? {
    get { self[DialFrozenDateKey.self] }
    set { self[DialFrozenDateKey.self] = newValue }
  }
}
