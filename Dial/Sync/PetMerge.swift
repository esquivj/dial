// Dial/Sync/PetMerge.swift
import Foundation
import GRDB

/// The pet after a merge (docs/design/multi-mac-history.md, "Pet rules").
///
/// XP is a running total: each play was scored with what that Mac knew at
/// the time. So the merge starts from the donor's XP, scores only the plays
/// the donor never saw, and never lowers XP. The streak is a plain function
/// of the merged days, so it's recomputed.
enum PetMerge {
  /// A counted play the donor lacked, with what scoring it needs. `day` is
  /// the local `YYYY-MM-DD`; the artist columns are read the way
  /// `PetEngine` reads them (first artist, name lowercased and trimmed).
  struct Play: Equatable {
    let playedAt: Int64
    let msPlayed: Int64
    let source: String
    let day: String
    let album: String?
    let artistUri: String?
    let artistName: String?

    /// Columns for a query over `plays p LEFT JOIN tracks t`.
    static let columns = """
      p.played_at, p.ms_played, p.source,
      date(p.played_at, 'unixepoch', 'localtime') AS day,
      t.album_name AS album,
      CASE WHEN json_valid(t.artists_json) = 1 THEN json_extract(t.artists_json, '$[0].uri') END AS artist_uri,
      CASE WHEN json_valid(t.artists_json) = 1 THEN LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))) END AS artist_name
      """

    init(row: Row) {
      playedAt = row["played_at"]
      msPlayed = row["ms_played"]
      source = row["source"]
      day = row["day"]
      album = row["album"]
      artistUri = row["artist_uri"]
      artistName = row["artist_name"]
    }

    init(playedAt: Int64, msPlayed: Int64, source: String, day: String,
         album: String?, artistUri: String?, artistName: String?) {
      self.playedAt = playedAt
      self.msPlayed = msPlayed
      self.source = source
      self.day = day
      self.album = album
      self.artistUri = artistUri
      self.artistName = artistName
    }
  }

  /// Imports never push XP past the Companion threshold (as `Importer`).
  static let importedXPCap: Int64 = 25_000

  /// `lacked`: the counted plays the donor didn't have, oldest first. `db`
  /// is the merged archive.
  static func merged(
    local: PetState,
    snapshot: PetState?,
    donorIsSnapshot: Bool,
    lacked: [Play],
    in db: Database,
    now: Int64
  ) throws -> PetState {
    let donor = donorIsSnapshot ? (snapshot ?? local) : local
    let streaks = try StreakDays.load(in: db)
    let firsts = lacked.contains { $0.source != "import" } ? try FirstPlays.load(in: db) : FirstPlays()

    var xp = donor.xp
    for play in lacked {
      if play.source == "import" {
        let delta = XPFormula.compute(msPlayed: play.msPlayed, variety: .none, streakDays: 0)
        if xp < importedXPCap { xp = min(xp + delta, importedXPCap) }
      } else {
        xp += XPFormula.compute(
          msPlayed: play.msPlayed,
          variety: firsts.variety(for: play),
          streakDays: streaks.runs[play.day] ?? 1)
      }
    }

    var state = local
    state.xp = max(local.xp, xp)
    if let lastDay = streaks.lastDay {
      state.streakAnchorDate = lastDay
      state.streakDays = streaks.runs[lastDay] ?? 1
      state.lastPlayAt = streaks.lastPlayAt
    }
    state.installedAt = min(local.installedAt, snapshot?.installedAt ?? local.installedAt)
    state.hatchedAt = earliest(local.hatchedAt, snapshot?.hatchedAt)
    state.elderUnlockedAt = earliest(local.elderUnlockedAt, snapshot?.elderUnlockedAt)
    state.stage = PetStageTable.stage(forXP: state.xp, elderUnlocked: state.elderUnlockedAt != nil)
    if state.stage != .egg, state.hatchedAt == nil { state.hatchedAt = now }
    return state
  }

  private static func earliest(_ a: Int64?, _ b: Int64?) -> Int64? {
    switch (a, b) {
    case let (a?, b?): return min(a, b)
    default: return a ?? b
    }
  }

  /// Streak lengths over the days with a counted live or recent play, built
  /// one day at a time with `StreakCalendar`, as `PetEngine` builds them.
  private struct StreakDays {
    var runs: [String: Int64] = [:]
    var lastDay: String?
    var lastPlayAt: Int64?

    static func load(in db: Database) throws -> StreakDays {
      var streaks = StreakDays()
      let days = try String.fetchAll(db, sql: """
        SELECT DISTINCT date(played_at, 'unixepoch', 'localtime') AS day
        FROM counted_plays
        WHERE source != 'import'
        ORDER BY day
        """)
      let calendar = StreakCalendar()
      var count: Int64 = 0
      for day in days {
        let result = calendar.apply(playDate: day, priorAnchor: streaks.lastDay, priorDays: count)
        count = result.days
        streaks.runs[day] = result.days
        streaks.lastDay = day
      }
      streaks.lastPlayAt = try Int64.fetchOne(
        db, sql: "SELECT MAX(played_at) FROM counted_plays WHERE source != 'import'")
      return streaks
    }
  }

  /// When each artist and album was first played in the merged archive, to
  /// award `PetEngine`'s New Artist and New Album bonuses.
  private struct FirstPlays {
    var byArtistUri: [String: Int64] = [:]
    var byArtistName: [String: Int64] = [:]
    var byAlbumArtistUri: [String: Int64] = [:]
    var byAlbumArtistName: [String: Int64] = [:]

    static func load(in db: Database) throws -> FirstPlays {
      var firsts = FirstPlays()
      let rows = try Row.fetchCursor(db, sql: """
        SELECT MIN(p.played_at) AS first,
               t.album_name AS album,
               CASE WHEN json_valid(t.artists_json) = 1 THEN json_extract(t.artists_json, '$[0].uri') END AS artist_uri,
               CASE WHEN json_valid(t.artists_json) = 1 THEN LOWER(TRIM(json_extract(t.artists_json, '$[0].name'))) END AS artist_name
        FROM plays p
        JOIN tracks t ON t.uri = p.track_uri
        WHERE t.artists_json IS NOT NULL
        GROUP BY t.uri
        """)
      while let row = try rows.next() {
        let first: Int64 = row["first"]
        let album: String? = row["album"]
        if let uri: String = row["artist_uri"] {
          firsts.byArtistUri.keepEarliest(first, for: uri)
          if let album { firsts.byAlbumArtistUri.keepEarliest(first, for: key(album, uri)) }
        }
        if let name: String = row["artist_name"], !name.isEmpty {
          firsts.byArtistName.keepEarliest(first, for: name)
          if let album { firsts.byAlbumArtistName.keepEarliest(first, for: key(album, name)) }
        }
      }
      return firsts
    }

    /// `PetEngine.variety`, asked of the merged archive: a bonus only when
    /// no earlier play matches the artist (or the album and artist).
    func variety(for play: Play) -> VarietyBonus {
      guard let uri = play.artistUri, let rawName = play.artistName else { return .none }
      let name = rawName.isEmpty ? nil : rawName
      let firstByArtist = min(byArtistUri[uri] ?? .max, name.flatMap { byArtistName[$0] } ?? .max)
      if firstByArtist >= play.playedAt { return .newArtist }
      if let album = play.album {
        let firstOnAlbum = min(
          byAlbumArtistUri[Self.key(album, uri)] ?? .max,
          name.flatMap { byAlbumArtistName[Self.key(album, $0)] } ?? .max)
        if firstOnAlbum >= play.playedAt { return .newAlbum }
      }
      return .none
    }

    private static func key(_ album: String, _ artist: String) -> String {
      "\(album)\u{1F}\(artist)"
    }
  }
}

private extension Dictionary where Value == Int64 {
  mutating func keepEarliest(_ value: Int64, for key: Key) {
    self[key] = Swift.min(self[key] ?? value, value)
  }
}
