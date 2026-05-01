// Dial/Views/Dropdown/PetViewSnapshot.swift
import Foundation
import GRDB

struct PetViewSnapshot {
  let todayListeningMs: Int64
  let recentBadgeCounts: [BadgeCategory: Int]
  let unlockedTricks: [PetTrickUnlock]
  let artifacts: [Artifact]
  let weeklyMemory: StatsQueries.WeeklyMemorySnapshot?
  let weeklyMemoryLog: [WeeklyMemoryRecord]
  let petState: PetState?

  static func load(
    dbq: DatabaseQueue,
    startOfToday: Int64,
    livingMemoriesEnabled: Bool
  ) async -> PetViewSnapshot {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: make(
          dbq: dbq,
          startOfToday: startOfToday,
          livingMemoriesEnabled: livingMemoriesEnabled))
      }
    }
  }

  private static func make(
    dbq: DatabaseQueue,
    startOfToday: Int64,
    livingMemoriesEnabled: Bool
  ) -> PetViewSnapshot {
    let queries = StatsQueries(dbq: dbq)
    let recentCutoff = Int64(Date().timeIntervalSince1970) - 7 * 86_400
    let summaries = (try? queries.badgeSummaries(since: recentCutoff)) ?? []
    let badgeCounts = summaries.reduce(into: [:]) { acc, summary in
      acc[summary.category] = summary.count
    }
    let weeklyLog = livingMemoriesEnabled
      ? ((try? WeeklyMemoriesDAO(dbq: dbq).ensureRecentWeeks(limit: 12)) ?? [])
      : []
    let liveWeeklyMemory = livingMemoriesEnabled
      ? (weeklyLog.first.map(StatsQueries.WeeklyMemorySnapshot.init(record:)) ?? (try? queries.weeklyMemory()))
      : nil

    return PetViewSnapshot(
      todayListeningMs: (try? queries.totals(since: startOfToday).listeningMs) ?? 0,
      recentBadgeCounts: badgeCounts,
      unlockedTricks: (try? PetTrickUnlocksDAO(dbq: dbq).all()) ?? [],
      artifacts: (try? ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()) ?? [],
      weeklyMemory: liveWeeklyMemory,
      weeklyMemoryLog: weeklyLog,
      petState: try? PetStateDAO(dbq: dbq).get())
  }
}
