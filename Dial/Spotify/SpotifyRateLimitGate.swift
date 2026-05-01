import Foundation

actor SpotifyRateLimitGate {
  static let shared = SpotifyRateLimitGate(defaults: .standard)

  private let defaults: UserDefaults
  private let cooldownUntilKey = "spotify.rateLimit.cooldownUntil"
  private let lastRateLimitKey = "spotify.rateLimit.lastHitAt"

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func waitIfNeeded() async throws {
    guard let until = cooldownUntil, until > Date() else { return }
    try await Task.sleep(nanoseconds: Self.nanoseconds(until.timeIntervalSinceNow))
  }

  func recordRateLimit(retryAfter: TimeInterval?) {
    let base = max(retryAfter ?? 60, 15)
    let cushion = min(max(base * 0.2, 2), 30)
    let until = Date().addingTimeInterval(base + cushion)
    if until > (cooldownUntil ?? .distantPast) {
      defaults.set(until.timeIntervalSince1970, forKey: cooldownUntilKey)
    }
    defaults.set(Date().timeIntervalSince1970, forKey: lastRateLimitKey)
  }

  func cooldownRemaining() -> TimeInterval {
    guard let until = cooldownUntil else { return 0 }
    return max(0, until.timeIntervalSinceNow)
  }

  func cooldownUntilDate() -> Date? {
    guard let until = cooldownUntil, until > Date() else { return nil }
    return until
  }

  private var cooldownUntil: Date? {
    let raw = defaults.double(forKey: cooldownUntilKey)
    guard raw > 0 else { return nil }
    return Date(timeIntervalSince1970: raw)
  }

  private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64(max(0, seconds) * 1_000_000_000)
  }
}
