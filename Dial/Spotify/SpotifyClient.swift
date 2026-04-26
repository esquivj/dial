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

  /// Authed GET with two layers of self-healing:
  ///   * 401 → refresh the token once and retry
  ///   * 429 → sleep for the value Spotify gave us in `Retry-After`, then
  ///           retry once. Without this, hitting the rate limit (which can
  ///           happen during the MetadataEnricher backfill across 49k tracks
  ///           or if multiple polling clients overlap) would just return a
  ///           429 to PollingService, which would then back off blindly
  ///           regardless of how long Spotify actually wanted us to wait —
  ///           sometimes too short (more 429s) and sometimes too long
  ///           (wasted polling time).
  fileprivate func authedGET(
    _ url: URL,
    retryOn401: Bool = true,
    retryOn429: Bool = true
  ) async throws -> (Data, HTTPURLResponse) {
    let token = try tokenStore.load()
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await session.data(for: req)
    let http = resp as! HTTPURLResponse

    if http.statusCode == 401, retryOn401 {
      _ = try await refresh()
      return try await authedGET(url, retryOn401: false, retryOn429: retryOn429)
    }
    if http.statusCode == 429, retryOn429 {
      // Cap at 60s so a misconfigured Retry-After (or the rare HTTP-date
      // form) doesn't silently freeze the polling loop forever. If Spotify
      // really needs longer, the next poll cycle will just hit 429 again
      // and we'll wait again.
      let waitSec = Self.retryAfterSeconds(from: http) ?? 5
      let capped = min(max(waitSec, 1), 60)
      try await Task.sleep(nanoseconds: UInt64(capped * 1_000_000_000))
      return try await authedGET(url, retryOn401: retryOn401, retryOn429: false)
    }
    return (data, http)
  }

  /// Spotify always returns Retry-After as an integer second count, but the
  /// HTTP spec also allows an HTTP-date — handle both forms defensively so
  /// any future change in their behavior doesn't silently default us to 5s.
  private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
    guard let val = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
    if let seconds = TimeInterval(val) { return seconds }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = f.date(from: val) { return max(0, date.timeIntervalSinceNow) }
    return nil
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
