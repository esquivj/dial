// Dial/Views/Dropdown/StatsViewSnapshot.swift
import Foundation
import GRDB

struct StatsViewSnapshot {
  let totals: StatsQueries.Totals
  let topTracks: [StatsQueries.TopRow]
  let topArtists: [StatsQueries.TopRow]
  let topGenres: [StatsQueries.GenreRow]
  let weeklyMemory: StatsQueries.WeeklyMemorySnapshot?
  let rhythmBuckets: [StatsQueries.RhythmBucket]
  let badgeSummaries: [StatsQueries.BadgeSummary]
  let recentBadges: [StatsQueries.BadgeMemoryRow]

  /// `nil` when the load was cancelled. A cancelled load stops at the next
  /// query instead of running to the end, so it doesn't hold the database
  /// queue while the range the user picked next waits behind it.
  static func load(dbq: DatabaseQueue, range: StatsRange) async -> StatsViewSnapshot? {
    let cancelled = CancelFlag()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: make(dbq: dbq, range: range, isCancelled: cancelled.isSet))
        }
      }
    } onCancel: {
      cancelled.set()
    }
  }

  static func make(
    dbq: DatabaseQueue,
    range: StatsRange,
    isCancelled: () -> Bool = { false }
  ) -> StatsViewSnapshot? {
    let q = StatsQueries(dbq: dbq)
    let since = range.since
    func step<T>(_ fallback: T, _ query: () throws -> T) -> T? {
      guard !isCancelled() else { return nil }
      return (try? query()) ?? fallback
    }
    let emptyTotals = StatsQueries.Totals(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0)
    guard let totals = step(emptyTotals, { try q.totals(since: since) }),
          let topTracks = step([], { try q.topTracks(since: since) }),
          let topArtists = step([], { try q.topArtists(since: since) }),
          let rhythm = step([], {
            range == .seven ? try q.recentDailyRhythm(days: 7) : try q.weekdayRhythm(since: since)
          }),
          let topGenres = step([], { try q.topGenres(since: since) }),
          let weeklyLog = step([], { try WeeklyMemoriesDAO(dbq: dbq).recent(limit: 1) })
    else { return nil }
    let weeklyMemory = weeklyLog.first.map(StatsQueries.WeeklyMemorySnapshot.init(record:))
      ?? (try? q.weeklyMemory())

    return StatsViewSnapshot(
      totals: totals,
      topTracks: topTracks,
      topArtists: topArtists,
      topGenres: topGenres,
      weeklyMemory: weeklyMemory,
      rhythmBuckets: rhythm,
      badgeSummaries: (try? q.badgeSummaries()) ?? [],
      recentBadges: (try? q.recentBadgeMemories(limit: 5)) ?? [])
  }
}

private final class CancelFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func set() { lock.withLock { value = true } }
  func isSet() -> Bool { lock.withLock { value } }
}

enum StatsRange: String, CaseIterable, Identifiable {
  case all
  case ytd
  case thirty
  case seven

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all:    return "ALL"
    case .ytd:    return "YTD"
    case .thirty: return "30D"
    case .seven:  return "7D"
    }
  }

  var since: Int64? {
    switch self {
    case .all:    return nil
    case .ytd:    return Self.startOfYearEpoch()
    case .thirty: return Int64(Date().timeIntervalSince1970) - 30 * 86_400
    case .seven:  return Int64(Date().timeIntervalSince1970) - 7 * 86_400
    }
  }

  /// Spelled out for the range button's tooltip (PLA-113).
  var help: String {
    switch self {
    case .all:    return "All known history: imported and live plays"
    case .ytd:    return "Year to date: since January 1"
    case .thirty: return "The last 30 days"
    case .seven:  return "The last 7 days"
    }
  }

  /// What fills an empty range (PLA-113).
  var emptyLine: String {
    switch self {
    case .all:    return "Import your Spotify history in Settings, or play something."
    case .ytd:    return "Nothing played this year. Play something and it shows up here."
    case .thirty: return "Nothing played in the last 30 days."
    case .seven:  return "Nothing played in the last 7 days."
    }
  }

  var heroTitle: String {
    switch self {
    case .all:    return "ALL KNOWN HISTORY"
    case .ytd:    return "THIS YEAR"
    case .thirty: return "LAST 30 DAYS"
    case .seven:  return "LAST 7 DAYS"
    }
  }

  private static func startOfYearEpoch() -> Int64 {
    let now = Date()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let components = calendar.dateComponents([.year], from: now)
    return Int64((calendar.date(from: components) ?? now).timeIntervalSince1970)
  }
}
