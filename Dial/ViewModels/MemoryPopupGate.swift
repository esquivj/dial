// Dial/ViewModels/MemoryPopupGate.swift
import Foundation

/// What the track-change pop-up says. Only real memories produce one:
/// discoveries and milestones. Streaks, repeats and album runs describe
/// the current session, not a memory, so they stay in the HUD.
struct MemoryPopupContent: Equatable {
  let kind: BadgeMemoryKind
  let label: String
  let line: String
  let trackName: String
  let artistName: String

  static let popupKinds: Set<BadgeMemoryKind> = [
    .firstListen, .newArtist, .rediscovered, .deepCut,
    .play10, .play50, .play100, .anniversary,
  ]

  /// - Parameters:
  ///   - lastPlayedAt: the previous play of this track (unix seconds), used
  ///     to say when a rediscovered track was last heard.
  ///   - enabledCategories: the badge families the user has switched on in
  ///     Settings; a hidden badge never pops up either.
  init?(
    insight: BadgeInsight?,
    trackName: String,
    artistName: String,
    lastPlayedAt: Int64?,
    enabledCategories: Set<BadgeCategory>,
    calendar: Calendar = .current
  ) {
    guard let insight,
          Self.popupKinds.contains(insight.kind),
          enabledCategories.contains(insight.kind.category),
          !trackName.isEmpty
    else { return nil }
    self.kind = insight.kind
    self.label = insight.kind.label.uppercased()
    self.trackName = trackName
    self.artistName = artistName
    self.line = Self.line(for: insight, lastPlayedAt: lastPlayedAt, calendar: calendar)
  }

  init(kind: BadgeMemoryKind, label: String, line: String, trackName: String, artistName: String) {
    self.kind = kind
    self.label = label
    self.line = line
    self.trackName = trackName
    self.artistName = artistName
  }

  /// Short enough to sit next to the stamp on one 300pt LCD line.
  private static func line(for insight: BadgeInsight, lastPlayedAt: Int64?, calendar: Calendar) -> String {
    switch insight.kind {
    case .rediscovered:
      guard let lastPlayedAt else { return insight.detail }
      var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated).year()
      style.calendar = calendar
      style.timeZone = calendar.timeZone
      return "Last played \(Date(timeIntervalSince1970: TimeInterval(lastPlayedAt)).formatted(style))"
    case .firstListen:
      return "New to your history"
    case .newArtist:
      return "First time hearing them"
    case .deepCut:
      return "Rare track, familiar artist"
    case .anniversary:
      return "Played on this day before"
    case .play10, .play50, .play100:
      return insight.detail
    case .onStreak, .repeatTrack, .albumMode:
      return insight.detail
    }
  }
}

/// Decides whether a memory pop-up shows. Pure so the rules are testable:
///
/// - at most one decision per track play: once a track has had its chance
///   (shown or skipped), nothing else pops up until the next track starts;
/// - when the track starts, any pop-up memory can show;
/// - when the play counts (~30 s in), only milestones and anniversaries can,
///   because those only become true once the play is in the archive;
/// - never while the toggle is off, the HUD is open, or a Focus is on.
struct MemoryPopupGate {
  enum Moment {
    case trackStarted
    case playCounted
  }

  struct Conditions: Equatable {
    var enabled: Bool
    var hudOpen: Bool
    var focusActive: Bool
  }

  private(set) var trackUri: String?
  private(set) var decided = false

  mutating func trackStarted(uri: String?) {
    trackUri = uri
    decided = false
  }

  mutating func decide(
    uri: String,
    content: MemoryPopupContent?,
    moment: Moment,
    conditions: Conditions
  ) -> MemoryPopupContent? {
    guard uri == trackUri, !decided, let content else { return nil }
    if moment == .playCounted, content.kind.category != .milestone { return nil }
    decided = true
    guard conditions.enabled, !conditions.hudOpen, !conditions.focusActive else { return nil }
    return content
  }
}

/// Where the coordinator sends a pop-up. `StatusBarController` implements
/// it because it owns the status item position and the HUD panel.
protocol MemoryPopupPresenting: AnyObject {
  var isHUDOpen: Bool { get }
  func presentMemoryPopup(_ content: MemoryPopupContent, theme: DialTheme)
}

protocol FocusStatusProviding {
  /// True while a Focus (including Do Not Disturb) is on.
  var isFocusActive: Bool { get }
}

/// What Dial's Focus filter last told it. `DialFocusFilter.perform()`
/// writes here when a Focus with the filter turns on or off. Lives in
/// UserDefaults because the system may launch Dial just to run the filter.
struct FocusFilterState {
  static let hidesMemoryPopupsKey = "focusFilterHidesMemoryPopups"

  var defaults: UserDefaults = .standard

  var hidesMemoryPopups: Bool { defaults.bool(forKey: Self.hidesMemoryPopupsKey) }

  /// `nil` is what the system passes when the Focus turns off (the filter's
  /// parameter goes back to its unset default), so only `true` hides pop-ups.
  func apply(hideMemoryPopups: Bool?) {
    defaults.set(hideMemoryPopups == true, forKey: Self.hidesMemoryPopupsKey)
  }
}

/// Reports a Focus as on while a Focus that has Dial's filter (System
/// Settings › Focus › Focus filters) is on. macOS has no other way to tell
/// this build about Focus: `INFocusStatusCenter` needs the restricted
/// Communication Notifications entitlement, which the self-signed
/// "Dial Local Dev" build can't carry, and ~/Library/DoNotDisturb is
/// privacy-protected. A Focus without the filter is invisible to Dial.
struct SystemFocusStatus: FocusStatusProviding {
  var state = FocusFilterState()
  var isFocusActive: Bool { state.hidesMemoryPopups }
}
