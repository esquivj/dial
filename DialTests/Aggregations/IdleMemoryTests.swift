import XCTest
import GRDB
@testable import Dial

/// PLA-105: the idle HUD's last spin and today's listening.
final class IdleMemoryTests: XCTestCase {
  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c
  }

  /// 15:00 local time on a fixed day, so "today" has room on both sides.
  private var now: Int64 {
    let day = calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 15))!
    return Int64(day.timeIntervalSince1970)
  }

  private func seed(_ dbq: DatabaseQueue, _ plays: [(at: Int64, uri: String, ms: Int64)]) throws {
    try TracksDAO(dbq: dbq).upsert(.init(
      uri: "T1", name: "Signal Drift", albumName: "Hardware Memory", albumArtUrl: nil, durationMs: 200_000,
      artistsJson: #"[{"name":"Dial Test","uri":"art:a"}]"#))
    try dbq.write { db in
      for p in plays {
        try db.execute(
          sql: "INSERT INTO plays (played_at, track_uri, ms_played, source) VALUES (?, ?, ?, 'live')",
          arguments: [p.at, p.uri, p.ms])
      }
    }
  }

  func test_idleMemory_countsTodayAndFindsTheLastSpin() throws {
    let dbq = try InMemoryDatabase.make()
    let startOfDay = Int64(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now))).timeIntervalSince1970)
    try seed(dbq, [
      (startOfDay - 600, "T1", 180_000),          // yesterday: not today
      (startOfDay + 3_600, "T1", 200_000),
      (now - 720, "T1", 120_000),                 // last spin, 12 min ago
    ])

    let memory = try StatsQueries(dbq: dbq).idleMemory(now: now)

    XCTAssertEqual(memory.todayPlays, 2)
    XCTAssertEqual(memory.todayMs, 320_000)
    XCTAssertEqual(memory.lastSpin?.trackName, "Signal Drift")
    XCTAssertEqual(memory.lastSpin?.artistName, "Dial Test")
    XCTAssertEqual(memory.lastSpin?.playedAt, now - 720)
  }

  func test_idleMemory_emptyArchive() throws {
    let memory = try StatsQueries(dbq: InMemoryDatabase.make()).idleMemory(now: now)
    XCTAssertNil(memory.lastSpin)
    XCTAssertEqual(memory.todayPlays, 0)
    XCTAssertEqual(memory.todayMs, 0)
  }

  func test_agoStamp() {
    let nowDate = Date(timeIntervalSince1970: TimeInterval(now))
    let stamp = { (secondsAgo: Int64) in
      IdleMemoryStrip.agoStamp(playedAt: self.now - secondsAgo, now: nowDate, calendar: self.calendar)
    }
    XCTAssertEqual(stamp(20), "NOW")
    XCTAssertEqual(stamp(12 * 60), "12M AGO")
    XCTAssertEqual(stamp(3 * 3_600), "3H AGO")
    XCTAssertEqual(stamp(20 * 3_600), "YESTERDAY")
    XCTAssertEqual(stamp(4 * 86_400), "4D AGO")
    XCTAssertEqual(stamp(800 * 86_400), "2Y AGO")
  }

  func test_todayFormatting() {
    XCTAssertEqual(IdleMemoryStrip.playsLine(0), "0 plays")
    XCTAssertEqual(IdleMemoryStrip.playsLine(1), "1 play")
    XCTAssertEqual(IdleMemoryStrip.listenedStamp(ms: 200_000), "3M")
    XCTAssertEqual(IdleMemoryStrip.listenedStamp(ms: 52 * 60_000 + 30_000), "52M")
    XCTAssertEqual(IdleMemoryStrip.listenedStamp(ms: 65 * 60_000), "1H 05M")
    XCTAssertEqual(IdleMemoryStrip.todayLine(plays: 0, ms: 0), "0 plays")
    XCTAssertEqual(IdleMemoryStrip.todayLine(plays: 14, ms: 52 * 60_000), "14 plays · 52M")
  }

  func test_titleLine() {
    XCTAssertEqual(IdleMemoryStrip.titleLine(name: "Signal Drift", artist: "Dial Test"), "Signal Drift · Dial Test")
    XCTAssertEqual(IdleMemoryStrip.titleLine(name: "Signal Drift", artist: ""), "Signal Drift")
    XCTAssertEqual(IdleMemoryStrip.titleLine(name: "", artist: ""), "Unknown track")
  }
}
