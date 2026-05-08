import GRDB
import XCTest
@testable import Dial

final class RecentPlaysReconcilerTests: XCTestCase {
  func test_firstRunStartsAfterImportedHistoryNotLatestLivePlay() async throws {
    let dbq = try InMemoryDatabase.make()
    let importedAt: Int64 = 1_700_000_000
    let liveAt: Int64 = importedAt + 250_000
    try await seedPlay(dbq, playedAt: importedAt, trackUri: "spotify:track:old", source: "import")
    try await seedPlay(dbq, playedAt: liveAt, trackUri: "spotify:track:live", source: "live")

    let client = FakeRecentlyPlayedClient(response: response(items: []))
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { liveAt })

    _ = try await syncer.sync()

    XCTAssertEqual(
      client.afterMs,
      importedAt * 1000 - RecentPlaysReconciler.initialImportLookbackMs)
  }

  func test_savedCursorUsesShortOverlapInsteadOfFullDay() async throws {
    let dbq = try InMemoryDatabase.make()
    let savedCursorMs: Int64 = 1_700_000_200_000
    try await dbq.write { db in
      try db.execute(sql: """
        INSERT INTO recent_play_sync_state (
          id,
          last_played_at_ms,
          last_synced_at,
          last_response_count,
          last_response_saturated,
          consecutive_saturated,
          last_inserted_count
        )
        VALUES (1, ?, 0, 0, 0, 0, 0)
        """, arguments: [savedCursorMs])
    }

    let client = FakeRecentlyPlayedClient(response: response(items: []))
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { 1_700_000_300 })

    _ = try await syncer.sync()

    XCTAssertEqual(
      client.afterMs,
      savedCursorMs - RecentPlaysReconciler.savedCursorOverlapMs)
  }

  func test_syncInsertsMissedRecentPlayAndTrackMetadata() async throws {
    let dbq = try InMemoryDatabase.make()
    let importedAt: Int64 = 1_700_000_000
    try await seedPlay(dbq, playedAt: importedAt, trackUri: "spotify:track:old", source: "import")

    let playedAt = "2023-11-14T22:15:00.123Z"
    let client = FakeRecentlyPlayedClient(response: response(items: [
      itemJSON(
        playedAt: playedAt,
        trackUri: "spotify:track:drake",
        trackName: "Flights Booked",
        artistName: "Drake",
        artistUri: "spotify:artist:drake",
        albumName: "Honestly, Nevermind")
    ]))
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { 1_700_000_200 })

    let result = try await syncer.sync()

    XCTAssertEqual(result.scanned, 1)
    XCTAssertEqual(result.inserted, 1)
    XCTAssertEqual(result.skipped, 0)
    XCTAssertFalse(result.possiblyTruncated)

    let play = try await dbq.read { db in
      try Play
        .filter(Play.Columns.trackUri == "spotify:track:drake")
        .fetchOne(db)
    }
    XCTAssertEqual(play?.source, RecentPlaysReconciler.source)
    XCTAssertEqual(play?.playedAt, 1_700_000_100)
    XCTAssertEqual(play?.msPlayed, 180_000)

    let track = try TracksDAO(dbq: dbq).fetch(uri: "spotify:track:drake")
    XCTAssertEqual(track?.name, "Flights Booked")
    XCTAssertEqual(track?.albumName, "Honestly, Nevermind")
    XCTAssertEqual(track?.durationMs, 180_000)
    XCTAssertTrue(track?.artistsJson?.contains("spotify:artist:drake") == true)

    let cursor = try await dbq.read { db in
      try Int64.fetchOne(db, sql: "SELECT last_played_at_ms FROM recent_play_sync_state WHERE id = 1")
    }
    XCTAssertEqual(cursor, 1_700_000_100_123)
  }

  func test_fullRecentPageAdvancesCursorAndMarksSaturation() async throws {
    let dbq = try InMemoryDatabase.make()
    let importedAt: Int64 = 1_700_000_000
    try await seedPlay(dbq, playedAt: importedAt, trackUri: "spotify:track:old", source: "import")

    let items = (0..<50).map { idx in
      itemJSON(
        playedAt: "2023-11-14T22:15:\(String(format: "%02d", idx))Z",
        trackUri: "spotify:track:recent-\(idx)",
        trackName: "Recent \(idx)",
        artistName: "Artist",
        artistUri: "spotify:artist:A",
        albumName: "Al")
    }
    let client = FakeRecentlyPlayedClient(response: response(items: items))
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { 1_700_000_200 })

    let result = try await syncer.sync()

    XCTAssertEqual(result.scanned, 50)
    XCTAssertEqual(result.inserted, 50)
    XCTAssertTrue(result.possiblyTruncated)

    let state = try await dbq.read { db in
      try Row.fetchOne(db, sql: """
        SELECT last_played_at_ms,
               last_response_count,
               last_response_saturated,
               consecutive_saturated,
               last_inserted_count
        FROM recent_play_sync_state
        WHERE id = 1
        """)
    }
    let lastPlayedAtMs: Int64? = state?["last_played_at_ms"]
    let responseCount: Int? = state?["last_response_count"]
    let responseSaturated: Int? = state?["last_response_saturated"]
    let consecutiveSaturated: Int? = state?["consecutive_saturated"]
    let insertedCount: Int? = state?["last_inserted_count"]
    XCTAssertEqual(lastPlayedAtMs, 1_700_000_149_000)
    XCTAssertEqual(responseCount, 50)
    XCTAssertEqual(responseSaturated, 1)
    XCTAssertEqual(consecutiveSaturated, 1)
    XCTAssertEqual(insertedCount, 50)
  }

  func test_syncPagesBackwardWhenMoreThanFiftyRecentPlaysAreAvailable() async throws {
    let dbq = try InMemoryDatabase.make()
    let savedCursorMs: Int64 = 1_700_000_000_000
    try await dbq.write { db in
      try db.execute(sql: """
        INSERT INTO recent_play_sync_state (
          id,
          last_played_at_ms,
          last_synced_at,
          last_response_count,
          last_response_saturated,
          consecutive_saturated,
          last_inserted_count
        )
        VALUES (1, ?, 0, 0, 0, 0, 0)
        """, arguments: [savedCursorMs])
    }

    func page(_ range: ClosedRange<Int>) -> RecentlyPlayedResponse {
      response(items: range.reversed().map { idx in
        itemJSON(
          playedAt: playedAt(savedCursorMs + Int64(idx) * 1_000),
          trackUri: "spotify:track:flight-\(idx)",
          trackName: "Flight \(idx)",
          artistName: "Plane Mode",
          artistUri: "spotify:artist:plane",
          albumName: "Offline")
      })
    }

    let client = FakeRecentlyPlayedClient(responses: [
      page(61...110),
      page(11...60),
      page(1...10),
    ])
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { 1_700_001_000 })

    let result = try await syncer.sync()

    XCTAssertEqual(result.scanned, 110)
    XCTAssertEqual(result.inserted, 110)
    XCTAssertFalse(result.possiblyTruncated)
    XCTAssertEqual(client.callCount, 3)

    let state = try await dbq.read { db in
      try Row.fetchOne(db, sql: """
        SELECT last_played_at_ms,
               last_response_count,
               last_response_saturated,
               consecutive_saturated,
               last_inserted_count
        FROM recent_play_sync_state
        WHERE id = 1
        """)
    }
    XCTAssertEqual(state?["last_played_at_ms"] as Int64?, savedCursorMs + 110_000)
    XCTAssertEqual(state?["last_response_count"] as Int?, 10)
    XCTAssertEqual(state?["last_response_saturated"] as Int?, 0)
    XCTAssertEqual(state?["consecutive_saturated"] as Int?, 0)
    XCTAssertEqual(state?["last_inserted_count"] as Int?, 110)
  }

  func test_syncSkipsRecentPlayAlreadyCountedLive() async throws {
    let dbq = try InMemoryDatabase.make()
    try await dbq.write { db in
      try Track(
        uri: "spotify:track:A",
        name: "A",
        albumName: "Al",
        albumArtUrl: nil,
        durationMs: 180_000,
        artistsJson: nil
      ).mergeUpsert(db)
    }
    try await seedPlay(dbq, playedAt: 1_700_000_130, trackUri: "spotify:track:A", source: "live")

    let client = FakeRecentlyPlayedClient(response: response(items: [
      itemJSON(
        playedAt: "2023-11-14T22:15:00.123Z",
        trackUri: "spotify:track:A",
        trackName: "A",
        artistName: "Artist",
        artistUri: "spotify:artist:A",
        albumName: "Al")
    ]))
    let syncer = RecentPlaysReconciler(
      dbq: dbq,
      client: client,
      engine: PetEngine(dbq: dbq),
      clock: { 1_700_000_200 })

    let result = try await syncer.sync()

    XCTAssertEqual(result.inserted, 0)
    XCTAssertEqual(result.skipped, 1)
    XCTAssertFalse(result.possiblyTruncated)
    let count = try await dbq.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM plays WHERE track_uri = 'spotify:track:A'")
    }
    XCTAssertEqual(count, 1)
  }

  private func seedPlay(
    _ dbq: DatabaseQueue,
    playedAt: Int64,
    trackUri: String,
    source: String
  ) async throws {
    try await dbq.write { db in
      var play = Play(playedAt: playedAt, trackUri: trackUri, msPlayed: 60_000, source: source)
      try play.insert(db)
    }
  }

  private func response(items: [String]) -> RecentlyPlayedResponse {
    let json = #"{"items":["# + items.joined(separator: ",") + #"]}"#
    return try! JSONDecoder().decode(RecentlyPlayedResponse.self, from: Data(json.utf8))
  }

  private func itemJSON(
    playedAt: String,
    trackUri: String,
    trackName: String,
    artistName: String,
    artistUri: String,
    albumName: String
  ) -> String {
    """
    {
      "played_at": "\(playedAt)",
      "track": {
        "uri": "\(trackUri)",
        "name": "\(trackName)",
        "duration_ms": 180000,
        "artists": [{"name": "\(artistName)", "uri": "\(artistUri)"}],
        "album": {"name": "\(albumName)", "images": [{"url": "http://art"}]}
      }
    }
    """
  }

  private func playedAt(_ epochMs: Int64) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
  }
}

private final class FakeRecentlyPlayedClient: RecentlyPlayedClient {
  private var responses: [RecentlyPlayedResponse]
  private(set) var afterMs: Int64?
  private(set) var beforeMs: Int64?
  private(set) var limit: Int?
  private(set) var callCount = 0

  init(response: RecentlyPlayedResponse) {
    self.responses = [response]
  }

  init(responses: [RecentlyPlayedResponse]) {
    self.responses = responses
  }

  func recentlyPlayed(afterMs: Int64?, beforeMs: Int64?, limit: Int) async throws -> RecentlyPlayedResponse {
    if beforeMs == nil {
      self.afterMs = afterMs
    }
    self.beforeMs = beforeMs
    self.limit = limit
    callCount += 1
    if responses.count > 1 {
      return responses.removeFirst()
    }
    return responses.first ?? RecentlyPlayedResponse(items: [])
  }
}
