// Dial/Views/Dropdown/StatsViewSnapshot.swift
import Foundation
import GRDB

struct StatsViewSnapshot {
  let totals: StatsQueries.Totals
  let topTracks: [StatsQueries.TopRow]
  let topArtists: [StatsQueries.TopRow]
  let topGenres: [StatsQueries.GenreRow]
  let rhythmBuckets: [StatsQueries.RhythmBucket]
  let badgeSummaries: [StatsQueries.BadgeSummary]
  let recentBadges: [StatsQueries.BadgeMemoryRow]

  static func load(dbq: DatabaseQueue, range: StatsRange) async -> StatsViewSnapshot {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: make(dbq: dbq, range: range))
      }
    }
  }

  private static func make(dbq: DatabaseQueue, range: StatsRange) -> StatsViewSnapshot {
    let q = StatsQueries(dbq: dbq)
    let since = range.since
    let rhythm: [StatsQueries.RhythmBucket]
    if range == .seven {
      rhythm = (try? q.recentDailyRhythm(days: 7)) ?? []
    } else {
      rhythm = (try? q.weekdayRhythm(since: since)) ?? []
    }

    return StatsViewSnapshot(
      totals: (try? q.totals(since: since)) ?? StatsQueries.Totals(
        plays: 0,
        listeningMs: 0,
        uniqueTracks: 0,
        uniqueArtists: 0),
      topTracks: (try? q.topTracks(since: since)) ?? [],
      topArtists: (try? q.topArtists(since: since)) ?? [],
      topGenres: (try? q.topGenres(since: since)) ?? [],
      rhythmBuckets: rhythm,
      badgeSummaries: (try? q.badgeSummaries()) ?? [],
      recentBadges: (try? q.recentBadgeMemories(limit: 5)) ?? [])
  }
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
