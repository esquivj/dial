// Dial/Store/DAO/ArtistsDAO.swift
import GRDB
import Foundation

struct ArtistsDAO {
  let dbq: DatabaseQueue
  func upsert(_ a: Artist) throws { try dbq.write { db in try a.mergeUpsert(db) } }
  func fetch(uri: String) throws -> Artist? { try dbq.read { db in try Artist.fetchOne(db, key: uri) } }
}
