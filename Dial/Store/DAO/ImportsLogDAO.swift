// Dial/Store/DAO/ImportsLogDAO.swift
import GRDB
import Foundation

struct ImportLogEntry: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
  var id: Int64?
  var importedAt: Int64
  var sourcePath: String?
  var rowsInserted: Int64
  var notes: String?

  enum CodingKeys: String, CodingKey {
    case id
    case importedAt   = "imported_at"
    case sourcePath   = "source_path"
    case rowsInserted = "rows_inserted"
    case notes
  }
  static let databaseTableName = "imports_log"
  mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct ImportsLogDAO {
  let dbq: DatabaseQueue
  func record(path: String, rows: Int, notes: String? = nil) throws {
    var e = ImportLogEntry(importedAt: Int64(Date().timeIntervalSince1970),
                           sourcePath: path, rowsInserted: Int64(rows), notes: notes)
    try dbq.write { db in try e.insert(db) }
  }
  func last() throws -> ImportLogEntry? {
    try dbq.read { db in try ImportLogEntry.order(Column("imported_at").desc).fetchOne(db) }
  }
}
