// Dial/ViewModels/DesktopMemoryContent.swift
import Foundation

/// What the desktop memory object shows (docs/design/desktop-memory.md).
/// Pure, so the content rules are testable without a window: the LCD's
/// first line is the track's memory, or its year-to-date plays when it has
/// none, and the object keeps the last track, dimmed, once playback stops.
struct DesktopMemoryContent: Hashable {
  enum Playback: Hashable {
    case playing
    case paused
    /// Spotify stopped or quit.
    case notPlaying
  }

  /// The LCD's first line.
  enum Stamp: Hashable {
    /// A memory the track-change pop-up would show, worded the same way.
    case memory(kind: BadgeMemoryKind, label: String, line: String)
    /// No memory: how often the track has played this year.
    case yearToDate(plays: Int)
    /// A new track whose memory hasn't loaded yet. Says only what's
    /// certain, so the previous track's memory never shows on it.
    case nowPlaying
    case notPlaying
  }

  struct Track: Hashable {
    let uri: String
    let name: String
    let artistName: String
    let artUrl: String?
  }

  /// What `AggregationsCache` holds for one track.
  struct Aggregates: Equatable {
    let insight: BadgeInsight?
    let playsYTD: Int
    let lastPlayedAt: Int64?
  }

  let playback: Playback
  let stamp: Stamp
  /// The current track, or the last one once playback stops. `nil` only
  /// before Dial has seen a track.
  let track: Track?

  init(playback: Playback, stamp: Stamp, track: Track?) {
    self.playback = playback
    self.stamp = stamp
    self.track = track
  }

  /// - Parameters:
  ///   - aggregates: the memory data for `track`, or `nil` while it's
  ///     still loading (it lands a moment after a new track appears).
  ///   - enabledCategories: the badge families switched on in Settings;
  ///     a hidden badge isn't shown here either.
  ///   - previous: what the object showed before, so a stopped player
  ///     keeps its last track.
  init(
    state: MenubarDisplayState,
    track: NowPlayingViewModel.Track?,
    aggregates: Aggregates?,
    enabledCategories: Set<BadgeCategory>,
    previous: DesktopMemoryContent?,
    calendar: Calendar = .current
  ) {
    guard state != .nothingPlaying, let track else {
      self.init(playback: .notPlaying, stamp: .notPlaying, track: previous?.track)
      return
    }
    let shown = Track(uri: track.uri, name: track.name, artistName: track.artistName, artUrl: track.artUrl)
    let playback: Playback = state == .paused ? .paused : .playing
    guard let aggregates else {
      self.init(playback: playback, stamp: .nowPlaying, track: shown)
      return
    }
    if let memory = MemoryPopupContent(
      insight: aggregates.insight,
      trackName: track.name,
      artistName: track.artistName,
      lastPlayedAt: aggregates.lastPlayedAt,
      enabledCategories: enabledCategories,
      calendar: calendar) {
      self.init(
        playback: playback,
        stamp: .memory(kind: memory.kind, label: memory.label, line: memory.line),
        track: shown)
    } else {
      self.init(playback: playback, stamp: .yearToDate(plays: aggregates.playsYTD), track: shown)
    }
  }

  // MARK: - Lines

  var stampLabel: String {
    switch stamp {
    case let .memory(_, label, _): label
    case .yearToDate: "TRACK · YTD"
    case .nowPlaying: "NOW PLAYING"
    case .notPlaying: "NOT PLAYING"
    }
  }

  /// The LCD's middle line.
  var primaryLine: String? {
    switch stamp {
    case let .memory(_, _, line):
      return line
    case let .yearToDate(plays):
      switch plays {
      case ...0: return "First play this year"
      case 1: return "1 play this year"
      default: return "\(plays.formatted()) plays this year"
      }
    case .nowPlaying, .notPlaying:
      return track?.name
    }
  }

  /// The LCD's last line, who's playing or who played last, longest form
  /// first. The view shows the first form that fits, so a long title drops
  /// the artist instead of ending in "· …".
  var secondaryLines: [String] {
    guard let track else { return [] }
    switch stamp {
    case .nowPlaying, .notPlaying:
      return track.artistName.isEmpty ? [] : [track.artistName]
    case .memory, .yearToDate:
      return track.artistName.isEmpty ? [track.name] : ["\(track.name) · \(track.artistName)", track.name]
    }
  }

  /// "PAUSED" in the LCD's corner; nothing while playing.
  var playbackTag: String? {
    playback == .paused ? "PAUSED" : nil
  }

  var accessibilityLabel: String {
    var parts: [String] = []
    switch stamp {
    case let .memory(kind, _, line):
      parts.append("\(kind.label): \(line).")
    case .yearToDate:
      parts.append("\(primaryLine ?? "").")
    case .nowPlaying:
      parts.append("Now playing.")
    case .notPlaying:
      parts.append("Not playing.")
    }
    if playback == .paused { parts.append("Paused.") }
    if let track {
      parts.append(track.artistName.isEmpty ? track.name : "\(track.name) · \(track.artistName)")
    }
    return parts.joined(separator: " ")
  }
}
