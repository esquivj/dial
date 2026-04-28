// Dial/Aggregations/BadgeResolver.swift
import Foundation
import GRDB

enum BadgeRecordMode {
  case live
  case imported
}

enum BadgeResolver {
  static func recordMemories(for play: Play, mode: BadgeRecordMode, in db: Database) throws {
    let events = try resolveMemories(for: play, mode: mode, in: db)
    for event in events {
      try BadgeEventsDAO.insertIgnoring(event, in: db)
    }
  }

  static func resolveMemories(for play: Play, mode: BadgeRecordMode, in db: Database) throws -> [BadgeEvent] {
    let context = try TrackContext.fetch(trackUri: play.trackUri, in: db)
    var events: [BadgeEvent] = []

    let trackCount = try trackLifetimeCount(trackUri: play.trackUri, in: db)
    events.append(contentsOf: milestoneEvents(play: play, context: context, trackCount: trackCount))

    if try isAnniversary(play: play, in: db) {
      events.append(event(.anniversary, play: play, context: context, scope: "anniversary:\(play.trackUri):\(yearKey(play.playedAt))"))
    }

    guard mode == .live else {
      return events
    }

    if trackCount == 1 {
      events.append(event(.firstListen, play: play, context: context, scope: "first_listen:\(play.trackUri)"))
    }

    if let artistUri = context.artistUri {
      let artistCount = try artistLifetimeCount(artistUri: artistUri, in: db)
      if artistCount == 1 {
        events.append(event(.newArtist, play: play, context: context, scope: "new_artist:\(artistUri)"))
      }
      if artistCount >= 20, trackCount <= 3 {
        events.append(event(.deepCut, play: play, context: context, scope: "deep_cut:\(play.trackUri)"))
      }
    }

    if try wasRediscovered(play: play, in: db) {
      events.append(event(.rediscovered, play: play, context: context, scope: "rediscovered:\(play.trackUri):\(play.playedAt)"))
    }

    if try isOnStreak(play: play, trackCount30d: nil, in: db) {
      events.append(event(.onStreak, play: play, context: context, scope: "on_streak:\(play.trackUri):\(weekKey(play.playedAt))"))
    }

    if try isRepeatTrack(play: play, in: db) {
      events.append(event(.repeatTrack, play: play, context: context, scope: "repeat_track:\(play.trackUri):\(play.playedAt)"))
    }

    if try isAlbumMode(play: play, context: context, in: db) {
      let albumScope = [context.artistUri, context.albumName]
        .compactMap { $0 }
        .joined(separator: ":")
      events.append(event(.albumMode, play: play, context: context, scope: "album_mode:\(albumScope):\(play.playedAt)"))
    }

    return events
  }

  static func currentInsight(
    trackUri: String,
    anchorAt: Int64,
    countedCurrentPlay: Bool,
    in db: Database
  ) throws -> BadgeInsight? {
    let context = try TrackContext.fetch(trackUri: trackUri, in: db)
    let trackCount = try trackLifetimeCount(trackUri: trackUri, in: db)
    let effectiveTrackCount = countedCurrentPlay ? trackCount : trackCount + 1

    if countedCurrentPlay, let milestone = milestoneKind(trackCount: trackCount) {
      return BadgeInsight(kind: milestone, detail: "\(trackCount.formatted()) lifetime plays")
    }

    if countedCurrentPlay,
       try hasAnniversary(trackUri: trackUri, anchorAt: anchorAt, excludingPlayID: nil, in: db) {
      return BadgeInsight(kind: .anniversary, detail: "Same calendar day, at least a year apart")
    }

    if let artistUri = context.artistUri {
      let artistCount = try artistLifetimeCount(artistUri: artistUri, in: db)
      if (countedCurrentPlay && artistCount == 1) || (!countedCurrentPlay && artistCount == 0) {
        return BadgeInsight(kind: .newArtist, detail: "First track from this artist")
      }
    }

    if (countedCurrentPlay && trackCount == 1) || (!countedCurrentPlay && trackCount == 0) {
      return BadgeInsight(kind: .firstListen, detail: "No plays in your history")
    }

    if let days = try rediscoveryGapDays(trackUri: trackUri, anchorAt: anchorAt, excludingPlayID: nil, in: db),
       days >= 90 {
      return BadgeInsight(kind: .rediscovered, detail: "Last played \(days.formatted()) days ago")
    }

    if let artistUri = context.artistUri {
      let artistCount = try artistLifetimeCount(artistUri: artistUri, in: db)
      if artistCount >= 20, effectiveTrackCount <= 3 {
        return BadgeInsight(kind: .deepCut, detail: "\(artistCount.formatted()) plays from this artist · rare track")
      }
    }

    if countedCurrentPlay {
      let repeatRun = try repeatRunLength(trackUri: trackUri, in: db)
      if repeatRun >= 3 {
        return BadgeInsight(kind: .repeatTrack, detail: "\(repeatRun.formatted()) plays in a row")
      }

      let albumRun = try albumRunLength(context: context, in: db)
      if albumRun >= 3 {
        return BadgeInsight(kind: .albumMode, detail: "\(albumRun.formatted())-track run from this album")
      }
    }

    if let streak = try streakContext(trackUri: trackUri, anchorAt: anchorAt, in: db),
       streak.plays30d >= 10,
       streak.rank7d <= 5 {
      return BadgeInsight(
        kind: .onStreak,
        detail: "#\(streak.rank7d) this week · \(streak.plays30d.formatted()) plays in 30d")
    }

    // Recent one-shot memories are only reused while handling a play that
    // actually counted. A skip-back/dedupe replay should not re-earn
    // FIRST LISTEN / NEW ARTIST / REDISCOVERED just because that memory
    // happened earlier today.
    guard countedCurrentPlay else { return nil }
    return try recentTrackInsight(trackUri: trackUri, anchorAt: anchorAt, in: db)
  }

  private static func milestoneEvents(play: Play, context: TrackContext, trackCount: Int) -> [BadgeEvent] {
    guard let kind = milestoneKind(trackCount: trackCount) else { return [] }
    return [event(kind, play: play, context: context, scope: "\(kind.rawValue):\(play.trackUri)")]
  }

  private static func milestoneKind(trackCount: Int) -> BadgeMemoryKind? {
    switch trackCount {
    case 10: return .play10
    case 50: return .play50
    case 100: return .play100
    default: return nil
    }
  }

  private static func event(
    _ kind: BadgeMemoryKind,
    play: Play,
    context: TrackContext,
    scope: String
  ) -> BadgeEvent {
    BadgeEvent(
      id: nil,
      kind: kind,
      category: kind.category,
      trackUri: play.trackUri,
      artistUri: context.artistUri,
      albumName: context.albumName,
      earnedAt: play.playedAt,
      payloadJson: nil,
      scopeKey: scope)
  }

  private static func trackLifetimeCount(trackUri: String, in db: Database) throws -> Int {
    try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ?",
      arguments: [trackUri]) ?? 0
  }

  private static func artistLifetimeCount(artistUri: String, in db: Database) throws -> Int {
    try Int.fetchOne(db, sql: """
      SELECT COUNT(*)
      FROM plays p
      JOIN tracks t ON t.uri = p.track_uri
      WHERE t.artists_json IS NOT NULL
        AND json_valid(t.artists_json) = 1
        AND json_extract(t.artists_json, '$[0].uri') = ?
      """, arguments: [artistUri]) ?? 0
  }

  private static func wasRediscovered(play: Play, in db: Database) throws -> Bool {
    guard let days = try rediscoveryGapDays(
      trackUri: play.trackUri,
      anchorAt: play.playedAt,
      excludingPlayID: play.id,
      in: db)
    else { return false }
    return days >= 90
  }

  private static func rediscoveryGapDays(
    trackUri: String,
    anchorAt: Int64,
    excludingPlayID: Int64?,
    in db: Database
  ) throws -> Int? {
    guard let prior = try Int64.fetchOne(db, sql: """
      SELECT MAX(played_at)
      FROM plays
      WHERE track_uri = ?
        AND (? IS NULL OR id != ?)
        AND played_at < ?
      """, arguments: [trackUri, excludingPlayID, excludingPlayID, anchorAt])
    else { return nil }
    return Int((anchorAt - prior) / 86_400)
  }

  private static func recentTrackInsight(trackUri: String, anchorAt: Int64, in db: Database) throws -> BadgeInsight? {
    let events = try BadgeEvent.fetchAll(db, sql: """
      SELECT *
      FROM badge_events
      WHERE track_uri = ?
        AND earned_at >= ?
        AND earned_at <= ?
      ORDER BY earned_at DESC, id DESC
      LIMIT 12
      """, arguments: [trackUri, anchorAt - 24 * 60 * 60, anchorAt])
    guard let event = events.max(by: { lhs, rhs in
      if lhs.earnedAt != rhs.earnedAt {
        return lhs.earnedAt < rhs.earnedAt
      }
      return recentDisplayPriority(lhs.kind) < recentDisplayPriority(rhs.kind)
    }) else {
      return nil
    }

    return BadgeInsight(
      kind: event.kind,
      detail: try recentDetail(for: event, trackUri: trackUri, in: db))
  }

  private static func recentDisplayPriority(_ kind: BadgeMemoryKind) -> Int {
    switch kind {
    case .firstListen: return 100
    case .newArtist: return 95
    case .rediscovered: return 90
    case .deepCut: return 80
    case .play100: return 74
    case .play50: return 73
    case .play10: return 72
    case .anniversary: return 70
    case .repeatTrack: return 62
    case .albumMode: return 61
    case .onStreak: return 60
    }
  }

  private static func recentDetail(for event: BadgeEvent, trackUri: String, in db: Database) throws -> String {
    switch event.kind {
    case .firstListen:
      return "First heard today"
    case .newArtist:
      return "First artist play today"
    case .rediscovered:
      if let days = try rediscoveryGapDays(
        trackUri: trackUri,
        anchorAt: event.earnedAt,
        excludingPlayID: nil,
        in: db) {
        return "Came back after \(days.formatted()) days"
      }
      return "Rediscovered today"
    case .deepCut:
      return "Rare track from a familiar artist"
    case .onStreak:
      return "Heavy rotation today"
    case .repeatTrack:
      return "Repeat run today"
    case .albumMode:
      return "Album run today"
    case .play10:
      return "10th lifetime play today"
    case .play50:
      return "50th lifetime play today"
    case .play100:
      return "100th lifetime play today"
    case .anniversary:
      return "Listening anniversary today"
    }
  }

  private static func isOnStreak(play: Play, trackCount30d: Int?, in db: Database) throws -> Bool {
    let cutoff30 = play.playedAt - 30 * 86_400
    let plays30d = try trackCount30d ?? Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND played_at > ?",
      arguments: [play.trackUri, cutoff30]) ?? 0
    guard plays30d >= 10 else { return false }

    let cutoff7 = play.playedAt - 7 * 86_400
    let rank = try Int.fetchOne(db, sql: """
      WITH ranked AS (
        SELECT track_uri, COUNT(*) AS c, MAX(played_at) AS last
        FROM plays
        WHERE played_at > ?
        GROUP BY track_uri
      )
      SELECT rnk FROM (
        SELECT track_uri, ROW_NUMBER() OVER (ORDER BY c DESC, last DESC) AS rnk
        FROM ranked
      )
      WHERE track_uri = ?
      """, arguments: [cutoff7, play.trackUri])
    return (rank ?? Int.max) <= 5
  }

  private static func isRepeatTrack(play: Play, in db: Database) throws -> Bool {
    guard try repeatRunLength(trackUri: play.trackUri, in: db) == 3 else { return false }
    let rows = try String.fetchAll(db, sql: """
      SELECT track_uri
      FROM plays
      ORDER BY played_at DESC, id DESC
      LIMIT 4
      """)
    return rows.count == 3 || rows[3] != play.trackUri
  }

  private static func repeatRunLength(trackUri: String, in db: Database) throws -> Int {
    let rows = try String.fetchAll(db, sql: """
      SELECT track_uri
      FROM plays
      ORDER BY played_at DESC, id DESC
      LIMIT 20
      """)
    var count = 0
    for row in rows {
      guard row == trackUri else { break }
      count += 1
    }
    return count
  }

  private static func isAlbumMode(play: Play, context: TrackContext, in db: Database) throws -> Bool {
    guard try albumRunLength(context: context, in: db) == 3 else { return false }
    let rows = try Row.fetchAll(db, sql: """
      SELECT t.album_name AS album_name,
             CASE WHEN json_valid(t.artists_json) = 1
                  THEN json_extract(t.artists_json, '$[0].uri')
                  ELSE NULL END AS artist_uri
      FROM plays p
      LEFT JOIN tracks t ON t.uri = p.track_uri
      ORDER BY p.played_at DESC, p.id DESC
      LIMIT 4
      """)
    guard rows.count == 4 else { return true }
    let previousAlbum: String? = rows[3]["album_name"]
    let previousArtist: String? = rows[3]["artist_uri"]
    return previousAlbum != context.albumName || previousArtist != context.artistUri
  }

  private static func albumRunLength(context: TrackContext, in db: Database) throws -> Int {
    guard let album = context.albumName, !album.isEmpty else { return 0 }
    let rows = try Row.fetchAll(db, sql: """
      SELECT t.album_name AS album_name,
             CASE WHEN json_valid(t.artists_json) = 1
                  THEN json_extract(t.artists_json, '$[0].uri')
                  ELSE NULL END AS artist_uri
      FROM plays p
      LEFT JOIN tracks t ON t.uri = p.track_uri
      ORDER BY p.played_at DESC, p.id DESC
      LIMIT 20
      """)
    var count = 0
    for row in rows {
      let rowAlbum: String? = row["album_name"]
      let rowArtist: String? = row["artist_uri"]
      guard rowAlbum == album, rowArtist == context.artistUri else { break }
      count += 1
    }
    return count
  }

  private static func isAnniversary(play: Play, in db: Database) throws -> Bool {
    try hasAnniversary(
      trackUri: play.trackUri,
      anchorAt: play.playedAt,
      excludingPlayID: play.id,
      in: db)
  }

  private static func hasAnniversary(
    trackUri: String,
    anchorAt: Int64,
    excludingPlayID: Int64?,
    in db: Database
  ) throws -> Bool {
    let oneYearAgo = anchorAt - 365 * 86_400
    let priorRows = try Int64.fetchAll(db, sql: """
      SELECT played_at
      FROM plays
      WHERE track_uri = ?
        AND (? IS NULL OR id != ?)
        AND played_at <= ?
      """, arguments: [trackUri, excludingPlayID, excludingPlayID, oneYearAgo])
    guard !priorRows.isEmpty else { return false }

    let calendar = Calendar(identifier: .gregorian)
    let current = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: TimeInterval(anchorAt)))
    return priorRows.contains { unix in
      let prior = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: TimeInterval(unix)))
      return prior.month == current.month && prior.day == current.day
    }
  }

  private static func streakContext(trackUri: String, anchorAt: Int64, in db: Database) throws -> (plays30d: Int, rank7d: Int)? {
    let cutoff30 = anchorAt - 30 * 86_400
    let plays30d = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM plays WHERE track_uri = ? AND played_at > ?",
      arguments: [trackUri, cutoff30]) ?? 0
    guard plays30d >= 10 else { return nil }

    let cutoff7 = anchorAt - 7 * 86_400
    guard let rank = try Int.fetchOne(db, sql: """
      WITH ranked AS (
        SELECT track_uri, COUNT(*) AS c, MAX(played_at) AS last
        FROM plays
        WHERE played_at > ?
        GROUP BY track_uri
      )
      SELECT rnk FROM (
        SELECT track_uri, ROW_NUMBER() OVER (ORDER BY c DESC, last DESC) AS rnk
        FROM ranked
      )
      WHERE track_uri = ?
      """, arguments: [cutoff7, trackUri])
    else { return nil }

    return (plays30d, rank)
  }

  private static func weekKey(_ unix: Int64) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "YYYY-ww"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
  }

  private static func yearKey(_ unix: Int64) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
  }
}

private struct TrackContext {
  let albumName: String?
  let artistName: String?
  let artistUri: String?

  static func fetch(trackUri: String, in db: Database) throws -> TrackContext {
    guard let track = try Track.fetchOne(db, key: trackUri) else {
      return TrackContext(albumName: nil, artistName: nil, artistUri: nil)
    }

    let artist = decodeFirstArtist(track.artistsJson)
    return TrackContext(
      albumName: track.albumName,
      artistName: artist?.name,
      artistUri: artist?.uri)
  }

  private static func decodeFirstArtist(_ json: String?) -> ArtistEntry? {
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return (try? JSONDecoder().decode([ArtistEntry].self, from: data))?.first
  }
}

private struct ArtistEntry: Decodable {
  let name: String
  let uri: String
}
