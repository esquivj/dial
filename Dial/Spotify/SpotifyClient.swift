// Dial/Spotify/SpotifyClient.swift
import Foundation

final class SpotifyClient {
  private let session: URLSession
  private let tokenStore: TokenStore
  private let refresh: () async throws -> SpotifyToken

  init(session: URLSession = .shared,
       tokenStore: TokenStore,
       refresh: @escaping () async throws -> SpotifyToken) {
    self.session = session
    self.tokenStore = tokenStore
    self.refresh = refresh
  }

  /// Authed GET that auto-refreshes once on 401.
  fileprivate func authedGET(_ url: URL, retryOn401: Bool = true) async throws -> (Data, HTTPURLResponse) {
    let token = try tokenStore.load()
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await session.data(for: req)
    let http = resp as! HTTPURLResponse
    if http.statusCode == 401, retryOn401 {
      _ = try await refresh()
      return try await authedGET(url, retryOn401: false)
    }
    return (data, http)
  }

  func currentlyPlaying() async throws -> CurrentlyPlaying? {
    let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
    let (data, http) = try await authedGET(url)
    if http.statusCode == 204 { return nil }
    return try JSONDecoder().decode(CurrentlyPlaying.self, from: data)
  }

  func audioFeatures(trackId: String) async throws -> AudioFeatures {
    let url = URL(string: "https://api.spotify.com/v1/audio-features/\(trackId)")!
    let (data, _) = try await authedGET(url)
    return try JSONDecoder().decode(AudioFeatures.self, from: data)
  }
}

// MARK: - Batch tracks

struct TrackMeta: Decodable {
  let uri: String
  let name: String
  let duration_ms: Int
  struct Artist: Decodable { let name: String; let uri: String }
  struct Album: Decodable {
    let name: String
    struct Img: Decodable { let url: String }
    let images: [Img]
  }
  let artists: [Artist]
  let album: Album
}

extension SpotifyClient {
  /// Fetches up to 50 tracks per call. Callers should batch > 50 externally.
  func tracks(uris: [String]) async throws -> [TrackMeta] {
    let ids = uris
      .map { $0.replacingOccurrences(of: "spotify:track:", with: "") }
      .joined(separator: ",")
    let url = URL(string: "https://api.spotify.com/v1/tracks?ids=\(ids)")!
    let (data, _) = try await authedGET(url)
    struct R: Decodable { let tracks: [TrackMeta] }
    return try JSONDecoder().decode(R.self, from: data).tracks
  }
}

// MARK: - Transport controls

extension SpotifyClient {
  func play()  async throws { try await sendEmpty(method: "PUT",  path: "/me/player/play") }
  func pause() async throws { try await sendEmpty(method: "PUT",  path: "/me/player/pause") }
  func next()  async throws { try await sendEmpty(method: "POST", path: "/me/player/next") }
  func prev()  async throws { try await sendEmpty(method: "POST", path: "/me/player/previous") }

  fileprivate func sendEmpty(method: String, path: String) async throws {
    let url = URL(string: "https://api.spotify.com/v1\(path)")!
    var req = URLRequest(url: url)
    req.httpMethod = method
    let token = try tokenStore.load()
    req.setValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
    _ = try await session.data(for: req)
  }
}
