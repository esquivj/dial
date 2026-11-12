import XCTest
import GRDB
@testable import Dial

/// Times the memory replay on a copy of a real archive, query by query.
/// Skipped unless an archive is given, because real listening history never
/// lives in this repo:
///
///     TEST_RUNNER_DIAL_BENCH_ARCHIVE=/path/to/dial.sqlite \
///     TEST_RUNNER_DIAL_BENCH_PLAYS=300 \
///       scripts/dev.sh test MemoryReplayBenchmark
///
/// It replays the newest `DIAL_BENCH_PLAYS` plays (default 200) in a temp
/// copy and prints the time per play and the costliest statements.
final class MemoryReplayBenchmark: XCTestCase {
  func test_replayCostOnARealArchive() throws {
    let env = ProcessInfo.processInfo.environment
    guard let archive = env["DIAL_BENCH_ARCHIVE"], !archive.isEmpty else {
      throw XCTSkip("Set TEST_RUNNER_DIAL_BENCH_ARCHIVE to an archive copy to run the replay benchmark.")
    }
    let count = Int(env["DIAL_BENCH_PLAYS"] ?? "") ?? 200

    let copy = FileManager.default.temporaryDirectory
      .appendingPathComponent("dial-bench-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm", "-journal"] {
        try? FileManager.default.removeItem(atPath: copy.path + suffix)
      }
    }
    // A plain file copy: the source may be a WAL-mode backup without its
    // -wal file, which SQLite won't open read-only.
    try FileManager.default.copyItem(atPath: archive, toPath: copy.path)

    final class Profile: @unchecked Sendable {
      var bySQL: [String: (count: Int, seconds: Double)] = [:]
    }
    let profile = Profile()
    var config = Configuration()
    config.prepareDatabase { db in
      db.trace(options: .profile) { event in
        guard case let .profile(statement, duration) = event else { return }
        let key = statement.sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let old = profile.bySQL[key] ?? (0, 0)
        profile.bySQL[key] = (old.count + 1, old.seconds + duration)
      }
    }
    let dbq = try DatabaseQueue(path: copy.path, configuration: config)
    try Migrations.register().migrate(dbq)

    let start = try dbq.read { db in
      try Int64.fetchOne(db, sql: """
        SELECT played_at FROM plays ORDER BY played_at DESC, id DESC LIMIT 1 OFFSET ?
        """, arguments: [count - 1])
    }
    let replayFrom = try XCTUnwrap(start)
    profile.bySQL = [:]

    let clock = ContinuousClock()
    var result: MemoryReplay.Result?
    let elapsed = try clock.measure {
      result = try dbq.write { db in try MemoryReplay.replay(in: db, from: replayFrom) }
    }
    let replayed = try XCTUnwrap(result).playsReplayed
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

    var lines = [String(format: "replayed %d plays in %.1f s: %.0f ms per play", replayed, seconds,
                        seconds / Double(max(1, replayed)) * 1000)]
    let total = profile.bySQL.values.reduce(0) { $0 + $1.seconds }
    for (sql, cost) in profile.bySQL.sorted(by: { $0.value.seconds > $1.value.seconds }).prefix(12) {
      lines.append(String(format: "%5.1f%%  %7.1f ms/call  x%-6d %@",
                          cost.seconds / max(total, 1e-9) * 100,
                          cost.seconds / Double(cost.count) * 1000,
                          cost.count,
                          String(sql.prefix(160))))
    }
    let kinds = try dbq.read { db in
      try Row.fetchAll(db, sql: """
        SELECT kind, COUNT(*) AS n, COUNT(DISTINCT date(earned_at, 'unixepoch', 'localtime')) AS days
        FROM badge_events WHERE earned_at >= ? GROUP BY kind ORDER BY n DESC
        """, arguments: [replayFrom])
    }
    lines.append("memories replayed, by kind:")
    for row in kinds {
      lines.append("  \(row["kind"] as String): \(row["n"] as Int) on \(row["days"] as Int) days")
    }
    let report = lines.joined(separator: "\n")
    print("MEMORY REPLAY BENCHMARK\n" + report)
    let attachment = XCTAttachment(string: report)
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
