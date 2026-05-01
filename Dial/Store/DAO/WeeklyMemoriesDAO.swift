import Foundation
import GRDB

struct WeeklyMemoriesDAO {
  let dbq: DatabaseQueue
  var now: () -> Int64 = { Int64(Date().timeIntervalSince1970) }

  func recent(limit: Int = 12) throws -> [WeeklyMemoryRecord] {
    try dbq.read { db in
      try WeeklyMemoryRecord
        .order(WeeklyMemoryRecord.Columns.weekStart.desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  @discardableResult
  func ensureRecentWeeks(limit: Int = 12) throws -> [WeeklyMemoryRecord] {
    let current = now()
    let targetWeeks = recentWeekBounds(limit: limit, now: current)
    let existing = try existingWeekStarts()
    let queries = StatsQueries(dbq: dbq)

    for bounds in targetWeeks {
      let isCurrentWeek = bounds.start == targetWeeks.first?.start
      guard isCurrentWeek || !existing.contains(bounds.start) else { continue }
      guard let snapshot = try queries.weeklyMemory(weekStart: bounds.start, weekEnd: bounds.end) else { continue }
      try upsert(snapshot, now: current)
    }

    try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()
    return try recent(limit: limit)
  }

  @discardableResult
  func upsert(_ snapshot: StatsQueries.WeeklyMemorySnapshot, now: Int64? = nil) throws -> WeeklyMemoryRecord {
    let timestamp = now ?? self.now()
    var record = WeeklyMemoryRecord(snapshot: snapshot, now: timestamp)

    try dbq.write { db in
      if let existing = try WeeklyMemoryRecord
        .filter(WeeklyMemoryRecord.Columns.weekStart == snapshot.weekStart)
        .fetchOne(db) {
        record.createdAt = existing.createdAt
      }

      try db.execute(sql: """
        INSERT INTO weekly_memories
          (week_start, week_end, trait, memento, recap_line, room_object_name,
           dominant_genre, theme, play_count, listening_ms, unique_artists,
           new_artists, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(week_start) DO UPDATE SET
          week_end = excluded.week_end,
          trait = excluded.trait,
          memento = excluded.memento,
          recap_line = excluded.recap_line,
          room_object_name = excluded.room_object_name,
          dominant_genre = excluded.dominant_genre,
          theme = excluded.theme,
          play_count = excluded.play_count,
          listening_ms = excluded.listening_ms,
          unique_artists = excluded.unique_artists,
          new_artists = excluded.new_artists,
          updated_at = excluded.updated_at
        """, arguments: [
          record.weekStart,
          record.weekEnd,
          record.trait,
          record.memento,
          record.recapLine,
          record.roomObjectName,
          record.dominantGenre,
          record.theme.rawValue,
          record.playCount,
          record.listeningMs,
          record.uniqueArtists,
          record.newArtists,
          record.createdAt,
          record.updatedAt,
        ])
    }

    return record
  }

  private func existingWeekStarts() throws -> Set<Int64> {
    try dbq.read { db in
      let rows = try Int64.fetchAll(db, sql: "SELECT week_start FROM weekly_memories")
      return Set(rows)
    }
  }

  private func recentWeekBounds(limit: Int, now: Int64) -> [(start: Int64, end: Int64)] {
    guard limit > 0 else { return [] }
    return (0..<limit).map { offset in
      let epoch = now - Int64(offset * 7 * 86_400)
      return StatsQueries.weekBounds(containing: epoch)
    }
  }
}
