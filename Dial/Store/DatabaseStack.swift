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
    try Self.applyPrivatePermissions(toDatabaseAt: url)
  }

  static func defaultURL() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dial", isDirectory: true)
    try FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
    return base.appendingPathComponent("dial.sqlite")
  }

  private static func applyPrivatePermissions(toDatabaseAt url: URL) throws {
    let fileManager = FileManager.default
    let paths = [
      url.path,
      "\(url.path)-wal",
      "\(url.path)-shm",
    ]

    for path in paths where fileManager.fileExists(atPath: path) {
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
  }
}
