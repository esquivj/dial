import Foundation
import GRDB
import os.log

private let recentPlayLog = Logger(subsystem: "com.dial.Dial", category: "RecentPlaysReconciler")

protocol RecentlyPlayedClient {
  func recentlyPlayed(afterMs: Int64?, beforeMs: Int64?, limit: Int) async throws -> RecentlyPlayedResponse
}

extension RecentlyPlayedClient {
  func recentlyPlayed(afterMs: Int64?, limit: Int) async throws -> RecentlyPlayedResponse
  {
    try await recentlyPlayed(afterMs: afterMs, beforeMs: nil, limit: limit)
  }

  func recentlyPlayed(beforeMs: Int64?, limit: Int) async throws -> RecentlyPlayedResponse
  {
    try await recentlyPlayed(afterMs: nil, beforeMs: beforeMs, limit: limit)
  }
}

extension SpotifyClient: RecentlyPlayedClient {}

struct RecentPlaySyncResult: Equatable {
  let scanned: Int
  let inserted: Int
  let skipped: Int
  let cursorMs: Int64?
  let possiblyTruncated: Bool
}

final class RecentPlaysReconciler {
  static let source = "recent"
  static let initialImportLookbackMs: Int64 = 24 * 60 * 60 * 1000
  static let savedCursorOverlapMs: Int64 = 5 * 60 * 1000
  static let maxCatchUpPages = 4

  private let dbq: DatabaseQueue
  private let client: RecentlyPlayedClient
  private let engine: PetEngine
  private let clock: () -> Int64

  init(
    dbq: DatabaseQueue,
    client: RecentlyPlayedClient,
    engine: PetEngine,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }
  ) {
    self.dbq = dbq
    self.client = client
    self.engine = engine
    self.clock = clock
  }

  @discardableResult
  func sync(limit: Int = 50) async throws -> RecentPlaySyncResult {
    let afterMs = try syncCursorMs()
    let requestLimit = min(max(limit, 1), 50)
    let page = try await catchUpCandidates(afterMs: afterMs, requestLimit: requestLimit)
    let candidates = page.candidates.sorted { $0.playedAtMs < $1.playedAtMs }

    var inserted = 0
    var skipped = 0
    for candidate in candidates {
      try upsertMetadata(for: candidate)
      do {
        let didRecord = try engine.recordPlay(candidate.play)
        if didRecord {
          inserted += 1
        } else {
          skipped += 1
        }
      } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
        skipped += 1
      }
    }
    if !candidates.isEmpty {
      _ = try await dbq.write { db in
        try ArtistIdentityRepair.rebuildAliases(in: db)
      }
    }

    let newestCandidateMs = candidates.map(\.playedAtMs).max()
    let cursorMs = max(afterMs ?? 0, newestCandidateMs ?? afterMs ?? 0)
    try saveState(
      cursorMs: cursorMs,
      responseCount: page.items.count,
      possiblyTruncated: page.possiblyTruncated,
      inserted: inserted)

    if inserted > 0 || skipped > 0 {
      recentPlayLog.notice("recent sync scanned=\(candidates.count) inserted=\(inserted) skipped=\(skipped) truncated=\(page.possiblyTruncated)")
    }
    return RecentPlaySyncResult(
      scanned: candidates.count,
      inserted: inserted,
      skipped: skipped,
      cursorMs: cursorMs > 0 ? cursorMs : nil,
      possiblyTruncated: page.possiblyTruncated)
  }

  private func catchUpCandidates(
    afterMs: Int64?,
    requestLimit: Int
  ) async throws -> (candidates: [RecentPlayCandidate], items: [RecentlyPlayedItem], possiblyTruncated: Bool) {
    var allCandidates: [RecentPlayCandidate] = []
    var allItems: [RecentlyPlayedItem] = []
    var seen = Set<String>()

    var page = try await client.recentlyPlayed(afterMs: afterMs, beforeMs: nil, limit: requestLimit)
    var pagesScanned = 0
    var oldestInPage: Int64?
    var lastPageWasFull = false
    var hitPageCap = false
    var stalledPagination = false

    while true {
      pagesScanned += 1
      allItems = page.items
      lastPageWasFull = page.items.count >= requestLimit

      let candidates = page.items
        .compactMap(RecentPlayCandidate.init(item:))
        .filter { candidate in
          guard let afterMs else { return true }
          return candidate.playedAtMs > afterMs
        }

      for candidate in candidates {
        let key = "\(candidate.trackUri):\(candidate.playedAtMs)"
        guard seen.insert(key).inserted else { continue }
        allCandidates.append(candidate)
      }

      let nextOldest = candidates.map(\.playedAtMs).min()
      guard let afterMs,
            lastPageWasFull,
            let nextOldest,
            nextOldest > afterMs
      else { break }

      if let oldestInPage, nextOldest >= oldestInPage {
        stalledPagination = true
        break
      }
      oldestInPage = nextOldest

      guard pagesScanned < Self.maxCatchUpPages else {
        hitPageCap = true
        break
      }

      page = try await client.recentlyPlayed(afterMs: nil, beforeMs: nextOldest, limit: requestLimit)
    }

    let oldestCandidate = allCandidates.map(\.playedAtMs).min()
    let stillAboveCursor = afterMs.map { cursor in
      (oldestCandidate ?? Int64.max) > cursor
    } ?? false
    return (
      candidates: allCandidates,
      items: allItems,
      possiblyTruncated: (hitPageCap || stalledPagination) && lastPageWasFull && stillAboveCursor)
  }

  private func syncCursorMs() throws -> Int64? {
    try dbq.read { db in
      if let saved = try Int64.fetchOne(
        db,
        sql: "SELECT last_played_at_ms FROM recent_play_sync_state WHERE id = 1"
      ), saved > 0 {
        return max(0, saved - Self.savedCursorOverlapMs)
      }

      if let importedMax = try Int64.fetchOne(
        db,
        sql: "SELECT MAX(played_at) FROM plays WHERE source = 'import'"
      ) {
        return max(0, importedMax * 1000 - Self.initialImportLookbackMs)
      }

      if let anyMax = try Int64.fetchOne(db, sql: "SELECT MAX(played_at) FROM plays") {
        return max(0, anyMax * 1000 - Self.initialImportLookbackMs)
      }

      return nil
    }
  }

  private func saveState(
    cursorMs: Int64,
    responseCount: Int,
    possiblyTruncated: Bool,
    inserted: Int
  ) throws {
    try dbq.write { db in
      let existing = try Row.fetchOne(
        db,
        sql: """
          SELECT last_played_at_ms, consecutive_saturated
          FROM recent_play_sync_state
          WHERE id = 1
          """)
      let existingCursor: Int64 = existing?["last_played_at_ms"] ?? 0
      let existingSaturated: Int = existing?["consecutive_saturated"] ?? 0
      let nextCursor = max(existingCursor, cursorMs)
      let nextConsecutiveSaturated = possiblyTruncated ? existingSaturated + 1 : 0

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
        VALUES (1, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          last_played_at_ms = excluded.last_played_at_ms,
          last_synced_at = excluded.last_synced_at,
          last_response_count = excluded.last_response_count,
          last_response_saturated = excluded.last_response_saturated,
          consecutive_saturated = excluded.consecutive_saturated,
          last_inserted_count = excluded.last_inserted_count
        """, arguments: [
          nextCursor,
          clock(),
          responseCount,
          possiblyTruncated ? 1 : 0,
          nextConsecutiveSaturated,
          inserted,
        ])
    }
  }

  private func upsertMetadata(for candidate: RecentPlayCandidate) throws {
    let artistsJson = (try? JSONEncoder().encode(candidate.artists)).flatMap {
      String(data: $0, encoding: .utf8)
    }

    try dbq.write { db in
      try Track(
        uri: candidate.trackUri,
        name: candidate.trackName,
        albumName: candidate.albumName,
        albumArtUrl: candidate.artUrl,
        durationMs: Int64(candidate.durationMs),
        artistsJson: artistsJson
      ).mergeUpsert(db)

      for artist in candidate.artists where artist.uri.hasPrefix("spotify:artist:") {
        try db.execute(sql: """
          INSERT INTO artists (uri, name, genres_json, image_url)
          VALUES (?, ?, NULL, NULL)
          ON CONFLICT(uri) DO UPDATE SET
            name = COALESCE(NULLIF(name, ''), excluded.name)
          """, arguments: [artist.uri, artist.name])
      }
    }
  }
}

private struct RecentPlayCandidate {
  let playedAtMs: Int64
  let trackUri: String
  let trackName: String
  let albumName: String
  let artUrl: String?
  let durationMs: Int
  let artists: [PlaybackArtist]

  var play: Play {
    Play(
      playedAt: playedAtMs / 1000,
      trackUri: trackUri,
      msPlayed: Int64(max(durationMs, 30_000)),
      source: RecentPlaysReconciler.source)
  }

  init?(item: RecentlyPlayedItem) {
    guard let playedAtMs = item.playedAtMs,
          item.track.uri.hasPrefix("spotify:track:")
    else { return nil }

    self.playedAtMs = playedAtMs
    self.trackUri = item.track.uri
    self.trackName = item.track.name
    self.albumName = item.track.album.name
    self.artUrl = item.track.album.images.first?.url
    self.durationMs = item.track.duration_ms
    self.artists = item.track.artists.map {
      PlaybackArtist(name: $0.name, uri: $0.uri)
    }
  }
}
