// Dial/Sync/ArchiveExporter.swift
import Foundation
import GRDB

/// What an exported archive says about itself: the `dial_archive_info` row
/// `ArchiveExporter` adds. A plain `VACUUM INTO` copy has none.
struct ArchiveInfo: Equatable {
  static let tableName = "dial_archive_info"

  var macId: String
  var macName: String
  var exportedAt: Int64
  var lastMigration: String?
  var playCount: Int

  func write(to db: Database) throws {
    try db.execute(sql: """
      CREATE TABLE \(Self.tableName) (
        mac_id TEXT NOT NULL,
        mac_name TEXT NOT NULL,
        exported_at INTEGER NOT NULL,
        last_migration TEXT,
        play_count INTEGER NOT NULL)
      """)
    try db.execute(
      sql: "INSERT INTO \(Self.tableName) VALUES (?, ?, ?, ?, ?)",
      arguments: [macId, macName, exportedAt, lastMigration, playCount])
  }

  /// The info row in `schema` ("main" or an attached database), if any.
  static func read(from db: Database, schema: String = "main") throws -> ArchiveInfo? {
    guard try db.tableExists(tableName, in: schema),
          let row = try Row.fetchOne(db, sql: "SELECT * FROM \(schema).\(tableName) LIMIT 1")
    else { return nil }
    return ArchiveInfo(
      macId: row["mac_id"],
      macName: row["mac_name"],
      exportedAt: row["exported_at"],
      lastMigration: row["last_migration"],
      playCount: row["play_count"])
  }
}

enum ArchiveError: Error, Equatable, CustomStringConvertible {
  case missingFile(String)
  case destinationExists(String)
  case notAnArchive(String)
  case historyExport(String)
  case damaged(String)
  case newerSchema([String])
  case sameMac
  case archiveChanged
  case checkFailed(String)

  var description: String {
    switch self {
    case let .missingFile(path):
      return "No file at \(path)."
    case let .destinationExists(path):
      return "\(path) already exists. Choose a new file name."
    case let .notAnArchive(name):
      return "\(name) isn't a Dial archive."
    case let .historyExport(name):
      return "\(name) is a Dial History export, which has plays but no memories or pet. "
        + "Merge a full copy of the other Mac's dial.sqlite instead."
    case let .damaged(detail):
      return "The snapshot failed its integrity check: \(detail)"
    case let .newerSchema(migrations):
      return "The snapshot comes from a newer Dial (\(migrations.joined(separator: ", "))). Update Dial on this Mac first."
    case .sameMac:
      return "That snapshot came from this Mac."
    case .archiveChanged:
      return "Dial recorded new plays during the merge. Quit Dial and run the merge again."
    case let .checkFailed(detail):
      return "The merged copy failed a check (\(detail)). Nothing was changed."
    }
  }
}

enum ArchiveFiles {
  /// A consistent single-file copy of the database at `source`, including
  /// commits still in its WAL. Reads through a read-only connection, so it's
  /// safe while Dial runs. The copy uses a rollback journal: no sidecars.
  static func vacuumCopy(from source: URL, to destination: URL) throws {
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw ArchiveError.missingFile(source.path)
    }
    var config = Configuration()
    config.readonly = true
    config.busyMode = .timeout(10)
    let dbq = try DatabaseQueue(path: source.path, configuration: config)
    try dbq.inDatabase { db in
      try db.execute(sql: "VACUUM INTO ?", arguments: [destination.path])
    }
    try dbq.close()
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
  }
}

/// Writes a snapshot of the archive for another Mac to merge
/// (`Dial --export-archive <file>`, docs/design/multi-mac-history.md).
enum ArchiveExporter {
  @discardableResult
  static func export(
    archiveAt source: URL,
    to destination: URL,
    mac: MacIdentity = .current(),
    now: Int64 = Int64(Date().timeIntervalSince1970)
  ) throws -> ArchiveInfo {
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ArchiveError.destinationExists(destination.path)
    }
    try ArchiveFiles.vacuumCopy(from: source, to: destination)
    do {
      let dbq = try DatabaseQueue(path: destination.path)
      let info = try dbq.write { db in
        let info = ArchiveInfo(
          macId: mac.id,
          macName: mac.name,
          exportedAt: now,
          lastMigration: try String.fetchOne(
            db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1"),
          playCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays") ?? 0)
        try info.write(to: db)
        return info
      }
      try dbq.close()
      return info
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
}
