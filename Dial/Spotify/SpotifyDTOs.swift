// Dial/Spotify/SpotifyDTOs.swift
import Foundation

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
}

struct AudioFeatures: Decodable {
  let tempo: Double      // BPM
}
