// Dial/LastFM/LastFMAPI.swift
import CryptoKit
import Foundation

/// API account credentials from last.fm/api/accounts. The key alone reads
/// tags; signed calls (auth, scrobble, love) also need the shared secret.
struct LastFMCredentials: Equatable, Sendable {
  let apiKey: String
  let sharedSecret: String
}

/// A user's authorized session. Last.fm session keys don't expire; the user
/// revokes them from last.fm/settings/applications.
struct LastFMSession: Equatable, Sendable {
  let credentials: LastFMCredentials
  let key: String
}

struct LastFMScrobbleEntry: Equatable, Sendable {
  let artist: String
  let track: String
  let album: String?
  let durationMs: Int64?
  /// When the play started, unix seconds UTC.
  let timestamp: Int64
}

/// Last.fm's per-scrobble answer. `ignoredCode` 0 means accepted.
struct LastFMScrobbleResult: Equatable, Sendable {
  let ignoredCode: Int
  let ignoredMessage: String

  var accepted: Bool { ignoredCode == 0 }

  static let acceptedResult = LastFMScrobbleResult(ignoredCode: 0, ignoredMessage: "")
}

enum LastFMErrorCode {
  static let invalidAPIKey = 10
  static let serviceOffline = 11
  static let invalidSessionKey = 9
  static let invalidSignature = 13
  static let tokenNotAuthorized = 14
  static let tokenExpired = 15
  static let temporarilyUnavailable = 16
  static let suspendedAPIKey = 26
  static let rateLimitExceeded = 29

  /// Per-scrobble ignore code: the account hit its daily scrobble limit.
  /// Worth retrying later, unlike the other ignore codes.
  static let dailyScrobbleLimit = 5
}

/// The signed Last.fm calls Dial makes. `LastFMWebClient` is the real one;
/// tests use a fake.
protocol LastFMScrobbleAPI {
  func getToken(credentials: LastFMCredentials) async throws -> String
  func getSession(token: String, credentials: LastFMCredentials) async throws -> (username: String, key: String)
  func updateNowPlaying(_ entry: LastFMScrobbleEntry, session: LastFMSession) async throws
  /// Up to 50 entries. Results come back in request order.
  func scrobble(_ entries: [LastFMScrobbleEntry], session: LastFMSession) async throws -> [LastFMScrobbleResult]
  func setLoved(_ loved: Bool, artist: String, track: String, session: LastFMSession) async throws
}

enum LastFMSignature {
  /// md5 of every parameter (sorted by name, name then value) followed by
  /// the shared secret. `format` and `callback` are not signed.
  static func sign(_ params: [String: String], secret: String) -> String {
    let base = params
      .filter { $0.key != "format" && $0.key != "callback" }
      .sorted { $0.key < $1.key }
      .map { $0.key + $0.value }
      .joined() + secret
    return Insecure.MD5.hash(data: Data(base.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

final class LastFMWebClient: LastFMScrobbleAPI {
  static let maxBatch = 50
  static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  static func authorizeURL(token: String, apiKey: String) -> URL {
    var comps = URLComponents(string: "https://www.last.fm/api/auth/")!
    comps.queryItems = [
      URLQueryItem(name: "api_key", value: apiKey),
      URLQueryItem(name: "token", value: token)
    ]
    return comps.url!
  }

  func getToken(credentials: LastFMCredentials) async throws -> String {
    let data = try await call("auth.getToken", [:], credentials: credentials, sessionKey: nil)
    let decoded = try JSONDecoder().decode(TokenEnvelope.self, from: data)
    guard !decoded.token.isEmpty else { throw LastFMError.invalidResponse }
    return decoded.token
  }

  func getSession(token: String, credentials: LastFMCredentials) async throws -> (username: String, key: String) {
    let data = try await call("auth.getSession", ["token": token], credentials: credentials, sessionKey: nil)
    let decoded = try JSONDecoder().decode(SessionEnvelope.self, from: data)
    guard !decoded.session.key.isEmpty else { throw LastFMError.invalidResponse }
    return (decoded.session.name, decoded.session.key)
  }

  func updateNowPlaying(_ entry: LastFMScrobbleEntry, session: LastFMSession) async throws {
    var params = ["artist": entry.artist, "track": entry.track]
    if let album = entry.album, !album.isEmpty { params["album"] = album }
    if let ms = entry.durationMs, ms > 0 { params["duration"] = String(ms / 1000) }
    _ = try await call("track.updateNowPlaying", params, credentials: session.credentials, sessionKey: session.key)
  }

  func scrobble(_ entries: [LastFMScrobbleEntry], session: LastFMSession) async throws -> [LastFMScrobbleResult] {
    precondition(entries.count <= Self.maxBatch, "Last.fm accepts at most 50 scrobbles per call")
    guard !entries.isEmpty else { return [] }
    var params: [String: String] = [:]
    for (i, entry) in entries.enumerated() {
      params["artist[\(i)]"] = entry.artist
      params["track[\(i)]"] = entry.track
      params["timestamp[\(i)]"] = String(entry.timestamp)
      if let album = entry.album, !album.isEmpty { params["album[\(i)]"] = album }
      if let ms = entry.durationMs, ms > 0 { params["duration[\(i)]"] = String(ms / 1000) }
    }
    let data = try await call("track.scrobble", params, credentials: session.credentials, sessionKey: session.key)
    let results = try Self.decodeScrobbleResults(data)
    // A short or malformed answer would mark the wrong rows. Treat it as a
    // failed call so the whole batch is retried.
    guard results.count == entries.count else { throw LastFMError.invalidResponse }
    return results
  }

  func setLoved(_ loved: Bool, artist: String, track: String, session: LastFMSession) async throws {
    _ = try await call(
      loved ? "track.love" : "track.unlove",
      ["artist": artist, "track": track],
      credentials: session.credentials,
      sessionKey: session.key)
  }

  // MARK: - Transport

  private func call(
    _ method: String,
    _ extra: [String: String],
    credentials: LastFMCredentials,
    sessionKey: String?
  ) async throws -> Data {
    var params = extra
    params["method"] = method
    params["api_key"] = credentials.apiKey
    if let sessionKey { params["sk"] = sessionKey }
    params["api_sig"] = LastFMSignature.sign(params, secret: credentials.sharedSecret)
    params["format"] = "json"

    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Dial/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
    request.httpBody = Data(Self.formEncode(params).utf8)
    request.timeoutInterval = 20

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw LastFMError.invalidResponse }
    // Last.fm reports API errors in the body, sometimes with a 4xx status.
    if let failure = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
      throw LastFMError.api(failure.error, failure.message ?? "Last.fm error")
    }
    guard (200...299).contains(http.statusCode) else { throw LastFMError.httpStatus(http.statusCode) }
    return data
  }

  static func formEncode(_ params: [String: String]) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return params
      .sorted { $0.key < $1.key }
      .map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(k)=\(v)"
      }
      .joined(separator: "&")
  }

  // MARK: - Decoding

  static func decodeScrobbleResults(_ data: Data) throws -> [LastFMScrobbleResult] {
    let envelope = try JSONDecoder().decode(ScrobblesEnvelope.self, from: data)
    return envelope.scrobbles.scrobble.items.map {
      LastFMScrobbleResult(
        ignoredCode: $0.ignoredMessage?.code.value ?? 0,
        ignoredMessage: $0.ignoredMessage?.text ?? "")
    }
  }

  private struct ErrorEnvelope: Decodable {
    let error: Int
    let message: String?
  }

  private struct TokenEnvelope: Decodable {
    let token: String
  }

  private struct SessionEnvelope: Decodable {
    struct Session: Decodable {
      let name: String
      let key: String
    }
    let session: Session
  }

  private struct ScrobblesEnvelope: Decodable {
    struct Scrobbles: Decodable {
      let scrobble: OneOrMany<Item>
    }
    struct Item: Decodable {
      let ignoredMessage: IgnoredMessage?
    }
    struct IgnoredMessage: Decodable {
      let code: FlexibleInt
      let text: String?

      enum CodingKeys: String, CodingKey {
        case code
        case text = "#text"
      }
    }
    let scrobbles: Scrobbles
  }

  /// Last.fm returns a bare object instead of a one-element array.
  private struct OneOrMany<T: Decodable>: Decodable {
    let items: [T]

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let many = try? container.decode([T].self) {
        items = many
      } else {
        items = [try container.decode(T.self)]
      }
    }
  }

  /// Codes arrive as "0" or 0 depending on the endpoint.
  private struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let int = try? container.decode(Int.self) {
        value = int
      } else if let string = try? container.decode(String.self), let int = Int(string) {
        value = int
      } else {
        value = 0
      }
    }
  }
}
