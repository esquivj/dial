// DialTests/Sync/ArchiveExporterTests.swift
import XCTest
import GRDB
@testable import Dial

final class ArchiveExporterTests: XCTestCase {
  private var directory: URL!
  private let mac = MacIdentity(id: "0123456789abcdef", name: "First Mac")

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Dial.ArchiveExporterTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func test_export_includesCommitsStillInTheWAL_andAddsArchiveInfo() throws {
    let archiveURL = directory.appendingPathComponent("dial.sqlite")
    let live = try DatabaseStack(url: archiveURL).dbq
    try live.write { db in
      try db.execute(sql: """
        INSERT INTO plays (played_at, track_uri, ms_played, source)
        VALUES (1700000000, 'spotify:track:A', 31000, 'live'),
               (1700000400, 'spotify:track:B', 31000, 'live')
        """)
    }
    // Dial still has the archive open, so those commits sit in the WAL.
    XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path + "-wal"))

    let snapshotURL = directory.appendingPathComponent("first-mac.dialarchive")
    let info = try ArchiveExporter.export(archiveAt: archiveURL, to: snapshotURL, mac: mac, now: 1_800_000_000)

    XCTAssertEqual(info, ArchiveInfo(
      macId: mac.id,
      macName: "First Mac",
      exportedAt: 1_800_000_000,
      lastMigration: Migrations.register().migrations.last,
      playCount: 2))
    let snapshot = try DatabaseQueue(path: snapshotURL.path)
    try snapshot.read { db in
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays"), 2)
      XCTAssertEqual(try ArchiveInfo.read(from: db), info)
      XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA journal_mode"), "delete")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path + "-wal"))
    let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func test_export_neverOverwritesAFile() throws {
    let archiveURL = directory.appendingPathComponent("dial.sqlite")
    _ = try DatabaseStack(url: archiveURL)
    let snapshotURL = directory.appendingPathComponent("taken.dialarchive")
    try Data("keep me".utf8).write(to: snapshotURL)

    XCTAssertThrowsError(try ArchiveExporter.export(archiveAt: archiveURL, to: snapshotURL, mac: mac)) { error in
      XCTAssertEqual(error as? ArchiveError, .destinationExists(snapshotURL.path))
    }
    XCTAssertEqual(try String(contentsOf: snapshotURL, encoding: .utf8), "keep me")
  }

  func test_export_withoutAnArchive_saysSo() {
    let missing = directory.appendingPathComponent("nothing.sqlite")
    let snapshotURL = directory.appendingPathComponent("out.dialarchive")

    XCTAssertThrowsError(try ArchiveExporter.export(archiveAt: missing, to: snapshotURL, mac: mac)) { error in
      XCTAssertEqual(error as? ArchiveError, .missingFile(missing.path))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }
}
