// Dial/Store/DatabaseStack.swift
import GRDB
import Foundation

final class DatabaseStack {
  let dbq: DatabaseQueue

  init(url: URL) throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
    // WAL = better crash recovery + concurrent reads while a writer commits.
    // Busy timeout protects against SQLITE_BUSY if a debugger / external sqlite3 touches the file.
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      try db.execute(sql: "PRAGMA busy_timeout = 500")
    }
    dbq = try DatabaseQueue(path: url.path, configuration: config)
    try Migrations.register().migrate(dbq)
  }

  static func defaultURL() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dial", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("dial.sqlite")
  }
}
