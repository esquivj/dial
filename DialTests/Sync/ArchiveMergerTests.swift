// DialTests/Sync/ArchiveMergerTests.swift
import XCTest
import GRDB
@testable import Dial

/// One listening history, recorded three ways: by a Mac that saw every play
/// ("all"), by a first Mac that missed days 5–7, and by a Mac mini set up on
/// day 3 whose start estimates run 2 s later. Merging the two partial
/// archives either way should land where "all" is.
final class ArchiveMergerTests: XCTestCase {
  private var directory: URL!
  private let firstMac = MacIdentity(id: "aaaaaaaaaaaaaaaa", name: "First Mac")
  private let miniMac = MacIdentity(id: "bbbbbbbbbbbbbbbb", name: "Mac mini")
  private let now: Int64 = 1_800_000_000

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Dial.ArchiveMergerTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Merging

  func test_mergingBothWays_endsWithOneHistoryOneSetOfMemoriesAndOnePet() throws {
    let archives = try buildArchives()
    let truth = try memories(archives.all)
    XCTAssertEqual(
      Set(truth.map { String($0.label.prefix { $0 != " " }) }),
      ["first_listen", "new_artist", "album_mode", "repeat_track", "play_10", "on_streak", "deep_cut", "rediscovered"],
      "the fixture should earn every kind the replay has to reproduce")
    // Each partial archive judged its plays on half a history.
    XCTAssertNotEqual(try memories(archives.first).map(\.label), truth.map(\.label))
    XCTAssertNotEqual(try memories(archives.mini).map(\.label), truth.map(\.label))

    let firstSnapshot = try export(archives.first, as: firstMac, to: "first.dialarchive")
    let miniSnapshot = try export(archives.mini, as: miniMac, to: "mini.dialarchive")
    let onFirst = try merge(miniSnapshot, into: archives.first, as: firstMac)
    let onMini = try merge(firstSnapshot, into: archives.mini, as: miniMac)

    // Both Macs choose the first Mac as the donor and replay from the first
    // play it missed: the Mac mini's day 5.
    XCTAssertEqual(onFirst.donor, .here)
    XCTAssertEqual(onMini.donor, .snapshot)
    XCTAssertEqual(onFirst.replayFrom, noon(5) + 2)
    XCTAssertEqual(onMini.replayFrom, noon(5) + 2)
    XCTAssertEqual(onFirst.addedBySource, ["live": 6])
    XCTAssertEqual(onMini.addedBySource, ["live": 11])

    let countedTotal = try countedPlays(archives.all)
    XCTAssertEqual(try countedPlays(archives.first), countedTotal)
    XCTAssertEqual(try countedPlays(archives.mini), countedTotal)
    assertSameMemories(try memories(archives.first), truth)
    assertSameMemories(try memories(archives.mini), truth)

    let firstPet = try pet(archives.first)
    let miniPet = try pet(archives.mini)
    XCTAssertEqual(firstPet.xp, miniPet.xp)
    XCTAssertEqual(firstPet.stage, miniPet.stage)
    XCTAssertEqual(firstPet.streakDays, miniPet.streakDays)
    // The app derives artifacts from memories; do the same for the reference.
    try withArchive(archives.all) { _ = try ArtifactsDAO(dbq: $0).syncFromMemoriesAndTricks() }
    XCTAssertEqual(try artifactKinds(archives.first), try artifactKinds(archives.all))
    XCTAssertEqual(try artifactKinds(archives.mini), try artifactKinds(archives.all))
  }

  func test_seed_youngMacKeepsItsPlaysAndQueue_butTakesTheOtherMacsMemoriesPetAndTricks() throws {
    let archives = try buildArchives()
    try withArchive(archives.first) { dbq in
      _ = try PetTrickUnlocksDAO(dbq: dbq, now: { self.noon(4) }).unlock(.memorySpin)
    }
    let queuedPlay = try withArchive(archives.mini) { dbq -> Int64 in
      let id = try XCTUnwrap(try dbq.read { try Int64.fetchOne($0, sql: "SELECT MAX(id) FROM plays") })
      XCTAssertTrue(try ScrobbleQueueDAO(dbq: dbq).enqueue(
        playId: id, artist: "Delta", track: "Delta Song", album: nil, durationMs: 200_000, now: now))
      return id
    }
    // On its own, the Mac mini thinks its first day was full of first listens.
    XCTAssertEqual(try memories(archives.mini).filter { $0.label == "first_listen spotify:track:a1" }.map(\.at),
                   [noon(3) + 2])

    let snapshot = try export(archives.first, as: firstMac, to: "first.dialarchive")
    let report = try merge(snapshot, into: archives.mini, as: miniMac)

    XCTAssertEqual(try memories(archives.mini).filter { $0.label == "first_listen spotify:track:a1" }.map(\.at),
                   [noon(0)])
    try withArchive(archives.mini) { dbq in
      let mergedPlay = try dbq.read { db -> Int64 in
        XCTAssertEqual(try String.fetchAll(db, sql: "SELECT trick FROM pet_trick_unlocks"), ["memory_spin"])
        XCTAssertEqual(
          try Int64.fetchAll(db, sql: "SELECT play_id FROM lastfm_scrobbles WHERE state = 'pending'"),
          [queuedPlay])
        let log = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT * FROM archive_merges"))
        XCTAssertEqual(log["source_mac_name"] as String, "First Mac")
        XCTAssertEqual(log["donor"] as String, "snapshot")
        XCTAssertEqual(log["plays_added"] as Int, 11)
        return try XCTUnwrap(try Int64.fetchOne(
          db, sql: "SELECT id FROM plays WHERE origin = ? AND source = 'live' LIMIT 1", arguments: [firstMac.id]))
      }
      // A play from the first Mac can never join this Mac's Last.fm queue.
      XCTAssertFalse(try ScrobbleQueueDAO(dbq: dbq).enqueue(
        playId: mergedPlay, artist: "Alpha", track: "Alpha Song 1", album: nil, durationMs: 200_000, now: now))
      XCTAssertEqual(try PetStateDAO(dbq: dbq).get().installedAt, noon(0) - 86_400)
    }

    let backup = try XCTUnwrap(report.backupURL)
    XCTAssertEqual(try withFile(backup) { dbq in
      try dbq.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM plays") }
    }, report.before.plays)
    // The working files are gone, and no empty folder is left behind.
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: archives.mini.deletingLastPathComponent().appendingPathComponent("Merging").path))
  }

  func test_mergingAgainOrBack_changesNothing() throws {
    let archives = try buildArchives()
    let firstSnapshot = try export(archives.first, as: firstMac, to: "first-1.dialarchive")
    _ = try merge(firstSnapshot, into: archives.mini, as: miniMac)
    let memoriesAfterOne = try memories(archives.mini)

    let again = try merge(firstSnapshot, into: archives.mini, as: miniMac)
    XCTAssertEqual(again.playsAdded, 0)
    XCTAssertNil(again.firstLackedHere)
    XCTAssertNil(again.replayFrom)
    XCTAssertEqual(again.after, again.before)
    XCTAssertEqual(try memories(archives.mini).map(\.label), memoriesAfterOne.map(\.label))

    // The first Mac takes the Mac mini's merged archive; sending it back
    // adds nothing.
    let miniSnapshot = try export(archives.mini, as: miniMac, to: "mini.dialarchive")
    _ = try merge(miniSnapshot, into: archives.first, as: firstMac)
    let secondFirstSnapshot = try export(archives.first, as: firstMac, to: "first-2.dialarchive")
    let back = try merge(secondFirstSnapshot, into: archives.mini, as: miniMac)
    XCTAssertEqual(back.playsAdded, 0)
    XCTAssertEqual(back.after, back.before)
  }

  func test_dryRun_reportsButChangesNothing() throws {
    let archives = try buildArchives()
    let snapshot = try export(archives.first, as: firstMac, to: "first.dialarchive")
    let memoriesBefore = try memories(archives.mini)
    let countedBefore = try countedPlays(archives.mini)

    let report = try merge(snapshot, into: archives.mini, as: miniMac, dryRun: true)

    XCTAssertTrue(report.dryRun)
    XCTAssertEqual(report.playsAdded, 11)
    XCTAssertEqual(report.after.plays, report.before.plays + 11)
    XCTAssertNil(report.backupURL)
    XCTAssertEqual(try countedPlays(archives.mini), countedBefore)
    XCTAssertEqual(try memories(archives.mini).map(\.label), memoriesBefore.map(\.label))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: archives.mini.deletingLastPathComponent().appendingPathComponent("Backups").path))
    XCTAssertTrue(report.summaryLines().last?.hasPrefix("✓ Dry run") ?? false)
  }

  func test_plainCopyOfAnOlderDial_mergesUnderTheGivenName() throws {
    // The first Mac runs a Dial from before v19: no `origin`, no info row.
    let plays = scriptedPlays()
    let older = directory.appendingPathComponent("older", isDirectory: true)
    try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
    let olderURL = older.appendingPathComponent("dial.sqlite")
    let olderDB = try DatabaseQueue(path: olderURL.path)
    try Migrations.register().migrate(olderDB, upTo: "v18_counted_plays_hide_recent_twins")
    try seedCatalog(olderDB)
    try record(plays.filter { $0.day <= 4 }, into: olderDB)
    try olderDB.close()

    let mini = try makeArchive("mini", installedAt: noon(3))
    try withArchive(mini) { try record(plays.filter { $0.day >= 3 }, into: $0, offset: 2) }
    let plainCopy = directory.appendingPathComponent("dial-first-mac.sqlite")
    try ArchiveFiles.vacuumCopy(from: olderURL, to: plainCopy)

    let report = try merge(plainCopy, into: mini, as: miniMac, sourceName: "First Mac")

    XCTAssertEqual(report.sourceName, "First Mac")
    XCTAssertNil(report.sourceExportedAt)
    XCTAssertEqual(report.addedBySource, ["live": 11])
    let origins = try withArchive(mini) { dbq in
      try dbq.read { try String.fetchAll($0, sql: "SELECT DISTINCT origin FROM plays WHERE origin IS NOT NULL") }
    }
    XCTAssertEqual(origins, ["unidentified:First Mac"])
  }

  func test_xpNeverGoesDown() throws {
    let archives = try buildArchives()
    try withArchive(archives.mini) { dbq in try PetStateDAO(dbq: dbq).update { $0.xp = 999_999 } }
    let snapshot = try export(archives.first, as: firstMac, to: "first.dialarchive")

    let report = try merge(snapshot, into: archives.mini, as: miniMac)

    XCTAssertEqual(report.donor, .snapshot)
    XCTAssertEqual(try pet(archives.mini).xp, 999_999)
  }

  func test_streak_countsDaysListenedOnEitherMac() throws {
    let here = try makeArchive("here", installedAt: noon(0))
    let there = try makeArchive("there", installedAt: noon(0))
    try withArchive(here) { dbq in
      try record([.init(day: 1, at: noon(1), track: "a1"), .init(day: 3, at: noon(3), track: "a2")], into: dbq)
    }
    try withArchive(there) { try record([.init(day: 2, at: noon(2), track: "b1")], into: $0) }
    XCTAssertEqual(try pet(here).streakDays, 1)

    _ = try merge(try export(there, as: firstMac, to: "there.dialarchive"), into: here, as: miniMac)

    let merged = try pet(here)
    XCTAssertEqual(merged.streakDays, 3)
    XCTAssertEqual(merged.streakAnchorDate, StreakCalendar.ymd(from: noon(3)))
  }

  func test_weeksTheMergeChanged_areRecomputed() throws {
    let archives = try buildArchives()
    // The first Mac remembers the week of day 5 without the plays it missed.
    let week = StatsQueries.weekBounds(containing: noon(5))
    try withArchive(archives.first) { dbq in
      let memory = try XCTUnwrap(try StatsQueries(dbq: dbq).weeklyMemory(weekStart: week.start, weekEnd: week.end))
      try WeeklyMemoriesDAO(dbq: dbq).upsert(memory, now: now)
    }
    let expected = try withArchive(archives.all) { dbq in
      try XCTUnwrap(try StatsQueries(dbq: dbq).weeklyMemory(weekStart: week.start, weekEnd: week.end)).playCount
    }

    _ = try merge(try export(archives.mini, as: miniMac, to: "mini.dialarchive"), into: archives.first, as: firstMac)

    let playCount = try withArchive(archives.first) { dbq in
      try dbq.read {
        try Int.fetchOne($0, sql: "SELECT play_count FROM weekly_memories WHERE week_start = ?", arguments: [week.start])
      }
    }
    XCTAssertEqual(playCount, expected)
  }

  // MARK: - Refusals

  func test_refusesItsOwnSnapshot_aNewerDial_aHistoryExport_andOtherFiles() throws {
    let here = try makeArchive("here", installedAt: noon(0))
    let other = try makeArchive("other", installedAt: noon(0))

    let own = try export(here, as: firstMac, to: "own.dialarchive")
    XCTAssertThrowsError(try merge(own, into: other, as: firstMac)) { error in
      XCTAssertEqual(error as? ArchiveError, .sameMac)
    }

    let newer = try export(here, as: miniMac, to: "newer.dialarchive")
    try withFile(newer) { dbq in
      try dbq.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99_future')") }
    }
    XCTAssertThrowsError(try merge(newer, into: other, as: firstMac)) { error in
      XCTAssertEqual(error as? ArchiveError, .newerSchema(["v99_future"]))
    }

    let historyExport = directory.appendingPathComponent("history.sqlite")
    let history = try DatabaseQueue(path: historyExport.path)
    try history.write { db in
      try db.execute(sql: "CREATE TABLE plays (id INTEGER PRIMARY KEY, played_at INTEGER, track_uri TEXT, ms_played INTEGER, source TEXT)")
      try db.execute(sql: "CREATE TABLE dial_history_snapshot (schema_version TEXT, captured_at TEXT)")
    }
    try history.close()
    XCTAssertThrowsError(try merge(historyExport, into: other, as: firstMac)) { error in
      XCTAssertEqual(error as? ArchiveError, .historyExport("history.sqlite"))
    }

    let notes = directory.appendingPathComponent("notes.txt")
    try Data("not a database".utf8).write(to: notes)
    XCTAssertThrowsError(try merge(notes, into: other, as: firstMac)) { error in
      XCTAssertEqual(error as? ArchiveError, .notAnArchive("notes.txt"))
    }
  }

  // MARK: - Fixture

  private struct ScriptedPlay {
    let day: Int
    let at: Int64
    let track: String
  }

  private struct Memory {
    let label: String
    let at: Int64
  }

  /// Local noon on fixture day `day`, so a few seconds never cross midnight.
  private func noon(_ day: Int) -> Int64 {
    let start = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 2, hour: 12))!
    return Int64(start.timeIntervalSince1970) + Int64(day) * 86_400
  }

  /// Plays chosen to earn every kind of memory the replay must reproduce:
  /// album mode and a repeat run (day 0), 10th plays and a streak (day 9), a
  /// deep cut (day 10), a rediscovery (day 100) and a new artist (day 101).
  private func scriptedPlays() -> [ScriptedPlay] {
    var plays: [ScriptedPlay] = []
    func add(_ day: Int, _ tracks: [String]) {
      for (index, track) in tracks.enumerated() {
        plays.append(.init(day: day, at: noon(day) + Int64(index) * 210, track: track))
      }
    }
    add(0, ["a1", "a2", "a3", "b1", "b1", "b1", "g1"])
    for day in 1...12 {
      add(day, day == 10 ? ["a1", "a2", "a5"] : ["a1", "a2"])
    }
    add(100, ["g1"])
    add(101, ["d1"])
    return plays
  }

  private func buildArchives() throws -> (all: URL, first: URL, mini: URL) {
    let plays = scriptedPlays()
    let all = try makeArchive("all", installedAt: noon(0) - 86_400)
    try withArchive(all) { try record(plays, into: $0) }
    let first = try makeArchive("first", installedAt: noon(0) - 86_400)
    try withArchive(first) { try record(plays.filter { !(5...7).contains($0.day) }, into: $0) }
    let mini = try makeArchive("mini", installedAt: noon(3) - 3_600)
    try withArchive(mini) { try record(plays.filter { $0.day >= 3 }, into: $0, offset: 2) }
    return (all, first, mini)
  }

  private func makeArchive(_ name: String, installedAt: Int64) throws -> URL {
    let folder = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("dial.sqlite")
    try withArchive(url) { dbq in
      try seedCatalog(dbq)
      try PetStateDAO(dbq: dbq).update { $0.installedAt = installedAt }
    }
    return url
  }

  private func seedCatalog(_ dbq: DatabaseQueue) throws {
    let tracks = TracksDAO(dbq: dbq)
    func add(_ id: String, _ name: String, artist: String, album: String) throws {
      try tracks.upsert(.init(
        uri: "spotify:track:\(id)",
        name: name,
        albumName: album,
        albumArtUrl: nil,
        durationMs: 200_000,
        artistsJson: #"[{"name":"\#(artist)","uri":"spotify:artist:\#(artist.lowercased())"}]"#))
    }
    for index in 1...6 { try add("a\(index)", "Alpha Song \(index)", artist: "Alpha", album: "Alpha One") }
    for index in 1...3 { try add("b\(index)", "Beta Song \(index)", artist: "Beta", album: "Beta Days") }
    try add("g1", "Gamma Song", artist: "Gamma", album: "Gamma")
    try add("d1", "Delta Song", artist: "Delta", album: "Delta")
  }

  /// Records plays the way the live poll does: counted at about 30 s.
  private func record(_ plays: [ScriptedPlay], into dbq: DatabaseQueue, offset: Int64 = 0) throws {
    let engine = PetEngine(dbq: dbq, clock: { self.now })
    for play in plays {
      XCTAssertTrue(try engine.recordPlay(.init(
        playedAt: play.at + offset, trackUri: "spotify:track:\(play.track)", msPlayed: 31_000, source: "live")))
    }
  }

  /// Opens a Mac's archive the way Dial does.
  private func withArchive<T>(_ url: URL, _ body: (DatabaseQueue) throws -> T) throws -> T {
    let dbq = try DatabaseStack(url: url).dbq
    defer { try? dbq.close() }
    return try body(dbq)
  }

  /// Opens a snapshot or backup as it is: no migrations, no WAL.
  private func withFile<T>(_ url: URL, _ body: (DatabaseQueue) throws -> T) throws -> T {
    let dbq = try DatabaseQueue(path: url.path)
    defer { try? dbq.close() }
    return try body(dbq)
  }

  private func export(_ archive: URL, as mac: MacIdentity, to name: String) throws -> URL {
    let snapshot = directory.appendingPathComponent(name)
    try ArchiveExporter.export(archiveAt: archive, to: snapshot, mac: mac, now: now)
    return snapshot
  }

  private func merge(
    _ snapshot: URL,
    into archive: URL,
    as mac: MacIdentity,
    dryRun: Bool = false,
    sourceName: String? = nil
  ) throws -> ArchiveMerger.Report {
    var options = ArchiveMerger.Options()
    options.mac = mac
    options.now = now
    options.dryRun = dryRun
    options.sourceName = sourceName
    return try ArchiveMerger(archiveURL: archive, snapshotURL: snapshot, options: options).run()
  }

  private func memories(_ archive: URL) throws -> [Memory] {
    try withArchive(archive) { dbq in
      try dbq.read { db in
        try Row.fetchAll(db, sql: "SELECT kind, COALESCE(track_uri, '') AS track, earned_at FROM badge_events")
          .map { Memory(label: "\($0["kind"] as String) \($0["track"] as String)", at: $0["earned_at"]) }
          .sorted { ($0.label, $0.at) < ($1.label, $1.at) }
      }
    }
  }

  /// Same memories, allowing for the 2 s between the two Macs' estimates.
  private func assertSameMemories(
    _ actual: [Memory],
    _ expected: [Memory],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.map(\.label), expected.map(\.label), file: file, line: line)
    for (got, want) in zip(actual, expected) {
      XCTAssertLessThanOrEqual(abs(got.at - want.at), 5, got.label, file: file, line: line)
    }
  }

  private func countedPlays(_ archive: URL) throws -> Int {
    try withArchive(archive) { dbq in
      try dbq.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM counted_plays") ?? 0 }
    }
  }

  private func pet(_ archive: URL) throws -> PetState {
    try withArchive(archive) { try PetStateDAO(dbq: $0).get() }
  }

  private func artifactKinds(_ archive: URL) throws -> [String] {
    try withArchive(archive) { dbq in
      try dbq.read { try String.fetchAll($0, sql: "SELECT kind FROM artifacts ORDER BY kind") }
    }
  }
}
