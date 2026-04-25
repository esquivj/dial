// Dial/Store/DAO/PetStateDAO.swift
import GRDB
import Foundation

struct PetStateDAO {
  let dbq: DatabaseQueue
  func get() throws -> PetState {
    try dbq.read { db in
      guard let s = try PetState.fetchOne(db, key: 1) else {
        throw NSError(domain: "Dial.Store", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing pet_state singleton"])
      }
      return s
    }
  }
  func update(_ mutate: (inout PetState) -> Void) throws {
    try dbq.write { db in
      var s = try PetState.fetchOne(db, key: 1)!
      mutate(&s)
      try s.update(db)
    }
  }
  /// In-transaction variant used by `PetEngine` from inside a larger write.
  func update(in db: Database, _ mutate: (inout PetState) -> Void) throws {
    var s = try PetState.fetchOne(db, key: 1)!
    mutate(&s)
    try s.update(db)
  }
}
