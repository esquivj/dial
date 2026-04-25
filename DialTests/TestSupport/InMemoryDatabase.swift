// DialTests/TestSupport/InMemoryDatabase.swift
import GRDB
@testable import Dial

enum InMemoryDatabase {
  static func make() throws -> DatabaseQueue {
    let dbq = try DatabaseQueue()
    try Migrations.register().migrate(dbq)
    return dbq
  }
}
