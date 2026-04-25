// DialTests/Auth/PKCETests.swift
import XCTest
@testable import Dial

final class PKCETests: XCTestCase {
  func test_verifier_isUrlSafe_43To128Chars() {
    let v = PKCE.makeCodeVerifier()
    XCTAssertGreaterThanOrEqual(v.count, 43)
    XCTAssertLessThanOrEqual(v.count, 128)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    XCTAssertTrue(v.allSatisfy { allowed.contains($0) })
  }
  func test_challenge_matchesSHA256Base64UrlOfVerifier() {
    let v = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"   // RFC 7636 example verifier
    let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    XCTAssertEqual(PKCE.makeCodeChallenge(for: v), expected)
  }
}
