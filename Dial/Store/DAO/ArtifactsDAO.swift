import Foundation
import GRDB

struct ArtifactsDAO {
  let dbq: DatabaseQueue

  func all() throws -> [Artifact] {
    try dbq.read { db in
      try Artifact
        .order(Artifact.Columns.unlockedAt.desc, Artifact.Columns.kind.asc)
        .fetchAll(db)
    }
  }

  @discardableResult
  func syncFromMemoriesAndTricks() throws -> [Artifact] {
    try dbq.write { db in
      try syncBadgeArtifacts(in: db)
      try syncTrickArtifacts(in: db)
      return try Artifact
        .order(Artifact.Columns.unlockedAt.desc, Artifact.Columns.kind.asc)
        .fetchAll(db)
    }
  }

  private func syncBadgeArtifacts(in db: Database) throws {
    var unlockedKinds = Set<ArtifactKind>()
    let events = try BadgeEvent
      .order(BadgeEvent.Columns.earnedAt.asc, BadgeEvent.Columns.id.asc)
      .fetchAll(db)

    for event in events {
      guard let kind = ArtifactKind(badgeKind: event.kind),
            unlockedKinds.insert(kind).inserted
      else { continue }

      try insertIgnoring(
        Artifact(
          kind: kind,
          source: .badge,
          unlockedAt: event.earnedAt,
          sourceBadgeEventId: event.id,
          trackUri: event.trackUri,
          artistUri: event.artistUri,
          detail: event.kind.label),
        in: db)
    }
  }

  private func syncTrickArtifacts(in db: Database) throws {
    let rows = try Row.fetchAll(db, sql: """
      SELECT trick, unlocked_at
      FROM pet_trick_unlocks
      ORDER BY unlocked_at ASC
      """)

    for row in rows {
      let rawTrick: String = row["trick"]
      let unlockedAt: Int64 = row["unlocked_at"]
      guard let trick = PetTrick(rawValue: rawTrick),
            let kind = ArtifactKind(trick: trick)
      else { continue }

      try insertIgnoring(
        Artifact(
          kind: kind,
          source: .trick,
          unlockedAt: unlockedAt,
          sourceBadgeEventId: nil,
          trackUri: nil,
          artistUri: nil,
          detail: trick.label),
        in: db)
    }
  }

  private func insertIgnoring(_ artifact: Artifact, in db: Database) throws {
    try db.execute(sql: """
      INSERT OR IGNORE INTO artifacts
        (kind, source, unlocked_at, source_badge_event_id, track_uri, artist_uri, detail)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """, arguments: [
        artifact.kind.rawValue,
        artifact.source.rawValue,
        artifact.unlockedAt,
        artifact.sourceBadgeEventId,
        artifact.trackUri,
        artifact.artistUri,
        artifact.detail,
      ])
  }
}
