// Dial/Store/DAO/TracksDAO.swift
import GRDB
import Foundation

struct TracksDAO {
  let dbq: DatabaseQueue
  func upsert(_ t: Track) throws { try dbq.write { db in try t.save(db) } }
  func fetch(uri: String) throws -> Track? {
    try dbq.read { db in try Track.fetchOne(db, key: uri) }
  }
  func missingUris(among uris: [String]) throws -> [String] {
    guard !uris.isEmpty else { return [] }
    return try dbq.read { db in
      let placeholders = uris.map { _ in "?" }.joined(separator: ",")
      let present = try String.fetchAll(db,
        sql: "SELECT uri FROM tracks WHERE uri IN (\(placeholders))",
        arguments: StatementArguments(uris))
      let set = Set(present)
      return uris.filter { !set.contains($0) }
    }
  }
}
