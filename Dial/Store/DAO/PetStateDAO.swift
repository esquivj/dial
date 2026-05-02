// Dial/Store/DAO/PetStateDAO.swift
import GRDB
import Foundation

struct PetStateDAO {
  let dbq: DatabaseQueue

  static func singleton(in db: Database) throws -> PetState {
    if let state = try PetState.fetchOne(db, key: 1) {
      return state
    }

    let state = PetState(installedAt: Int64(Date().timeIntervalSince1970))
    try state.insert(db)
    return state
  }

  func get() throws -> PetState {
    try dbq.write { db in
      try Self.singleton(in: db)
    }
  }

  func update(_ mutate: (inout PetState) -> Void) throws {
    try dbq.write { db in
      var s = try Self.singleton(in: db)
      mutate(&s)
      try s.update(db)
    }
  }

  /// In-transaction variant used by `PetEngine` from inside a larger write.
  func update(in db: Database, _ mutate: (inout PetState) -> Void) throws {
    var s = try Self.singleton(in: db)
    mutate(&s)
    try s.update(db)
  }
}
