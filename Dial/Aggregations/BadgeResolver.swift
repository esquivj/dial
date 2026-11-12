// Dial/Aggregations/BadgeResolver.swift
import Foundation
import GRDB

enum BadgeRecordMode {
  case live
  case imported
}

enum BadgeResolver {
  private static let familiarArtistPlayThreshold = 20
  private static let familiarAlbumPlayThreshold = 3

  /// Rediscovered means "you came back to something that mattered", so it
  /// stays rare (PLA-95). With years of imported history almost any song
  /// unplayed for a few months qualified under the old 90-day rule: about a
  /// quarter of live plays, and up to 176 badges on one day.
  ///
  /// A play is a rediscovery when the song went unplayed for
  /// `rediscoveryMinGapDays`, had at least `rediscoveryMinPriorPlays`
  /// earlier counted plays, and no other song was rediscovered earlier the
  /// same local day. Only live plays earn the badge; recently-played
  /// backfills never do.
  static let rediscoveryMinGapDays = 180
  static let rediscoveryMinPriorPlays = 5

  static func recordMemories(for play: Play, mode: BadgeRecordMode, in db: Database) throws {
    let events = try resolveMemories(for: play, mode: mode, in: db)
    for event in events {
      try BadgeEventsDAO.insertIgnoring(event, in: db)
    }
  }

  static func resolveMemories(for play: Play, mode: BadgeRecordMode, in db: Database) throws -> [BadgeEvent] {
    let context = try TrackContext.fetch(trackUri: play.trackUri, in: db)
    var events: [BadgeEvent] = []

    let trackCount = try trackLifetimeCount(trackUri: play.trackUri, context: context, in: db)
    events.append(contentsOf: milestoneEvents(play: play, context: context, trackCount: trackCount))

    if try isAnniversary(play: play, context: context, in: db) {
      events.append(event(.anniversary, play: play, context: context, scope: "anniversary:\(play.trackUri):\(yearKey(play.playedAt))"))
    }

    guard mode == .live else {
      return events
    }

    // Recording only compares these with thresholds (artist == 1, >= 20;
    // album >= 3), so stop counting at the highest one (PLA-98).
    let artistCount = try artistLifetimeCount(context: context, upTo: familiarArtistPlayThreshold, in: db)
    let albumCount = try albumLifetimeCount(context: context, upTo: familiarAlbumPlayThreshold, in: db)

    if trackCount == 1,
       !isKnownCatalogContext(artistCount: artistCount, albumCount: albumCount) {
      events.append(event(.firstListen, play: play, context: context, scope: "first_listen:\(play.trackUri)"))
    }

    if let artistUri = context.artistUri {
      if artistCount == 1 {
        events.append(event(.newArtist, play: play, context: context, scope: "new_artist:\(artistUri)"))
      }
    }

    if play.source == "live",
       try isDeepCut(
         trackUri: play.trackUri, context: context, artistCount: artistCount, trackCount: trackCount,
         anchorAt: play.playedAt, in: db) {
      events.append(event(.deepCut, play: play, context: context, scope: "deep_cut:\(play.trackUri)"))
    }

    if play.source == "live",
       try rediscoveryGap(
         trackUri: play.trackUri, context: context, anchorAt: play.playedAt, excludingPlayID: play.id, in: db) != nil {
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
    let trackCount = try trackLifetimeCount(trackUri: trackUri, context: context, in: db)
    let effectiveTrackCount = countedCurrentPlay ? trackCount : trackCount + 1
    let artistCount = try artistLifetimeCount(context: context, in: db)
    let albumCount = try albumLifetimeCount(context: context, in: db)

    if countedCurrentPlay, let milestone = milestoneKind(trackCount: trackCount) {
      return BadgeInsight(
        kind: milestone,
        detail: "\(trackCount.formatted()) lifetime plays",
        explanation: "Shown because this counted play brought the track to exactly \(trackCount.formatted()) lifetime plays. Milestones fire only on 10, 50, and 100.")
    }

    if countedCurrentPlay,
       try hasAnniversary(trackUri: trackUri, context: context, anchorAt: anchorAt, excludingPlayID: nil, in: db) {
      return BadgeInsight(
        kind: .anniversary,
        detail: "Same calendar day, at least a year apart",
        explanation: "Shown because this track has a prior play on this same calendar day at least one year ago.")
    }

    if context.artistUri != nil {
      if (countedCurrentPlay && artistCount == 1) || (!countedCurrentPlay && artistCount == 0) {
        let displayCount = countedCurrentPlay ? artistCount : artistCount + 1
        return BadgeInsight(
          kind: .newArtist,
          detail: "First track from this artist",
          explanation: "Shown because this artist has \(displayCount.formatted()) counted lifetime play. New Artist is stronger than First Listen, so it wins when both are true.")
      }
    }

    if let days = try rediscoveryGap(trackUri: trackUri, context: context, anchorAt: anchorAt, excludingPlayID: nil, in: db) {
      return BadgeInsight(
        kind: .rediscovered,
        detail: "Last played \(days.formatted()) days ago",
        explanation: "Shown because the previous play was \(days.formatted()) days ago. \(rediscoveryRuleText)")
    }

    if try isDeepCut(
      trackUri: trackUri, context: context, artistCount: artistCount, trackCount: effectiveTrackCount,
      anchorAt: anchorAt, in: db) {
      return BadgeInsight(
        kind: .deepCut,
        detail: "Rare track from a familiar artist",
        explanation: "Shown because this artist has \(artistCount.formatted()) lifetime plays, while this track has only \(effectiveTrackCount.formatted()). Deep Cut requires 20+ artist plays and 3 or fewer track plays, at most once a day.")
    }

    if ((countedCurrentPlay && trackCount == 1) || (!countedCurrentPlay && trackCount == 0)),
       !isKnownCatalogContext(artistCount: artistCount, albumCount: albumCount) {
      let displayCount = countedCurrentPlay ? trackCount : trackCount + 1
      return BadgeInsight(
        kind: .firstListen,
        detail: "No plays in your history",
        explanation: "Shown because this track has \(displayCount.formatted()) counted lifetime play and the artist/album are not already familiar in your library. Familiar catalog tracks use Deep Cut instead of First Listen.")
    }

    if countedCurrentPlay {
      let repeatRun = try repeatRunLength(trackUri: trackUri, in: db)
      if repeatRun == 3 {
        return BadgeInsight(
          kind: .repeatTrack,
          detail: "\(repeatRun.formatted()) plays in a row",
          explanation: "Shown because this counted play started a 3-play run of the same track.")
      }

      let albumRun = try albumRunLength(context: context, in: db)
      if albumRun == 3 {
        return BadgeInsight(
          kind: .albumMode,
          detail: "\(albumRun.formatted())-track run from this album",
          explanation: "Shown because this counted play started a 3-track run from this album and artist.")
      }
    }

    if let streak = try streakContext(trackUri: trackUri, anchorAt: anchorAt, in: db),
       streak.plays30d >= 10,
      streak.rank7d <= 5 {
      return BadgeInsight(
        kind: .onStreak,
        detail: "#\(streak.rank7d) this week · \(streak.plays30d.formatted()) plays in 30d",
        explanation: "Shown because this track has \(streak.plays30d.formatted()) plays in the last 30 days and ranks #\(streak.rank7d) over the last 7 days. On Streak requires 10+ in 30d and top 5 this week.")
    }

    // Rediscovery gets a short same-day afterglow: if a track came back
    // after a long gap, replaying it later that day still carries the
    // "this returned today" meaning. Other badges must be currently true
    // and should not be resurrected from memory history.
    guard countedCurrentPlay else { return nil }
    return try recentRediscoveryInsight(trackUri: trackUri, context: context, anchorAt: anchorAt, in: db)
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

  private static func trackLifetimeCount(trackUri: String, context: TrackContext, in db: Database) throws -> Int {
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    return try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM counted_plays WHERE track_uri IN (\(placeholders(for: uris)))",
      arguments: StatementArguments(uris)) ?? 0
  }

  /// Counted plays by this track's first artist. With `limit`, counting
  /// stops there: enough for threshold checks, and far cheaper for artists
  /// with thousands of plays.
  private static func artistLifetimeCount(context: TrackContext, upTo limit: Int? = nil, in db: Database) throws -> Int {
    let tracks = try TrackArtistSQL.trackURIs(
      artistUri: context.artistUri,
      normalizedName: context.normalizedArtistName,
      in: db)
    return try countCountedPlays(inTracks: tracks, upTo: limit, in: db)
  }

  private static func albumLifetimeCount(context: TrackContext, upTo limit: Int? = nil, in db: Database) throws -> Int {
    guard let albumName = context.normalizedAlbumName else { return 0 }
    let tracks = try TrackArtistSQL.trackURIs(
      artistUri: context.artistUri,
      normalizedName: context.normalizedArtistName,
      extraCondition: "t.album_name IS NOT NULL AND LOWER(TRIM(t.album_name)) = ?",
      extraArguments: [albumName],
      in: db)
    return try countCountedPlays(inTracks: tracks, upTo: limit, in: db)
  }

  private static func countCountedPlays(
    inTracks tracks: (sql: String, arguments: StatementArguments),
    upTo limit: Int?,
    in db: Database
  ) throws -> Int {
    guard let limit else {
      return try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM counted_plays WHERE track_uri IN (\(tracks.sql))",
        arguments: tracks.arguments) ?? 0
    }
    return try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM (SELECT 1 FROM counted_plays WHERE track_uri IN (\(tracks.sql)) LIMIT ?)",
      arguments: tracks.arguments + [limit]) ?? 0
  }

  private static func isKnownCatalogContext(artistCount: Int, albumCount: Int) -> Bool {
    artistCount >= familiarArtistPlayThreshold || albumCount >= familiarAlbumPlayThreshold
  }

  private static let rediscoveryRuleText =
    "Rediscovered needs a \(rediscoveryMinGapDays)+ day gap and \(rediscoveryMinPriorPlays)+ earlier plays, at most once a day."

  /// Whether playing this track at `anchorAt` would be a rediscovery, for
  /// the pet's rediscovery expression.
  static func isRediscovery(trackUri: String, anchorAt: Int64, in db: Database) throws -> Bool {
    let context = try TrackContext.fetch(trackUri: trackUri, in: db)
    return try rediscoveryGap(trackUri: trackUri, context: context, anchorAt: anchorAt, excludingPlayID: nil, in: db) != nil
  }

  /// Days since the song's previous counted play, when a play at `anchorAt`
  /// is a rediscovery (see `rediscoveryMinGapDays`); nil otherwise.
  private static func rediscoveryGap(
    trackUri: String,
    context: TrackContext,
    anchorAt: Int64,
    excludingPlayID: Int64?,
    in db: Database
  ) throws -> Int? {
    guard let days = try rediscoveryGapDays(
      trackUri: trackUri, context: context, anchorAt: anchorAt, excludingPlayID: excludingPlayID, in: db),
      days >= rediscoveryMinGapDays
    else { return nil }

    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    var exclusion = ""
    var arguments: [DatabaseValueConvertible] = uris
    if let excludingPlayID {
      exclusion = "AND id != ?"
      arguments.append(excludingPlayID)
    }
    arguments.append(anchorAt)
    arguments.append(rediscoveryMinPriorPlays)
    let priorPlays = try Int.fetchOne(db, sql: """
      SELECT COUNT(*) FROM (
        SELECT 1 FROM counted_plays
        WHERE track_uri IN (\(placeholders(for: uris))) \(exclusion) AND played_at < ?
        LIMIT ?)
      """, arguments: StatementArguments(arguments)) ?? 0
    guard priorPlays >= rediscoveryMinPriorPlays else { return nil }

    guard try !anotherSongEarnedToday(.rediscovered, otherThan: uris, before: anchorAt, in: db) else { return nil }
    return days
  }

  /// Deep Cut means "a rare track from an artist you love" (PLA-100). The
  /// artist has 20+ counted plays and this track 3 or fewer, it's a live
  /// play (or the track playing now), and no other song earned Deep Cut
  /// earlier the same local day. Without the cap a new album from a familiar
  /// artist made every track a Deep Cut: about 6 a day, up to 82 in one day.
  private static func isDeepCut(
    trackUri: String,
    context: TrackContext,
    artistCount: Int,
    trackCount: Int,
    anchorAt: Int64,
    in db: Database
  ) throws -> Bool {
    guard context.artistUri != nil, artistCount >= familiarArtistPlayThreshold, trackCount <= 3 else { return false }
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    return try !anotherSongEarnedToday(.deepCut, otherThan: uris, before: anchorAt, in: db)
  }

  /// Whether a song other than `uris` earned `kind` earlier on the local
  /// day of `anchorAt`: the once-a-day cap on the rarer memories.
  private static func anotherSongEarnedToday(
    _ kind: BadgeMemoryKind,
    otherThan uris: [String],
    before anchorAt: Int64,
    in db: Database
  ) throws -> Bool {
    let dayStart = Int64(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(anchorAt)))
      .timeIntervalSince1970)
    var arguments: [DatabaseValueConvertible] = [kind.rawValue, dayStart, anchorAt]
    arguments.append(contentsOf: uris)
    return try Int.fetchOne(db, sql: """
      SELECT 1 FROM badge_events
      WHERE kind = ? AND earned_at >= ? AND earned_at < ?
        AND (track_uri IS NULL OR track_uri NOT IN (\(placeholders(for: uris))))
      LIMIT 1
      """, arguments: StatementArguments(arguments)) != nil
  }

  private static func rediscoveryGapDays(
    trackUri: String,
    context: TrackContext,
    anchorAt: Int64,
    excludingPlayID: Int64?,
    in db: Database
  ) throws -> Int? {
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    var arguments: [DatabaseValueConvertible] = uris
    var exclusion = ""
    if let excludingPlayID {
      exclusion = "AND id != ?"
      arguments.append(excludingPlayID)
    }
    arguments.append(anchorAt)

    guard let prior = try Int64.fetchOne(db, sql: """
      SELECT MAX(played_at)
      FROM counted_plays
      WHERE track_uri IN (\(placeholders(for: uris)))
        \(exclusion)
        AND played_at < ?
      """, arguments: StatementArguments(arguments))
    else { return nil }
    return Int((anchorAt - prior) / 86_400)
  }

  private static func recentRediscoveryInsight(
    trackUri: String,
    context: TrackContext,
    anchorAt: Int64,
    in db: Database
  ) throws -> BadgeInsight? {
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    var arguments: [DatabaseValueConvertible] = uris
    arguments.append(BadgeMemoryKind.rediscovered.rawValue)
    arguments.append(anchorAt - 24 * 60 * 60)
    arguments.append(anchorAt)

    guard let event = try BadgeEvent.fetchOne(db, sql: """
      SELECT *
      FROM badge_events
      WHERE track_uri IN (\(placeholders(for: uris)))
        AND kind = ?
        AND earned_at >= ?
        AND earned_at <= ?
      ORDER BY earned_at DESC, id DESC
      LIMIT 1
      """, arguments: StatementArguments(arguments))
    else { return nil }

    let detail = try recentDetail(for: event, trackUri: trackUri, context: context, in: db)
    return BadgeInsight(
      kind: event.kind,
      detail: detail,
      explanation: "\(detail). Rediscovered stays visible for same-day replays after the original return.")
  }

  private static func recentDetail(for event: BadgeEvent, trackUri: String, context: TrackContext, in db: Database) throws -> String {
    switch event.kind {
    case .firstListen:
      return "First heard today"
    case .newArtist:
      return "First artist play today"
    case .rediscovered:
      if let days = try rediscoveryGapDays(
        trackUri: trackUri,
        context: context,
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
    let context = try TrackContext.fetch(trackUri: play.trackUri, in: db)
    let uris = try matchingTrackUris(trackUri: play.trackUri, context: context, in: db)
    let plays30d = try trackCount30d ?? Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM counted_plays WHERE track_uri IN (\(placeholders(for: uris))) AND played_at > ?",
      arguments: statementArguments(uris, appending: [cutoff30])) ?? 0
    guard plays30d >= 10 else { return false }

    let rank = try TrackIdentityResolver.rank7d(
      matching: uris,
      anchorAt: play.playedAt,
      in: db)
    return (rank ?? Int.max) <= 5
  }

  private static func isRepeatTrack(play: Play, in db: Database) throws -> Bool {
    let context = try TrackContext.fetch(trackUri: play.trackUri, in: db)
    let uris = try matchingTrackUris(trackUri: play.trackUri, context: context, in: db)
    let uriSet = Set(uris)
    guard try repeatRunLength(matching: uris, in: db) == 3 else { return false }
    let rows = try String.fetchAll(db, sql: """
      SELECT track_uri
      FROM counted_plays
      ORDER BY played_at DESC, id DESC
      LIMIT 4
      """)
    return rows.count == 3 || !uriSet.contains(rows[3])
  }

  private static func repeatRunLength(trackUri: String, in db: Database) throws -> Int {
    let context = try TrackContext.fetch(trackUri: trackUri, in: db)
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    return try repeatRunLength(matching: uris, in: db)
  }

  private static func repeatRunLength(matching uris: [String], in db: Database) throws -> Int {
    let uriSet = Set(uris)
    let rows = try String.fetchAll(db, sql: """
      SELECT track_uri
      FROM counted_plays
      ORDER BY played_at DESC, id DESC
      LIMIT 20
      """)
    var count = 0
    for row in rows {
      guard uriSet.contains(row) else { break }
      count += 1
    }
    return count
  }

  private static func isAlbumMode(play: Play, context: TrackContext, in db: Database) throws -> Bool {
    guard try albumRunLength(context: context, in: db) == 3 else { return false }
    let rows = try Row.fetchAll(db, sql: """
      SELECT t.album_name AS album_name,
             COALESCE(
               alias.canonical_uri,
               CASE WHEN json_valid(t.artists_json) = 1
                    THEN json_extract(t.artists_json, '$[0].uri')
                    ELSE NULL END
             ) AS artist_uri
      FROM counted_plays p
      LEFT JOIN tracks t ON t.uri = p.track_uri
      LEFT JOIN artist_identity_aliases alias
        ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                   THEN json_extract(t.artists_json, '$[0].uri')
                                   ELSE NULL END
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
             COALESCE(
               alias.canonical_uri,
               CASE WHEN json_valid(t.artists_json) = 1
                    THEN json_extract(t.artists_json, '$[0].uri')
                    ELSE NULL END
             ) AS artist_uri
      FROM counted_plays p
      LEFT JOIN tracks t ON t.uri = p.track_uri
      LEFT JOIN artist_identity_aliases alias
        ON alias.source_uri = CASE WHEN json_valid(t.artists_json) = 1
                                   THEN json_extract(t.artists_json, '$[0].uri')
                                   ELSE NULL END
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

  private static func isAnniversary(play: Play, context: TrackContext, in db: Database) throws -> Bool {
    try hasAnniversary(
      trackUri: play.trackUri,
      context: context,
      anchorAt: play.playedAt,
      excludingPlayID: play.id,
      in: db)
  }

  private static func hasAnniversary(
    trackUri: String,
    context: TrackContext,
    anchorAt: Int64,
    excludingPlayID: Int64?,
    in db: Database
  ) throws -> Bool {
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    var arguments: [DatabaseValueConvertible] = uris
    var exclusion = ""
    if let excludingPlayID {
      exclusion = "AND id != ?"
      arguments.append(excludingPlayID)
    }

    let oneYearAgo = anchorAt - 365 * 86_400
    arguments.append(oneYearAgo)

    let priorRows = try Int64.fetchAll(db, sql: """
      SELECT played_at
      FROM counted_plays
      WHERE track_uri IN (\(placeholders(for: uris)))
        \(exclusion)
        AND played_at <= ?
      """, arguments: StatementArguments(arguments))
    guard !priorRows.isEmpty else { return false }

    let calendar = Calendar(identifier: .gregorian)
    let current = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: TimeInterval(anchorAt)))
    return priorRows.contains { unix in
      let prior = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: TimeInterval(unix)))
      return prior.month == current.month && prior.day == current.day
    }
  }

  private static func matchingTrackUris(trackUri: String, context: TrackContext, in db: Database) throws -> [String] {
    try TrackIdentityResolver.matchingTrackUris(
      trackUri: trackUri,
      trackName: context.trackName,
      artistName: context.artistName,
      artistUri: context.artistUri,
      in: db)
  }

  private static func placeholders(for values: [String]) -> String {
    Array(repeating: "?", count: values.count).joined(separator: ",")
  }

  private static func statementArguments(_ uris: [String], appending values: [DatabaseValueConvertible]) -> StatementArguments {
    var arguments: [DatabaseValueConvertible] = uris
    arguments.append(contentsOf: values)
    return StatementArguments(arguments)
  }

  private static func streakContext(trackUri: String, anchorAt: Int64, in db: Database) throws -> (plays30d: Int, rank7d: Int)? {
    let cutoff30 = anchorAt - 30 * 86_400
    let context = try TrackContext.fetch(trackUri: trackUri, in: db)
    let uris = try matchingTrackUris(trackUri: trackUri, context: context, in: db)
    let plays30d = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM counted_plays WHERE track_uri IN (\(placeholders(for: uris))) AND played_at > ?",
      arguments: statementArguments(uris, appending: [cutoff30])) ?? 0
    guard plays30d >= 10 else { return nil }

    guard let rank = try TrackIdentityResolver.rank7d(
      matching: uris,
      anchorAt: anchorAt,
      in: db)
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
  let trackName: String?
  let albumName: String?
  let artistName: String?
  let artistUri: String?
  var normalizedTrackName: String? {
    let normalized = trackName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized?.isEmpty == false ? normalized : nil
  }
  var normalizedArtistName: String? {
    let normalized = artistName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized?.isEmpty == false ? normalized : nil
  }
  var normalizedAlbumName: String? {
    let normalized = albumName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized?.isEmpty == false ? normalized : nil
  }

  static func fetch(trackUri: String, in db: Database) throws -> TrackContext {
    guard let track = try Track.fetchOne(db, key: trackUri) else {
      return TrackContext(trackName: nil, albumName: nil, artistName: nil, artistUri: nil)
    }

    let artist = decodeFirstArtist(track.artistsJson)
    let alias = try artist.flatMap { artist in
      try Row.fetchOne(
        db,
        sql: "SELECT canonical_uri, canonical_name FROM artist_identity_aliases WHERE source_uri = ?",
        arguments: [artist.uri])
    }
    return TrackContext(
      trackName: track.name,
      albumName: track.albumName,
      artistName: alias?["canonical_name"] ?? artist?.name,
      artistUri: alias?["canonical_uri"] ?? artist?.uri)
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
