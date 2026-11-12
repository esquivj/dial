import XCTest
@testable import Dial

final class SpotifyAuthServiceTests: XCTestCase {
  func test_refreshRejectedDoesNotClearStoredToken() async throws {
    StubURLProtocol.handler = { req in
      XCTAssertEqual(req.httpMethod, "POST")
      XCTAssertEqual(req.url?.path, "/api/token")
      let response = HTTPURLResponse(
        url: req.url!,
        statusCode: 400,
        httpVersion: nil,
        headerFields: [:])!
      return (response, #"{"error":"invalid_grant"}"#.data(using: .utf8)!)
    }

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "expired", refreshToken: "refresh", expiresAt: 1))
    let auth = SpotifyAuthService(
      clientID: "auth-tests",
      tokenStore: store,
      session: StubURLProtocol.session())

    do {
      _ = try await auth.refresh()
      XCTFail("refresh should reject")
    } catch let error as SpotifyAuthError {
      XCTAssertEqual(error, .refreshRejected(400))
    }

    XCTAssertEqual(try store.load()?.refreshToken, "refresh")
  }

  func test_rateLimitedRefreshIsRetryableNotRejected() async throws {
    StubURLProtocol.handler = { req in
      let response = HTTPURLResponse(
        url: req.url!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: ["Retry-After": "5"])!
      return (response, Data())
    }

    let store = InMemoryTokenStore()
    try store.save(.init(accessToken: "expired", refreshToken: "refresh", expiresAt: 1))
    let auth = SpotifyAuthService(
      clientID: "auth-tests",
      tokenStore: store,
      session: StubURLProtocol.session())

    do {
      _ = try await auth.refresh()
      XCTFail("refresh should fail while rate limited")
    } catch let error as SpotifyAuthError {
      XCTAssertEqual(error, .tokenEndpointStatus(429))
    }

    XCTAssertEqual(try store.load()?.refreshToken, "refresh")
  }

  func test_refreshWithoutStoredTokenReportsMissingToken() async throws {
    let store = InMemoryTokenStore()
    let auth = SpotifyAuthService(
      clientID: "auth-tests",
      tokenStore: store,
      session: StubURLProtocol.session())

    do {
      _ = try await auth.refresh()
      XCTFail("refresh should fail without a stored token")
    } catch let error as SpotifyAuthError {
      XCTAssertEqual(error, .missingStoredToken)
    }
  }
}
