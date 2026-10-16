// Dial/Auth/SpotifyAuthService.swift
import Foundation
import AuthenticationServices
import os.log

private let authLog = Logger(subsystem: "com.dial.Dial", category: "Auth")

/// Auth-related errors that callers can pattern-match on.
/// `missingStoredToken` is the only clear sign we have no local auth state.
/// `refreshRejected` means Spotify rejected a refresh attempt, but Dial keeps
/// the token around so a transient auth edge does not force a full OAuth flow
/// on every relaunch.
enum SpotifyAuthError: Error, Equatable {
  case missingStoredToken
  case refreshRejected(Int)
  case invalidResponse
  case tokenEndpointStatus(Int)
}

final class SpotifyAuthService: NSObject {
  private let clientID: String
  private let redirectURI = "dial://callback"
  private let scopes = [
    "user-read-currently-playing",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-recently-played",
    "user-top-read",
    "user-library-read",
    "user-library-modify"
  ]
  private let tokenStore: TokenStore
  private let session: URLSession

  init(clientID: String, tokenStore: TokenStore, session: URLSession = .shared) {
    self.clientID = clientID
    self.tokenStore = tokenStore
    self.session = session
  }

  @MainActor
  func signIn() async throws -> SpotifyToken {
    let verifier = PKCE.makeCodeVerifier()
    let challenge = PKCE.makeCodeChallenge(for: verifier)

    guard var auth = URLComponents(string: "https://accounts.spotify.com/authorize") else {
      throw SpotifyAuthError.invalidResponse
    }
    auth.queryItems = [
      .init(name: "client_id", value: clientID),
      .init(name: "response_type", value: "code"),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "code_challenge", value: challenge),
      .init(name: "scope", value: scopes.joined(separator: " ")),
      .init(name: "show_dialog", value: "true")
    ]

    guard let authURL = auth.url else { throw SpotifyAuthError.invalidResponse }

    let code: String = try await withCheckedThrowingContinuation { cont in
      let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "dial") { callback, error in
        if let error { cont.resume(throwing: error); return }
        guard let cb = callback,
              let c = URLComponents(url: cb, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "code" })?.value
        else {
          cont.resume(throwing: NSError(domain: "Dial.Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing code in callback"]))
          return
        }
        cont.resume(returning: c)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      session.start()
    }

    let token = try await exchange(code: code, verifier: verifier)
    try tokenStore.save(token)
    return token
  }

  private func exchange(code: String, verifier: String) async throws -> SpotifyToken {
    guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
      throw SpotifyAuthError.invalidResponse
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.formEncode([
      "grant_type":   "authorization_code",
      "code":         code,
      "redirect_uri": redirectURI,
      "client_id":    clientID,
      "code_verifier": verifier
    ]).data(using: .utf8)
    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw SpotifyAuthError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      throw SpotifyAuthError.tokenEndpointStatus(http.statusCode)
    }
    struct R: Decodable {
      let access_token: String
      let refresh_token: String
      let expires_in: Int
    }
    let r = try JSONDecoder().decode(R.self, from: data)
    return .init(
      accessToken: r.access_token,
      refreshToken: r.refresh_token,
      expiresAt: Int64(Date().timeIntervalSince1970) + Int64(r.expires_in)
    )
  }

  func refresh() async throws -> SpotifyToken {
    authLog.notice("refresh() called")
    guard let current = try tokenStore.load() else {
      authLog.error("refresh: no token in store")
      throw SpotifyAuthError.missingStoredToken
    }
    guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
      throw SpotifyAuthError.invalidResponse
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.formEncode([
      "grant_type":    "refresh_token",
      "refresh_token": current.refreshToken,
      "client_id":     clientID
    ]).data(using: .utf8)
    let (data, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw SpotifyAuthError.invalidResponse
    }

    // Do not clear the refresh token here. Spotify can return a 4xx during
    // auth edge cases, account/device churn, or request races; deleting the
    // credential turns that into a guaranteed full reauth on every relaunch.
    // The explicit Disconnect button remains the destructive path.
    if (400...499).contains(http.statusCode) {
      authLog.error("refresh: 4xx status \(http.statusCode), preserving token for retry")
      throw SpotifyAuthError.refreshRejected(http.statusCode)
    }
    guard (200...299).contains(http.statusCode) else {
      throw SpotifyAuthError.tokenEndpointStatus(http.statusCode)
    }
    struct R: Decodable {
      let access_token: String
      let refresh_token: String?
      let expires_in: Int
    }
    let r = try JSONDecoder().decode(R.self, from: data)
    let updated = SpotifyToken(
      accessToken: r.access_token,
      refreshToken: r.refresh_token ?? current.refreshToken,
      expiresAt: Int64(Date().timeIntervalSince1970) + Int64(r.expires_in)
    )
    do {
      try tokenStore.save(updated)
      authLog.notice("refresh: saved new token, expires in \(r.expires_in)s")
    } catch {
      authLog.error("refresh: tokenStore.save FAILED: \(String(describing: error), privacy: .public)")
      throw error
    }
    return updated
  }
}

extension SpotifyAuthService: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    NSApplication.shared.windows.first ?? ASPresentationAnchor()
  }
}

private extension SpotifyAuthService {
  /// `application/x-www-form-urlencoded` body. Each value is percent-escaped per
  /// the form-url-encoded charset (RFC 3986 unreserved + `*-._`), so server-supplied
  /// tokens with `+`, `/`, or `=` survive the round-trip unchanged.
  static func formEncode(_ pairs: [String: String]) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=")
    return pairs
      .map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)" }
      .joined(separator: "&")
  }
}
