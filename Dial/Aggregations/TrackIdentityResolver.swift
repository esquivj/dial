// Dial/Aggregations/TrackIdentityResolver.swift
import Foundation
import GRDB

enum TrackIdentityResolver {
  struct Key: Equatable {
    let title: String
    let artist: String
  }

  static func key(trackName: String?, artistName: String?) -> Key? {
    guard let title = normalizedTrackTitle(trackName),
          let artist = normalizedArtistName(artistName)
    else { return nil }
    return Key(title: title, artist: artist)
  }

  static func matchingTrackUris(
    trackUri: String,
    trackName: String?,
    artistName: String?,
    artistUri: String?,
    in db: Database
  ) throws -> [String] {
    guard let target = key(trackName: trackName, artistName: artistName) else {
      return [trackUri]
    }

    var matches = Set<String>()
    matches.insert(trackUri)

    let candidates = try candidateRows(
      trackUri: trackUri,
      artistName: artistName,
      artistUri: artistUri,
      in: db)

    for candidate in candidates {
      guard let candidateKey = key(trackName: candidate.trackName, artistName: candidate.artistName),
            candidateKey == target
      else { continue }
      matches.insert(candidate.uri)
    }

    return matches.sorted()
  }

  static func rank7d(
    matching trackUris: [String],
    anchorAt: Int64,
    in db: Database
  ) throws -> Int? {
    let uris = normalizedUriList(trackUris)
    guard !uris.isEmpty else { return nil }

    let cutoff = anchorAt - 7 * 86_400
    let target = try Row.fetchOne(db, sql: """
      SELECT COUNT(*) AS plays, MAX(played_at) AS last
      FROM plays
      WHERE played_at > ?
        AND track_uri IN (\(placeholders(for: uris)))
      """, arguments: statementArguments([cutoff], appending: uris))

    let targetPlays: Int = target?["plays"] ?? 0
    guard targetPlays > 0 else { return nil }
    let targetLast: Int64 = target?["last"] ?? 0
    let targetSet = Set(uris)

    let rows = try Row.fetchAll(db, sql: """
      SELECT track_uri, COUNT(*) AS plays, MAX(played_at) AS last
      FROM plays
      WHERE played_at > ?
      GROUP BY track_uri
      """, arguments: [cutoff])

    let stronger = rows.reduce(0) { count, row in
      let uri: String = row["track_uri"]
      guard !targetSet.contains(uri) else { return count }
      let plays: Int = row["plays"]
      let last: Int64 = row["last"]
      if plays > targetPlays { return count + 1 }
      if plays == targetPlays, last > targetLast { return count + 1 }
      return count
    }
    return stronger + 1
  }

  private static func candidateRows(
    trackUri: String,
    artistName: String?,
    artistUri: String?,
    in db: Database
  ) throws -> [(uri: String, trackName: String?, artistName: String?)] {
    let rawArtist = artistName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let artistNameFilter = rawArtist?.isEmpty == false ? rawArtist : nil
    let artistUriFilter = artistUri?.isEmpty == false ? artistUri : nil

    let rows = try Row.fetchAll(db, sql: """
      SELECT uri, name, artists_json
      FROM tracks
      WHERE uri = ?
         OR (
           artists_json IS NOT NULL
           AND json_valid(artists_json) = 1
           AND (
             (? IS NOT NULL AND json_extract(artists_json, '$[0].uri') = ?)
             OR
             (? IS NOT NULL AND LOWER(TRIM(json_extract(artists_json, '$[0].name'))) = ?)
           )
         )
      """, arguments: [
        trackUri,
        artistUriFilter,
        artistUriFilter,
        artistNameFilter,
        artistNameFilter,
      ])

    return rows.map { row in
      let artistsJson: String? = row["artists_json"]
      return (
        uri: row["uri"],
        trackName: row["name"],
        artistName: decodeFirstArtistName(artistsJson)
      )
    }
  }

  private static func normalizedTrackTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    var text = normalizedBase(value)
    text = removingVersionNoise(from: text)
    text = text.replacingOccurrences(of: "&", with: " and ")
    text = text.replacingOccurrences(
      of: #"[^a-z0-9]+"#,
      with: " ",
      options: .regularExpression)
    text = text.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private static func normalizedArtistName(_ value: String?) -> String? {
    guard let value else { return nil }
    var text = normalizedBase(value)
    text = text.replacingOccurrences(of: "&", with: " and ")
    text = text.replacingOccurrences(
      of: #"[^a-z0-9]+"#,
      with: " ",
      options: .regularExpression)
    text = text.replacingOccurrences(
      of: #"\s+"#,
      with: " ",
      options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private static func normalizedBase(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func removingVersionNoise(from value: String) -> String {
    var text = value
    let bracketNoise = [
      #"[\(\[][^\)\]]*\b\d{2,4}\s*(?:remaster|remastered)[^\)\]]*[\)\]]"#,
      #"[\(\[][^\)\]]*\b(?:remaster|remastered|explicit|clean|mono|stereo|album version|single version|radio edit)[^\)\]]*[\)\]]"#,
    ]
    for pattern in bracketNoise {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }

    let suffixNoise = [
      #"\s*[-–—]\s*\d{2,4}\s*(?:remaster|remastered)\b.*$"#,
      #"\s*[-–—]\s*(?:remaster|remastered|explicit|clean|mono|stereo|album version|single version|radio edit)\b.*$"#,
    ]
    for pattern in suffixNoise {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    return text
  }

  private static func decodeFirstArtistName(_ json: String?) -> String? {
    guard let json, let data = json.data(using: .utf8) else { return nil }
    return (try? JSONDecoder().decode([ArtistEntry].self, from: data))?.first?.name
  }

  private static func normalizedUriList(_ trackUris: [String]) -> [String] {
    var seen = Set<String>()
    return trackUris.filter { uri in
      guard !uri.isEmpty, !seen.contains(uri) else { return false }
      seen.insert(uri)
      return true
    }
  }

  private static func placeholders(for values: [String]) -> String {
    Array(repeating: "?", count: values.count).joined(separator: ",")
  }

  private static func statementArguments(
    _ values: [DatabaseValueConvertible],
    appending strings: [String]
  ) -> StatementArguments {
    var arguments = values
    arguments.append(contentsOf: strings)
    return StatementArguments(arguments)
  }
}

private struct ArtistEntry: Decodable {
  let name: String
}
