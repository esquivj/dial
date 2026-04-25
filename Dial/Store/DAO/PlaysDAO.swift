// Dial/Store/DAO/PlaysDAO.swift
import GRDB
import Foundation

struct PlaysDAO {
  let dbq: DatabaseQueue

  func insert(_ play: Play) throws {
    var p = play
    try dbq.write { db in try p.insert(db) }
  }
  func playsFor(trackUri: String) throws -> [Play] {
    try dbq.read { db in
      try Play.filter(Play.Columns.trackUri == trackUri)
        .order(Play.Columns.playedAt.desc)
        .fetchAll(db)
    }
  }
  func recent(limit: Int) throws -> [Play] {
    try dbq.read { db in
      try Play.order(Play.Columns.playedAt.desc).limit(limit).fetchAll(db)
    }
  }
}
