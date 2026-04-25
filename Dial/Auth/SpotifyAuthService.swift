// Dial/Auth/SpotifyAuthService.swift
import Foundation
import AuthenticationServices

final class SpotifyAuthService: NSObject {
  private let clientID: String
  private let redirectURI = "dial://callback"
  private let scopes = [
    "user-read-currently-playing",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-recently-played"
  ]
  private let tokenStore: TokenStore

  init(clientID: String, tokenStore: TokenStore) {
    self.clientID = clientID
    self.tokenStore = tokenStore
  }

  @MainActor
  func signIn() async throws -> SpotifyToken {
    let verifier = PKCE.makeCodeVerifier()
    let challenge = PKCE.makeCodeChallenge(for: verifier)

    var auth = URLComponents(string: "https://accounts.spotify.com/authorize")!
    auth.queryItems = [
      .init(name: "client_id", value: clientID),
      .init(name: "response_type", value: "code"),
      .init(name: "redirect_uri", value: redirectURI),
      .init(name: "code_challenge_method", value: "S256"),
      .init(name: "code_challenge", value: challenge),
      .init(name: "scope", value: scopes.joined(separator: " "))
    ]

    let code: String = try await withCheckedThrowingContinuation { cont in
      let session = ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: "dial") { callback, error in
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
    var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.formEncode([
      "grant_type":   "authorization_code",
      "code":         code,
      "redirect_uri": redirectURI,
      "client_id":    clientID,
      "code_verifier": verifier
    ]).data(using: .utf8)
    let (data, _) = try await URLSession.shared.data(for: req)
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
    guard let current = try tokenStore.load() else {
      throw NSError(domain: "Dial.Auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "no token to refresh"])
    }
    var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.formEncode([
      "grant_type":    "refresh_token",
      "refresh_token": current.refreshToken,
      "client_id":     clientID
    ]).data(using: .utf8)
    let (data, _) = try await URLSession.shared.data(for: req)
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
    try tokenStore.save(updated)
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
