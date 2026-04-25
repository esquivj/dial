// Dial/Pet/StreakCalendar.swift
import Foundation

struct StreakCalendar {
  struct Result { let anchor: String; let days: Int64 }

  /// `playDate` and `priorAnchor` are `YYYY-MM-DD` strings in the user's local time zone.
  /// Same day → no change. Next day → +1. Gap → reset to 1.
  func apply(playDate: String, priorAnchor: String?, priorDays: Int64) -> Result {
    guard let priorAnchor else {
      return .init(anchor: playDate, days: 1)
    }
    if playDate == priorAnchor {
      return .init(anchor: priorAnchor, days: priorDays)
    }
    guard let prior = date(from: priorAnchor),
          let today = date(from: playDate) else {
      return .init(anchor: playDate, days: 1)
    }
    let gap = Calendar(identifier: .gregorian)
      .dateComponents([.day], from: prior, to: today).day ?? 0
    return gap == 1
      ? .init(anchor: playDate, days: priorDays + 1)
      : .init(anchor: playDate, days: 1)
  }

  private func date(from ymd: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    return f.date(from: ymd)
  }

  /// Helper for callers that have a unix timestamp and need the YYYY-MM-DD anchor.
  static func ymd(from unixSeconds: Int64, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = timeZone
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(unixSeconds)))
  }
}
