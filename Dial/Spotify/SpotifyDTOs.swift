// Dial/Spotify/SpotifyDTOs.swift
import Foundation

/// Mirrors the response shape of GET /v1/me/player (and the older
/// /v1/me/player/currently-playing it superseded for our polling). The
/// player-level call gives us shuffle_state and repeat_state too, which
/// /currently-playing doesn't include — so we switched to /me/player.
struct CurrentlyPlaying: Decodable {
  struct Item: Decodable {
    struct Artist: Decodable { let name: String; let uri: String }
    struct Album: Decodable {
      struct Image: Decodable { let url: String }
      let name: String
      let images: [Image]
    }
    let uri: String
    let name: String
    let duration_ms: Int
    let artists: [Artist]
    let album: Album
  }
  let item: Item?
  let is_playing: Bool
  let progress_ms: Int?
  /// Optional because /currently-playing (legacy) didn't return them. With
  /// the switch to /me/player we expect these to populate consistently.
  let shuffle_state: Bool?
  let repeat_state: String?  // "off" | "context" | "track"

  /// Explicit init with defaults for the new fields keeps existing tests
  /// (which construct CurrentlyPlaying directly) compiling without forcing
  /// every fixture to spell out shuffle_state/repeat_state. Decodable
  /// synthesis is unaffected — the field types match.
  init(
    item: Item?,
    is_playing: Bool,
    progress_ms: Int? = nil,
    shuffle_state: Bool? = nil,
    repeat_state: String? = nil
  ) {
    self.item = item
    self.is_playing = is_playing
    self.progress_ms = progress_ms
    self.shuffle_state = shuffle_state
    self.repeat_state = repeat_state
  }
}

struct AudioFeatures: Decodable {
  let tempo: Double      // BPM
}
