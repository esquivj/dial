import Foundation
import GRDB

struct PetTrickUnlocksDAO {
  let dbq: DatabaseQueue
  var now: () -> Int64 = { Int64(Date().timeIntervalSince1970) }

  func all() throws -> [PetTrickUnlock] {
    try dbq.read { db in
      try PetTrickUnlock
        .order(Column("unlocked_at").desc)
        .fetchAll(db)
    }
  }

  @discardableResult
  func unlock(_ trick: PetTrick, sourceBadge: BadgeMemoryKind? = nil) throws -> Bool {
    try dbq.write { db in
      let changesBefore = db.totalChangesCount
      try db.execute(sql: """
        INSERT OR IGNORE INTO pet_trick_unlocks (trick, unlocked_at, source_badge)
        VALUES (?, ?, ?)
        """, arguments: [trick.rawValue, now(), sourceBadge?.rawValue])
      return db.totalChangesCount > changesBefore
    }
  }
}
