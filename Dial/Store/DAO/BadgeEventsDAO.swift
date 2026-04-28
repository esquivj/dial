// Dial/Store/DAO/BadgeEventsDAO.swift
import Foundation
import GRDB

struct BadgeEventsDAO {
  let dbq: DatabaseQueue

  func recent(limit: Int = 20) throws -> [BadgeEvent] {
    try dbq.read { db in
      try BadgeEvent
        .order(BadgeEvent.Columns.earnedAt.desc, BadgeEvent.Columns.id.desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func count(kind: BadgeMemoryKind) throws -> Int {
    try dbq.read { db in
      try BadgeEvent
        .filter(BadgeEvent.Columns.kind == kind.rawValue)
        .fetchCount(db)
    }
  }

  static func insertIgnoring(_ event: BadgeEvent, in db: Database) throws {
    try db.execute(sql: """
      INSERT OR IGNORE INTO badge_events
        (kind, category, track_uri, artist_uri, album_name, earned_at, payload_json, scope_key)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        event.kind.rawValue,
        event.category.rawValue,
        event.trackUri,
        event.artistUri,
        event.albumName,
        event.earnedAt,
        event.payloadJson,
        event.scopeKey,
      ])
  }
}
