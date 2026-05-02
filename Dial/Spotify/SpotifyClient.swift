// Dial/Spotify/SpotifyClient.swift
import Foundation

enum SpotifyAPIError: Error, Equatable {
  case httpStatus(Int)
  case rateLimited(retryAfter: TimeInterval?)
  case invalidResponse
}

final class SpotifyClient {
  private let session: URLSession
  private let tokenStore: TokenStore
  private let refresh: () async throws -> SpotifyToken
  private let rateLimitGate: SpotifyRateLimitGate

  init(session: URLSession = .shared,
       tokenStore: TokenStore,
       rateLimitGate: SpotifyRateLimitGate = .shared,
       refresh: @escaping () async throws -> SpotifyToken) {
    self.session = session
    self.tokenStore = tokenStore
    self.rateLimitGate = rateLimitGate
    self.refresh = refresh
  }

  /// Authed GET with two layers of self-healing:
  ///   * 401 → refresh the token once and retry
  ///   * 429 → record one shared cooldown for background catalog enrichment.
  ///           Foreground/player calls do not wait on that cooldown; they should
  ///           fail fast if Spotify itself rejects them, not make the app feel
  ///           disconnected.
  fileprivate func authedGET(
    _ url: URL,
    retryOn401: Bool = true,
    retryOn429: Bool = true,
    respectRateLimitGate: Bool = false
  ) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    return try await authedRequest(
      req,
      retryOn401: retryOn401,
      retryOn429: retryOn429,
      respectRateLimitGate: respectRateLimitGate)
  }

  fileprivate func authedRequest(
    _ request: URLRequest,
    retryOn401: Bool = true,
    retryOn429: Bool = true,
    respectRateLimitGate: Bool = false
  ) async throws -> (Data, HTTPURLResponse) {
    if respectRateLimitGate {
      try await rateLimitGate.waitIfNeeded()
    }
    let token = try tokenStore.load()
    var req = request
    req.setValue("Bearer \(token?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw SpotifyAPIError.invalidResponse
    }

    if http.statusCode == 401, retryOn401 {
      _ = try await refresh()
      return try await authedRequest(
        request,
        retryOn401: false,
        retryOn429: retryOn429,
        respectRateLimitGate: respectRateLimitGate)
    }
    if http.statusCode == 429, retryOn429 {
      let waitSec = Self.retryAfterSeconds(from: http)
      await rateLimitGate.recordRateLimit(retryAfter: waitSec)
      throw SpotifyAPIError.rateLimited(retryAfter: waitSec)
    }
    return (data, http)
  }

  fileprivate static func validate(_ response: HTTPURLResponse) throws {
    guard (200...299).contains(response.statusCode) else {
      throw SpotifyAPIError.httpStatus(response.statusCode)
    }
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
    // /me/player gives the full player state (track + progress + is_playing
    // + shuffle_state + repeat_state + device). The older /currently-playing
    // endpoint omits shuffle/repeat, which the dropdown's transport row
    // needs to render the toggle states. Both return 204 when nothing's
    // playing, so the caller-side semantics are unchanged.
    let url = URL(string: "https://api.spotify.com/v1/me/player")!
    let (data, http) = try await authedGET(url)
    if http.statusCode == 204 { return nil }
    try Self.validate(http)
    return try JSONDecoder().decode(CurrentlyPlaying.self, from: data)
  }

  func recentlyPlayed(afterMs: Int64?, limit: Int = 50) async throws -> RecentlyPlayedResponse {
    var comps = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")!
    var items = [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))")]
    if let afterMs {
      items.append(URLQueryItem(name: "after", value: "\(afterMs)"))
    }
    comps.queryItems = items
    guard let url = comps.url else { throw SpotifyAPIError.invalidResponse }
    let (data, http) = try await authedGET(url)
    try Self.validate(http)
    return try JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
  }

  func audioFeatures(trackId: String, respectRateLimitGate: Bool = false) async throws -> AudioFeatures {
    let url = URL(string: "https://api.spotify.com/v1/audio-features/\(trackId)")!
    let (data, http) = try await authedGET(url, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
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

struct ArtistMeta: Decodable {
  struct Image: Decodable { let url: String }
  let uri: String
  let name: String
  let genres: [String]
  let images: [Image]

  private enum CodingKeys: String, CodingKey {
    case uri, name, genres, images
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    uri = try container.decode(String.self, forKey: .uri)
    name = try container.decode(String.self, forKey: .name)
    genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
    images = try container.decodeIfPresent([Image].self, forKey: .images) ?? []
  }
}

extension SpotifyClient {
  /// Single-track metadata still works for this app, while the batched
  /// `/v1/tracks?ids=...` endpoint returns 403 in development quota mode.
  /// The historical backfill is slower one-by-one, but it gives us real
  /// artist URIs, album names, duration, and art for imported history rows.
  func track(uri: String, respectRateLimitGate: Bool = false) async throws -> TrackMeta {
    guard uri.hasPrefix("spotify:track:") else { throw SpotifyAPIError.httpStatus(400) }
    let id = uri.replacingOccurrences(of: "spotify:track:", with: "")
    let url = URL(string: "https://api.spotify.com/v1/tracks/\(id)")!
    let (data, http) = try await authedGET(url, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
    return try JSONDecoder().decode(TrackMeta.self, from: data)
  }

  /// Fetches up to 50 tracks per call. Callers should batch > 50 externally.
  func tracks(uris: [String], respectRateLimitGate: Bool = false) async throws -> [TrackMeta] {
    let ids = uris
      .map { $0.replacingOccurrences(of: "spotify:track:", with: "") }
      .joined(separator: ",")
    let url = URL(string: "https://api.spotify.com/v1/tracks?ids=\(ids)")!
    let (data, http) = try await authedGET(url, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
    struct R: Decodable { let tracks: [TrackMeta?] }
    return try JSONDecoder().decode(R.self, from: data).tracks.compactMap { $0 }
  }

  /// Single-artist metadata. Spotify genres live on artists, not tracks.
  /// The field is deprecated and may be empty, but it is still the best native
  /// signal available for a personal Wrapped-style genre layer.
  func artist(uri: String, respectRateLimitGate: Bool = false) async throws -> ArtistMeta {
    guard uri.hasPrefix("spotify:artist:") else { throw SpotifyAPIError.httpStatus(400) }
    let id = uri.replacingOccurrences(of: "spotify:artist:", with: "")
    let url = URL(string: "https://api.spotify.com/v1/artists/\(id)")!
    let (data, http) = try await authedGET(url, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
    return try JSONDecoder().decode(ArtistMeta.self, from: data)
  }
}

// MARK: - Library / Liked Songs

extension SpotifyClient {
  func libraryContains(uri: String, respectRateLimitGate: Bool = false) async throws -> Bool {
    guard uri.hasPrefix("spotify:track:") else { return false }
    let (data, http) = try await authedGET(
      Self.libraryURL(path: "/me/library/contains", uri: uri),
      respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
    return try JSONDecoder().decode([Bool].self, from: data).first ?? false
  }

  func saveToLibrary(uri: String, respectRateLimitGate: Bool = false) async throws {
    try await sendEmpty(
      method: "PUT",
      url: Self.libraryURL(path: "/me/library", uri: uri),
      respectRateLimitGate: respectRateLimitGate)
  }

  func removeFromLibrary(uri: String, respectRateLimitGate: Bool = false) async throws {
    try await sendEmpty(
      method: "DELETE",
      url: Self.libraryURL(path: "/me/library", uri: uri),
      respectRateLimitGate: respectRateLimitGate)
  }

  fileprivate static func libraryURL(path: String, uri: String) throws -> URL {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":")
    let encoded = uri.addingPercentEncoding(withAllowedCharacters: allowed) ?? uri

    var comps = URLComponents(string: "https://api.spotify.com/v1\(path)")!
    comps.percentEncodedQueryItems = [.init(name: "uris", value: encoded)]
    guard let url = comps.url else { throw SpotifyAPIError.invalidResponse }
    return url
  }
}

// MARK: - oEmbed (public, no-auth fallback)

/// Lightweight track metadata from Spotify's public oEmbed endpoint.
/// `/v1/tracks` (Get Several Tracks) was restricted in Spotify's November 2024
/// API changes — apps in Development Mode quota now get 403 Forbidden on it.
/// `oembed` is unrestricted, requires no authentication, and returns just
/// enough (title + thumbnail) for the History view to show album art.
struct OEmbedTrack: Decodable {
  let title: String?
  let thumbnail_url: String?
}

extension SpotifyClient {
  /// Fetch a track's title + album art via oEmbed. No auth required.
  /// One request per track (no batching) — slower than `/v1/tracks` but
  /// works under the post-2024 API restrictions.
  func trackOEmbed(uri: String) async throws -> OEmbedTrack {
    // The oEmbed endpoint accepts a Spotify URI in the `url` parameter,
    // URL-encoded. `spotify:track:<id>` works as-is when colon-encoded.
    let encoded = uri.replacingOccurrences(of: ":", with: "%3A")
    let url = URL(string: "https://open.spotify.com/oembed?url=\(encoded)&format=json")!
    let (data, _) = try await session.data(for: URLRequest(url: url))
    return try JSONDecoder().decode(OEmbedTrack.self, from: data)
  }
}

// MARK: - Transport controls

extension SpotifyClient {
  func play() async throws {
    if let deviceID = try? await preferredPlaybackDeviceID(respectRateLimitGate: false) {
      do {
        try await sendEmpty(
          method: "PUT",
          path: "/me/player/play",
          queryItems: [.init(name: "device_id", value: deviceID)],
          respectRateLimitGate: false)
        return
      } catch {
        // Device lists can be stale right after Spotify starts or changes
        // output. Fall back to Spotify's implicit "current active device"
        // resume path before surfacing the failure to the UI.
      }
    }
    try await sendEmpty(method: "PUT", path: "/me/player/play", respectRateLimitGate: false)
  }

  func pause() async throws {
    try await sendEmpty(method: "PUT", path: "/me/player/pause", respectRateLimitGate: false)
  }
  func next() async throws {
    try await sendEmpty(method: "POST", path: "/me/player/next", respectRateLimitGate: false)
  }
  func prev() async throws {
    try await sendEmpty(method: "POST", path: "/me/player/previous", respectRateLimitGate: false)
  }

  /// Restart the current track from 0:00.
  func seek(positionMs: Int = 0) async throws {
    try await sendEmpty(
      method: "PUT",
      path: "/me/player/seek?position_ms=\(positionMs)",
      respectRateLimitGate: false)
  }

  /// Toggle shuffle on or off for the current player.
  func setShuffle(_ on: Bool) async throws {
    try await sendEmpty(
      method: "PUT",
      path: "/me/player/shuffle?state=\(on)",
      respectRateLimitGate: false)
  }

  /// Set repeat mode. Valid values per Spotify: "off" | "context" | "track".
  func setRepeat(_ mode: String) async throws {
    try await sendEmpty(
      method: "PUT",
      path: "/me/player/repeat?state=\(mode)",
      respectRateLimitGate: false)
  }

  fileprivate func sendEmpty(
    method: String,
    path: String,
    queryItems: [URLQueryItem] = [],
    respectRateLimitGate: Bool = false
  ) async throws {
    var comps = URLComponents(string: "https://api.spotify.com/v1\(path)")!
    if !queryItems.isEmpty { comps.queryItems = queryItems }
    guard let url = comps.url else { throw SpotifyAPIError.invalidResponse }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("0", forHTTPHeaderField: "Content-Length")
    req.httpBody = Data()
    let (_, http) = try await authedRequest(req, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
  }

  fileprivate func sendEmpty(
    method: String,
    url: URL,
    respectRateLimitGate: Bool = false
  ) async throws {
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue("0", forHTTPHeaderField: "Content-Length")
    req.httpBody = Data()
    let (_, http) = try await authedRequest(req, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
  }

  private func preferredPlaybackDeviceID(respectRateLimitGate: Bool = false) async throws -> String? {
    let url = URL(string: "https://api.spotify.com/v1/me/player/devices")!
    let (data, http) = try await authedGET(url, respectRateLimitGate: respectRateLimitGate)
    try Self.validate(http)
    let response = try JSONDecoder().decode(PlaybackDevicesResponse.self, from: data)
    return response.devices.first(where: { $0.isActive && !$0.isRestricted })?.id
      ?? response.devices.first(where: { !$0.isRestricted })?.id
  }
}

private struct PlaybackDevicesResponse: Decodable {
  let devices: [PlaybackDevice]
}

private struct PlaybackDevice: Decodable {
  let id: String?
  let isActive: Bool
  let isRestricted: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case isActive = "is_active"
    case isRestricted = "is_restricted"
  }
}
