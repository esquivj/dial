// Dial/LastFM/ScrobbleTracker.swift
import Foundation

/// When a play goes to Last.fm.
///
/// Dial counts a play at 30 s or half the track (`DedupRule`). Last.fm's own
/// rule is stricter: the track must be longer than 30 s, and it must be
/// played for half its length or 4 minutes, whichever comes first. Dial
/// scrobbles only when both hold: the play was recorded as a counted live
/// play, and the playback position has reached Last.fm's point. In practice
/// that means Last.fm's rule decides, because it never passes before
/// Dial's does.
enum LastFMScrobbleRule {
  static let minimumTrackMs = 30_000
  static let fourMinutesMs = 240_000

  static func shouldScrobble(positionMs: Int, durationMs: Int) -> Bool {
    // Unknown length: only the 4-minute half of the rule can be checked.
    guard durationMs > 0 else { return positionMs >= fourMinutesMs }
    guard durationMs > minimumTrackMs else { return false }
    return positionMs >= fourMinutesMs || positionMs * 2 >= durationMs
  }
}

/// Follows the current track and decides when to send "now playing" and
/// when the play is ready to queue. Pure state; `LastFMScrobbler` acts on
/// the returned actions.
struct ScrobbleTracker {
  struct Track: Equatable {
    let uri: String
    let artist: String
    let name: String
    let album: String?
    let durationMs: Int
  }

  struct Candidate: Equatable {
    let playId: Int64
    let track: Track
  }

  enum Action: Equatable {
    case nowPlaying(Track)
    case scrobble(Candidate)
  }

  private(set) var track: Track?
  private var isPlaying = false
  private var nowPlayingSent = false
  private var positionMs = 0
  private var playId: Int64?
  private var queued = false

  mutating func started(_ next: Track) -> [Action] {
    if next.uri != track?.uri {
      positionMs = 0
      playId = nil
      queued = false
      nowPlayingSent = false
    }
    track = next
    return nowPlayingIfDue()
  }

  mutating func progress(_ ms: Int) -> [Action] {
    guard track != nil else { return [] }
    positionMs = ms
    return scrobbleIfDue()
  }

  mutating func paused() {
    isPlaying = false
  }

  mutating func resumed() -> [Action] {
    isPlaying = true
    return nowPlayingIfDue()
  }

  mutating func stopped() {
    track = nil
    isPlaying = false
    playId = nil
    queued = false
    nowPlayingSent = false
    positionMs = 0
  }

  /// Dial recorded this track's play as a counted live play.
  mutating func counted(playId: Int64, uri: String, msPlayed: Int) -> [Action] {
    guard track?.uri == uri, self.playId == nil else { return [] }
    self.playId = playId
    positionMs = max(positionMs, msPlayed)
    return scrobbleIfDue()
  }

  private mutating func nowPlayingIfDue() -> [Action] {
    guard isPlaying, !nowPlayingSent, let track, Self.isScrobbleable(track) else { return [] }
    nowPlayingSent = true
    return [.nowPlaying(track)]
  }

  private mutating func scrobbleIfDue() -> [Action] {
    guard !queued, let track, let playId, Self.isScrobbleable(track),
          LastFMScrobbleRule.shouldScrobble(positionMs: positionMs, durationMs: track.durationMs)
    else { return [] }
    queued = true
    return [.scrobble(Candidate(playId: playId, track: track))]
  }

  /// Music only (catalog tracks and local files, not podcast episodes),
  /// and Last.fm needs an artist and a title.
  private static func isScrobbleable(_ track: Track) -> Bool {
    (track.uri.hasPrefix("spotify:track:") || track.uri.hasPrefix("spotify:local:"))
      && !track.artist.trimmingCharacters(in: .whitespaces).isEmpty
      && !track.name.trimmingCharacters(in: .whitespaces).isEmpty
  }
}
