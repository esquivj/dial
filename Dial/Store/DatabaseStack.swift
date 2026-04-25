// Dial/Store/DatabaseStack.swift
import GRDB
import Foundation

final class DatabaseStack {
  let dbq: DatabaseQueue

  init(url: URL) throws {
    var config = Configuration()
    config.foreignKeysEnabled = true
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
