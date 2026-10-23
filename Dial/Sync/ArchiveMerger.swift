// Dial/Sync/ArchiveMerger.swift
import Foundation
import GRDB

/// Merges another Mac's archive into this one (`Dial --merge-archive`),
/// following docs/design/multi-mac-history.md, "Merge rules".
///
/// The archive itself is only read. Every step runs on a working copy: a dry
/// run reports and throws the copy away, and a real merge backs the archive
/// up and swaps the copy in only after it passes its checks. A real merge
/// needs Dial quit; the caller checks.
struct ArchiveMerger {
  struct Options {
    var dryRun = false
    /// Names a snapshot that has no `dial_archive_info`, such as a plain
    /// `VACUUM INTO` copy of another Mac's `dial.sqlite`. Defaults to the
    /// file name.
    var sourceName: String?
    var mac: MacIdentity = .current()
    var now: Int64 = Int64(Date().timeIntervalSince1970)
    var log: (String) -> Void = { _ in }
  }

  /// Whose memories and pet the merge keeps up to the replay point.
  enum Donor: String {
    case here
    case snapshot
  }

  struct Totals: Equatable {
    var plays = 0
    var memories = 0
    var artifacts = 0
    var tricks = 0
    var weeklyMemories = 0
    var xp: Int64 = 0
    var stage: PetStage = .egg
  }

  struct Report: Equatable {
    var dryRun: Bool
    var sourceName: String
    var sourceExportedAt: Int64?
    var snapshotPlays = 0
    var addedBySource: [String: Int] = [:]
    var alreadyHere = 0
    /// The earliest counted play this Mac lacked, and the earliest one the
    /// snapshot lacked. Nil means it lacked none.
    var firstLackedHere: Int64?
    var firstLackedThere: Int64?
    var donor: Donor = .here
    var replayFrom: Int64?
    var playsReplayed = 0
    var before = Totals()
    var after = Totals()
    var backupURL: URL?

    var playsAdded: Int { addedBySource.values.reduce(0, +) }
  }

  let archiveURL: URL
  let snapshotURL: URL
  var options = Options()

  func run() throws -> Report {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: snapshotURL.path) else {
      throw ArchiveError.missingFile(snapshotURL.path)
    }
    let stamp = Self.fileStamp(options.now)
    let dialFolder = archiveURL.deletingLastPathComponent()
    let mergingFolder = dialFolder.appendingPathComponent("Merging", isDirectory: true)
    let workFolder = mergingFolder
      .appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try fileManager.createDirectory(
      at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer {
      try? fileManager.removeItem(at: workFolder)
      if (try? fileManager.contentsOfDirectory(atPath: mergingFolder.path))?.isEmpty == true {
        try? fileManager.removeItem(at: mergingFolder)
      }
    }

    options.log("→ Reading \(snapshotURL.lastPathComponent)")
    let snapshotCopy = workFolder.appendingPathComponent("snapshot.sqlite")
    do {
      try ArchiveFiles.vacuumCopy(from: snapshotURL, to: snapshotCopy)
    } catch is DatabaseError {
      throw ArchiveError.notAnArchive(snapshotURL.lastPathComponent)
    }

    let fingerprint = try Self.fingerprint(of: archiveURL)
    let working = workFolder.appendingPathComponent("working.sqlite")
    try ArchiveFiles.vacuumCopy(from: archiveURL, to: working)
    var report = try Self.mergeAndCheck(
      workingCopy: working,
      snapshotCopy: snapshotCopy,
      scratchFolder: workFolder,
      merger: self)

    guard !options.dryRun else { return report }

    guard try Self.fingerprint(of: archiveURL) == fingerprint else {
      throw ArchiveError.archiveChanged
    }
    let backups = dialFolder.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(
      at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var backup = backups.appendingPathComponent("dial-before-merge-\(stamp).sqlite")
    var attempt = 1
    while fileManager.fileExists(atPath: backup.path) {
      attempt += 1
      backup = backups.appendingPathComponent("dial-before-merge-\(stamp)-\(attempt).sqlite")
    }
    try ArchiveFiles.vacuumCopy(from: archiveURL, to: backup)
    try Self.swap(working, into: archiveURL)
    report.backupURL = backup
    options.log("→ Backed up the archive to \(backup.path)")
    return report
  }

  private static func mergeAndCheck(
    workingCopy: URL,
    snapshotCopy: URL,
    scratchFolder: URL,
    merger: ArchiveMerger
  ) throws -> Report {
    var config = Configuration()
    config.foreignKeysEnabled = true
    let dbq = try DatabaseQueue(path: workingCopy.path, configuration: config)
    try Migrations.register().migrate(dbq)
    let report = try merger.merge(into: dbq, snapshotCopy: snapshotCopy, scratchFolder: scratchFolder)
    try dbq.read { db in
      let check = try String.fetchAll(db, sql: "PRAGMA main.integrity_check")
      guard check == ["ok"] else {
        throw ArchiveError.checkFailed(check.prefix(3).joined(separator: "; "))
      }
      let plays = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM main.plays") ?? 0
      let expected = report.before.plays + report.playsAdded
      guard plays == expected else {
        throw ArchiveError.checkFailed("expected \(expected) plays, found \(plays)")
      }
    }
    try dbq.close()
    return report
  }

  // MARK: - The merge

  private struct Source {
    let id: String
    let name: String
    let exportedAt: Int64?
  }

  private func merge(into dbq: DatabaseQueue, snapshotCopy: URL, scratchFolder: URL) throws -> Report {
    try dbq.inDatabase { db in
      try db.execute(sql: "ATTACH DATABASE ? AS snapshot", arguments: [snapshotCopy.path])
    }
    defer { try? dbq.inDatabase { db in try db.execute(sql: "DETACH DATABASE snapshot") } }

    let source = try dbq.read { db in try identifySource(db) }
    var report = Report(dryRun: options.dryRun, sourceName: source.name, sourceExportedAt: source.exportedAt)
    report.before = try dbq.read(Self.totals)
    report.snapshotPlays = try dbq.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshot.plays") ?? 0
    }
    options.log("→ Snapshot from \(source.name): \(report.snapshotPlays.formatted()) plays")

    // 1. Metadata, so durations and artists are known before plays.
    options.log("→ Merging tracks, artists and tags")
    try dbq.write { db in
      try Self.mergeMetadata(db)
      try ArtistIdentityRepair.rebuildAliases(in: db, now: options.now)
    }

    // 2. Plays, skipping every listen this Mac already holds.
    options.log("→ Merging plays")
    let durations = try dbq.read(Self.durations)
    try dbq.write { db in
      let result = try Self.mergePlays(db, durations: durations, sourceID: source.id)
      report.addedBySource = result.added
      report.alreadyHere = result.alreadyHere
    }

    // 3. Tricks you taught on either Mac.
    try dbq.write(Self.mergeTricks)

    // 4. Donor and replay point.
    report.firstLackedHere = try dbq.read { db in
      try Int64.fetchOne(db, sql: """
        SELECT MIN(played_at) FROM counted_plays WHERE id IN (SELECT id FROM temp.merge_added)
        """)
    }
    report.firstLackedThere = try dbq.read { db in
      try Self.playsTheSnapshotLacks(db, durations: durations, from: nil, all: false).first?.playedAt
    }
    (report.donor, report.replayFrom) = Self.chooseDonor(
      firstLackedHere: report.firstLackedHere,
      firstLackedThere: report.firstLackedThere,
      hereID: options.mac.id,
      thereID: source.id)
    let lacked: [PetMerge.Play]
    switch report.donor {
    case .here:
      lacked = try dbq.read { db in
        try Row.fetchAll(db, sql: """
          SELECT \(PetMerge.Play.columns)
          FROM counted_plays p
          LEFT JOIN tracks t ON t.uri = p.track_uri
          WHERE p.id IN (SELECT id FROM temp.merge_added)
          ORDER BY p.played_at, p.id
          """).map(PetMerge.Play.init(row:))
      }
    case .snapshot:
      lacked = try dbq.read { db in
        try Self.playsTheSnapshotLacks(db, durations: durations, from: report.firstLackedThere, all: true)
      }
    }

    // 5. Memories: the donor's up to the replay point, then replayed.
    try dbq.write { db in
      try Self.keepDonorMemories(db, donor: report.donor, before: report.replayFrom)
    }
    if let start = report.replayFrom {
      options.log("→ Replaying memories from \(Self.describe(start))")
      let replay = try MemoryReplay.run(
        on: dbq, from: start, scratchURL: scratchFolder.appendingPathComponent("replay.sqlite"))
      report.playsReplayed = replay.playsReplayed
      try dbq.write { db in
        for event in replay.events {
          try BadgeEventsDAO.insertIgnoring(event, in: db)
        }
      }
    }

    // 6. Pet.
    try dbq.write { db in
      let local = try PetStateDAO.singleton(in: db)
      let snapshotPet = try PetState.fetchOne(db, sql: "SELECT * FROM snapshot.pet_state WHERE id = 1")
      let merged = try PetMerge.merged(
        local: local,
        snapshot: snapshotPet,
        donorIsSnapshot: report.donor == .snapshot,
        lacked: lacked,
        in: db,
        now: options.now)
      try merged.update(db)
    }

    // 7. Weekly memories: the donor's, with weeks from the replay point on
    // recomputed. The app fills in missing recent weeks itself.
    try dbq.write { db in try Self.keepDonorWeeklyMemories(db, donor: report.donor) }
    if let start = report.replayFrom {
      try Self.recomputeWeeks(dbq, endingAfter: start, now: options.now)
    }

    // 8. Artifacts are fully derived: rebuild them.
    try dbq.write { db in try db.execute(sql: "DELETE FROM main.artifacts") }
    try ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()

    // 9. Log.
    try dbq.write { db in
      try db.execute(sql: """
        INSERT INTO main.archive_merges
          (merged_at, source_mac_id, source_mac_name, source_exported_at,
           plays_added, donor, replay_from, plays_replayed)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
          options.now, source.id, source.name, source.exportedAt,
          report.playsAdded, report.donor.rawValue, report.replayFrom, report.playsReplayed,
        ])
    }
    report.after = try dbq.read(Self.totals)
    return report
  }

  private func identifySource(_ db: Database) throws -> Source {
    let fileName = snapshotURL.lastPathComponent
    if try db.tableExists("dial_history_snapshot", in: "snapshot") {
      throw ArchiveError.historyExport(fileName)
    }
    let check = try String.fetchAll(db, sql: "PRAGMA snapshot.integrity_check")
    guard check == ["ok"] else {
      throw ArchiveError.damaged(check.prefix(3).joined(separator: "; "))
    }
    for table in ["plays", "tracks", "pet_state", "badge_events", "pet_trick_unlocks", "grdb_migrations"] {
      guard try db.tableExists(table, in: "snapshot") else { throw ArchiveError.notAnArchive(fileName) }
    }
    let known = Set(Migrations.register().migrations)
    let unknown = try String.fetchAll(db, sql: "SELECT identifier FROM snapshot.grdb_migrations")
      .filter { !known.contains($0) }
    guard unknown.isEmpty else { throw ArchiveError.newerSchema(unknown.sorted()) }

    if let info = try ArchiveInfo.read(from: db, schema: "snapshot") {
      guard info.macId != options.mac.id else { throw ArchiveError.sameMac }
      return Source(id: info.macId, name: info.macName, exportedAt: info.exportedAt)
    }
    let name = options.sourceName ?? snapshotURL.deletingPathExtension().lastPathComponent
    return Source(id: "unidentified:\(name)", name: name, exportedAt: nil)
  }

  /// The side whose first missing play comes later knew everything the
  /// other did up to that point: it's the donor, and memories replay from
  /// its first missing play. Ties go to the smaller Mac id, so both Macs
  /// choose the same donor.
  static func chooseDonor(
    firstLackedHere: Int64?,
    firstLackedThere: Int64?,
    hereID: String,
    thereID: String
  ) -> (Donor, Int64?) {
    switch (firstLackedHere, firstLackedThere) {
    case (nil, _):
      return (.here, nil)
    case (_, nil):
      return (.snapshot, nil)
    case let (here?, there?):
      if here > there { return (.here, here) }
      if there > here { return (.snapshot, there) }
      return (hereID <= thereID ? .here : .snapshot, here)
    }
  }

  // MARK: - Steps

  private static func mergeMetadata(_ db: Database) throws {
    func canonical(_ column: String) -> String {
      """
      (CASE WHEN json_valid(\(column)) = 1
            THEN COALESCE(json_extract(\(column), '$[0].uri'), '') ELSE '' END
       LIKE 'spotify:artist:%')
      """
    }
    // Fill blanks, never overwrite, except that real Spotify artist ids
    // replace the synthetic `artist:Name` ids imported history carries.
    try db.execute(sql: """
      INSERT INTO main.tracks AS here (uri, name, album_name, album_art_url, duration_ms, artists_json)
      SELECT uri, name, album_name, album_art_url, duration_ms, artists_json
      FROM snapshot.tracks WHERE true
      ON CONFLICT(uri) DO UPDATE SET
        name = COALESCE(NULLIF(here.name, ''), excluded.name),
        album_name = COALESCE(NULLIF(here.album_name, ''), excluded.album_name),
        album_art_url = COALESCE(here.album_art_url, excluded.album_art_url),
        duration_ms = COALESCE(NULLIF(here.duration_ms, 0), excluded.duration_ms),
        artists_json = CASE
          WHEN here.artists_json IS NULL THEN excluded.artists_json
          WHEN \(canonical("excluded.artists_json")) AND NOT \(canonical("here.artists_json"))
            THEN excluded.artists_json
          ELSE here.artists_json
        END
      """)
    if try db.tableExists("artists", in: "snapshot") {
      try db.execute(sql: """
        INSERT INTO main.artists AS here (uri, name, genres_json, image_url)
        SELECT uri, name, genres_json, image_url FROM snapshot.artists WHERE true
        ON CONFLICT(uri) DO UPDATE SET
          name = COALESCE(NULLIF(here.name, ''), excluded.name),
          genres_json = COALESCE(here.genres_json, excluded.genres_json),
          image_url = COALESCE(here.image_url, excluded.image_url)
        """)
    }
    // Tag caches: the newer lookup wins, row by row.
    if try db.tableExists("raw_tags", in: "snapshot") {
      try db.execute(sql: """
        INSERT INTO main.raw_tags AS here
          (entity_uri, entity_type, provider, raw_tag, score, rank, source_url, fetched_at)
        SELECT entity_uri, entity_type, provider, raw_tag, score, rank, source_url, fetched_at
        FROM snapshot.raw_tags WHERE true
        ON CONFLICT(entity_uri, entity_type, provider, raw_tag) DO UPDATE SET
          score = excluded.score, rank = excluded.rank,
          source_url = excluded.source_url, fetched_at = excluded.fetched_at
        WHERE excluded.fetched_at > here.fetched_at
        """)
    }
    if try db.tableExists("normalized_tags", in: "snapshot") {
      try db.execute(sql: """
        INSERT INTO main.normalized_tags AS here
          (entity_uri, entity_type, provider, family, raw_tag, score, updated_at)
        SELECT entity_uri, entity_type, provider, family, raw_tag, score, updated_at
        FROM snapshot.normalized_tags WHERE true
        ON CONFLICT(entity_uri, entity_type, provider, family, raw_tag) DO UPDATE SET
          score = excluded.score, updated_at = excluded.updated_at
        WHERE excluded.updated_at > here.updated_at
        """)
    }
    for table in ["tag_enrichment_state", "metadata_enrichment_state"] {
      guard try db.tableExists(table, in: "snapshot") else { continue }
      try db.execute(sql: """
        INSERT INTO main.\(table) AS here (entity_uri, entity_type, provider, status, fetched_at, error)
        SELECT entity_uri, entity_type, provider, status, fetched_at, error
        FROM snapshot.\(table) WHERE true
        ON CONFLICT(entity_uri, entity_type, provider) DO UPDATE SET
          status = excluded.status, fetched_at = excluded.fetched_at, error = excluded.error
        WHERE excluded.fetched_at > here.fetched_at
        """)
    }
  }

  private static func durations(_ db: Database) throws -> [String: Int64] {
    var durations: [String: Int64] = [:]
    let rows = try Row.fetchCursor(db, sql: "SELECT uri, duration_ms FROM main.tracks WHERE duration_ms > 0")
    while let row = try rows.next() {
      durations[row["uri"]] = row["duration_ms"]
    }
    return durations
  }

  /// Inserts the snapshot's plays oldest first, skipping any with a twin
  /// here (including twins this merge just added). New rows are remembered
  /// in `temp.merge_added`.
  private static func mergePlays(
    _ db: Database,
    durations: [String: Int64],
    sourceID: String
  ) throws -> (added: [String: Int], alreadyHere: Int) {
    try db.execute(sql: "CREATE TEMP TABLE IF NOT EXISTS merge_added (id INTEGER PRIMARY KEY)")
    let hasOrigin = try db.columns(in: "plays", in: "snapshot").contains { $0.name == "origin" }
    let rows = try Row.fetchCursor(db, sql: """
      SELECT played_at, track_uri, ms_played, source, \(hasOrigin ? "origin" : "NULL") AS origin
      FROM snapshot.plays
      ORDER BY played_at, id
      """)
    // A first merge can insert hundreds of thousands of rows: prepare once.
    let insertPlay = try db.cachedStatement(sql: """
      INSERT INTO main.plays (played_at, track_uri, ms_played, source, origin) VALUES (?, ?, ?, ?, ?)
      """)
    let rememberPlay = try db.cachedStatement(sql: "INSERT INTO temp.merge_added (id) VALUES (?)")
    var added: [String: Int] = [:]
    var alreadyHere = 0
    while let row = try rows.next() {
      let trackUri: String = row["track_uri"]
      let stamp = PlayTwinMatcher.Stamp(
        playedAt: row["played_at"], msPlayed: row["ms_played"], source: row["source"])
      if try PlayTwinMatcher.twinExists(
        of: stamp, trackUri: trackUri, durationMs: durations[trackUri], in: "main", db: db) {
        alreadyHere += 1
        continue
      }
      // A play keeps the id of the Mac that first recorded it.
      let origin = (row["origin"] as String?) ?? sourceID
      try insertPlay.execute(arguments: [stamp.playedAt, trackUri, stamp.msPlayed, stamp.source, origin])
      try rememberPlay.execute(arguments: [db.lastInsertedRowID])
      added[stamp.source, default: 0] += 1
    }
    return (added, alreadyHere)
  }

  /// Counted plays already here that have no twin in the snapshot, oldest
  /// first. With `all` false it stops at the first one.
  private static func playsTheSnapshotLacks(
    _ db: Database,
    durations: [String: Int64],
    from start: Int64?,
    all: Bool
  ) throws -> [PetMerge.Play] {
    let rows = try Row.fetchCursor(db, sql: """
      SELECT id, played_at, track_uri, ms_played, source
      FROM counted_plays
      WHERE id NOT IN (SELECT id FROM temp.merge_added) AND played_at >= ?
      ORDER BY played_at, id
      """, arguments: [start ?? Int64.min])
    var lacked: [PetMerge.Play] = []
    while let row = try rows.next() {
      let trackUri: String = row["track_uri"]
      let stamp = PlayTwinMatcher.Stamp(
        playedAt: row["played_at"], msPlayed: row["ms_played"], source: row["source"])
      if try PlayTwinMatcher.twinExists(
        of: stamp, trackUri: trackUri, durationMs: durations[trackUri], in: "snapshot", db: db) {
        continue
      }
      let id: Int64 = row["id"]
      if let play = try Row.fetchOne(db, sql: """
        SELECT \(PetMerge.Play.columns)
        FROM plays p LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE p.id = ?
        """, arguments: [id]) {
        lacked.append(PetMerge.Play(row: play))
      }
      if !all { break }
    }
    return lacked
  }

  private static func mergeTricks(_ db: Database) throws {
    let known = PetTrick.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    try db.execute(sql: """
      INSERT INTO main.pet_trick_unlocks AS here (trick, unlocked_at, source_badge)
      SELECT trick, unlocked_at, source_badge
      FROM snapshot.pet_trick_unlocks
      WHERE trick IN (\(known))
      ON CONFLICT(trick) DO UPDATE SET
        unlocked_at = MIN(here.unlocked_at, excluded.unlocked_at),
        source_badge = CASE WHEN excluded.unlocked_at < here.unlocked_at
                            THEN excluded.source_badge ELSE here.source_badge END
      """)
  }

  private static func keepDonorMemories(_ db: Database, donor: Donor, before start: Int64?) throws {
    switch donor {
    case .here:
      if let start {
        try db.execute(sql: "DELETE FROM main.badge_events WHERE earned_at >= ?", arguments: [start])
      }
    case .snapshot:
      // Only kinds this build knows, in case the other Mac runs a newer Dial.
      let kinds = BadgeMemoryKind.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
      try db.execute(sql: "DELETE FROM main.badge_events")
      try db.execute(sql: """
        INSERT OR IGNORE INTO main.badge_events
          (kind, category, track_uri, artist_uri, album_name, earned_at, payload_json, scope_key)
        SELECT kind, category, track_uri, artist_uri, album_name, earned_at, payload_json, scope_key
        FROM snapshot.badge_events
        WHERE kind IN (\(kinds)) AND earned_at < ?
        ORDER BY earned_at, id
        """, arguments: [start ?? Int64.max])
    }
  }

  private static func keepDonorWeeklyMemories(_ db: Database, donor: Donor) throws {
    guard donor == .snapshot, try db.tableExists("weekly_memories", in: "snapshot") else { return }
    let columns = """
      week_start, week_end, trait, memento, recap_line, room_object_name, dominant_genre,
      theme, play_count, listening_ms, unique_artists, new_artists, created_at, updated_at
      """
    try db.execute(sql: "DELETE FROM main.weekly_memories")
    try db.execute(sql: """
      INSERT INTO main.weekly_memories (\(columns)) SELECT \(columns) FROM snapshot.weekly_memories
      """)
  }

  private static func recomputeWeeks(_ dbq: DatabaseQueue, endingAfter start: Int64, now: Int64) throws {
    let weeks = try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT week_start, week_end FROM main.weekly_memories WHERE week_end > ? ORDER BY week_start
        """, arguments: [start])
    }
    let stats = StatsQueries(dbq: dbq)
    let memories = WeeklyMemoriesDAO(dbq: dbq, now: { now })
    for week in weeks {
      if let memory = try stats.weeklyMemory(weekStart: week["week_start"], weekEnd: week["week_end"]) {
        try memories.upsert(memory, now: now)
      }
    }
  }

  private static func totals(_ db: Database) throws -> Totals {
    func count(_ table: String) throws -> Int {
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM main.\(table)") ?? 0
    }
    let pet = try PetState.fetchOne(db, sql: "SELECT * FROM main.pet_state WHERE id = 1")
    return Totals(
      plays: try count("plays"),
      memories: try count("badge_events"),
      artifacts: try count("artifacts"),
      tricks: try count("pet_trick_unlocks"),
      weeklyMemories: try count("weekly_memories"),
      xp: pet?.xp ?? 0,
      stage: pet?.stage ?? .egg)
  }

  // MARK: - Files

  /// Changes whenever Dial records something. A real merge refuses to swap
  /// if the archive changed after its working copy was taken.
  private static func fingerprint(of archive: URL) throws -> String {
    var config = Configuration()
    config.readonly = true
    config.busyMode = .timeout(10)
    let dbq = try DatabaseQueue(path: archive.path, configuration: config)
    defer { try? dbq.close() }
    return try dbq.read { db in
      try Int64.fetchAll(db, sql: """
        SELECT COUNT(*) FROM plays
        UNION ALL SELECT COALESCE(MAX(id), 0) FROM plays
        UNION ALL SELECT COALESCE(MAX(id), 0) FROM badge_events
        UNION ALL SELECT COALESCE(MAX(xp), 0) FROM pet_state
        """).map(String.init).joined(separator: ":")
    }
  }

  private static func swap(_ working: URL, into archive: URL) throws {
    let fileManager = FileManager.default
    // The old WAL belongs to the old file. Its commits are already in the
    // working copy, and SQLite must never replay it into the new one.
    for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: archive.path + suffix) {
      try fileManager.removeItem(atPath: archive.path + suffix)
    }
    _ = try fileManager.replaceItemAt(archive, withItemAt: working)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
  }

  private static func fileStamp(_ unix: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
  }

  static func describe(_ unix: Int64) -> String {
    Date(timeIntervalSince1970: TimeInterval(unix)).formatted(date: .abbreviated, time: .shortened)
  }
}

extension ArchiveMerger.Report {
  /// What the CLI prints when the merge is done.
  func summaryLines() -> [String] {
    let exported = sourceExportedAt.map { ", exported \(ArchiveMerger.describe($0))" } ?? ""
    let bySource = addedBySource.sorted { $0.key < $1.key }
      .map { "\($0.key) \($0.value.formatted())" }
      .joined(separator: " · ")
    let donorName = donor == .here ? "this Mac's" : "\(sourceName)'s"
    var lines = [
      "→ Snapshot: \(sourceName)\(exported), \(snapshotPlays.formatted()) plays",
      "→ Plays: \(playsAdded.formatted()) added\(bySource.isEmpty ? "" : " (\(bySource))"), "
        + "\(alreadyHere.formatted()) already here",
      firstLackedHere.map { "→ This Mac was missing plays from \(ArchiveMerger.describe($0))" }
        ?? "→ This Mac already had every play in the snapshot",
      firstLackedThere.map { "→ The snapshot was missing plays from \(ArchiveMerger.describe($0))" }
        ?? "→ The snapshot had every play from this Mac",
    ]
    if let replayFrom {
      lines.append("→ Kept \(donorName) memories and pet up to \(ArchiveMerger.describe(replayFrom)), "
        + "then replayed \(playsReplayed.formatted()) plays")
    } else {
      lines.append("→ Kept \(donorName) memories and pet; nothing to replay")
    }
    lines.append("→ Memories \(before.memories.formatted()) → \(after.memories.formatted())"
      + " · Artifacts \(before.artifacts.formatted()) → \(after.artifacts.formatted())"
      + " · Tricks \(before.tricks) → \(after.tricks)"
      + " · Weekly memories \(before.weeklyMemories) → \(after.weeklyMemories)")
    lines.append("→ Pet \(before.xp.formatted()) XP \(before.stage.rawValue) → "
      + "\(after.xp.formatted()) XP \(after.stage.rawValue)")
    if dryRun {
      lines.append("✓ Dry run: nothing changed. Run again without --dry-run to merge.")
    } else {
      lines.append("✓ Merged. Backup: \(backupURL?.path ?? "none")")
    }
    return lines
  }
}
