// Dial/Sync/MemoryRebuilder.swift
import Foundation
import GRDB

/// Re-judges every memory from a date on under the current rules
/// (`Dial --rebuild-memories <yyyy-MM-dd>`), for when a badge rule changes
/// (PLA-95). It runs the same `MemoryReplay` a merge uses, then recomputes
/// the weekly memories and rebuilds artifacts.
///
/// Plays, the pet and taught tricks are untouched. Like a merge, it works on
/// a copy: a dry run reports and throws the copy away, and a real run backs
/// the archive up and swaps the copy in. A real run needs Dial quit; the
/// caller checks.
struct MemoryRebuilder {
  struct Report: Equatable {
    var dryRun: Bool
    var from: Int64
    var playsReplayed = 0
    var before = ArchiveMerger.Totals()
    var after = ArchiveMerger.Totals()
    /// Memory counts by kind from `from` on, before and after.
    var kindsBefore: [String: Int] = [:]
    var kindsAfter: [String: Int] = [:]
    var backupURL: URL?
  }

  let archiveURL: URL
  let from: Int64
  var dryRun = false
  var now: Int64 = Int64(Date().timeIntervalSince1970)
  var log: (String) -> Void = { _ in }

  /// Local midnight of a `yyyy-MM-dd` date, or nil.
  static func startOfDay(_ text: String, calendar: Calendar = .current) -> Int64? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: text) else { return nil }
    return Int64(calendar.startOfDay(for: date).timeIntervalSince1970)
  }

  func run() throws -> Report {
    let fileManager = FileManager.default
    let stamp = ArchiveMerger.fileStamp(now)
    let dialFolder = archiveURL.deletingLastPathComponent()
    let workFolder = dialFolder.appendingPathComponent("Rebuilding", isDirectory: true)
      .appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try fileManager.createDirectory(
      at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer {
      try? fileManager.removeItem(at: workFolder)
      let parent = workFolder.deletingLastPathComponent()
      if (try? fileManager.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
        try? fileManager.removeItem(at: parent)
      }
    }

    let fingerprint = try ArchiveMerger.fingerprint(of: archiveURL)
    let working = workFolder.appendingPathComponent("working.sqlite")
    try ArchiveFiles.vacuumCopy(from: archiveURL, to: working)
    var report = try rebuild(working: working, scratch: workFolder.appendingPathComponent("replay.sqlite"))

    guard !dryRun else { return report }

    guard try ArchiveMerger.fingerprint(of: archiveURL) == fingerprint else {
      throw ArchiveError.archiveChanged
    }
    let backups = dialFolder.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(
      at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var backup = backups.appendingPathComponent("dial-before-rebuild-\(stamp).sqlite")
    var attempt = 1
    while fileManager.fileExists(atPath: backup.path) {
      attempt += 1
      backup = backups.appendingPathComponent("dial-before-rebuild-\(stamp)-\(attempt).sqlite")
    }
    try ArchiveFiles.vacuumCopy(from: archiveURL, to: backup)
    try ArchiveMerger.swap(working, into: archiveURL)
    report.backupURL = backup
    log("→ Backed up the archive to \(backup.path)")
    return report
  }

  private func rebuild(working: URL, scratch: URL) throws -> Report {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let dbq = try DatabaseQueue(path: working.path, configuration: config)
    defer { try? dbq.close() }
    try Migrations.register().migrate(dbq)

    var report = Report(dryRun: dryRun, from: from)
    report.before = try dbq.read(ArchiveMerger.totals)
    report.kindsBefore = try dbq.read(kinds)

    log("→ Replaying memories from \(ArchiveMerger.describe(from))")
    let started = Date()
    let log = self.log
    let replay = try MemoryReplay.run(on: dbq, from: from, scratchURL: scratch) { done, total in
      guard done % 500 == 0 || done == total else { return }
      let elapsed = Date().timeIntervalSince(started)
      let left = done > 0 ? elapsed / Double(done) * Double(total - done) : 0
      log(String(format: "  replayed %d of %d plays (%.0f s, about %.0f s left)", done, total, elapsed, left))
    }
    report.playsReplayed = replay.playsReplayed

    try dbq.write { db in
      // Artifacts are fully derived from memories and tricks: rebuilt below.
      try db.execute(sql: "DELETE FROM main.artifacts")
      try db.execute(sql: "DELETE FROM main.badge_events WHERE earned_at >= ?", arguments: [from])
      for event in replay.events {
        try BadgeEventsDAO.insertIgnoring(event, in: db)
      }
    }
    try ArchiveMerger.recomputeWeeks(dbq, endingAfter: from, now: now)
    try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()

    report.after = try dbq.read(ArchiveMerger.totals)
    report.kindsAfter = try dbq.read(kinds)
    try dbq.read { db in
      let check = try String.fetchAll(db, sql: "PRAGMA main.integrity_check")
      guard check == ["ok"] else {
        throw ArchiveError.checkFailed(check.prefix(3).joined(separator: "; "))
      }
    }
    guard report.after.plays == report.before.plays, report.after.xp == report.before.xp else {
      throw ArchiveError.checkFailed("the rebuild changed plays or pet XP")
    }
    return report
  }

  private func kinds(_ db: Database) throws -> [String: Int] {
    let rows = try Row.fetchAll(db, sql: """
      SELECT kind, COUNT(*) AS n FROM main.badge_events WHERE earned_at >= ? GROUP BY kind
      """, arguments: [from])
    return Dictionary(uniqueKeysWithValues: rows.map { ($0["kind"] as String, $0["n"] as Int) })
  }
}

extension MemoryRebuilder.Report {
  /// What the CLI prints when the rebuild is done.
  func summaryLines() -> [String] {
    var lines = [
      "→ Replayed \(playsReplayed.formatted()) plays from \(ArchiveMerger.describe(from))",
      "→ Memories \(before.memories.formatted()) → \(after.memories.formatted())"
        + " · Artifacts \(before.artifacts.formatted()) → \(after.artifacts.formatted())"
        + " · Weekly memories \(before.weeklyMemories) → \(after.weeklyMemories)",
    ]
    for kind in Set(kindsBefore.keys).union(kindsAfter.keys).sorted() {
      let old = kindsBefore[kind] ?? 0
      let new = kindsAfter[kind] ?? 0
      if old != new {
        lines.append("    \(kind): \(old.formatted()) → \(new.formatted())")
      }
    }
    lines.append("→ Plays and pet unchanged (\(after.plays.formatted()) plays, \(after.xp.formatted()) XP)")
    lines.append(dryRun
      ? "✓ Dry run: nothing changed. Run again without --dry-run to rebuild."
      : "✓ Rebuilt. Backup: \(backupURL?.path ?? "none")")
    return lines
  }
}
