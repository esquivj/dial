// Dial/Auth/PKCE.swift
import Foundation
import CryptoKit

enum PKCE {
  static func makeCodeVerifier(length: Int = 64) -> String {
    let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var rng = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in chars[Int(rng.next(upperBound: UInt64(chars.count)))] })
  }
  static func makeCodeChallenge(for verifier: String) -> String {
    let hash = SHA256.hash(data: Data(verifier.utf8))
    return Data(hash).base64URLEncoded()
  }
}
private extension Data {
  func base64URLEncoded() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
