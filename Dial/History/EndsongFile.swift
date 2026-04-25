// Dial/History/EndsongFile.swift
import Foundation

struct EndsongRow: Equatable {
  let playedAt: Int64
  let msPlayed: Int64
  let trackUri: String
  let trackName: String?
  let artistName: String?
  let albumName: String?
}

enum EndsongFile {
  private struct Raw: Decodable {
    let ts: String?
    let ms_played: Int64?
    let spotify_track_uri: String?
    let master_metadata_track_name: String?
    let master_metadata_album_artist_name: String?
    let master_metadata_album_album_name: String?
  }

  /// Parses one Spotify Extended Streaming History JSON file. Skips malformed rows
  /// (missing `ts`, `ms_played`, `spotify_track_uri`, or unparseable timestamp).
  /// Caller is expected to iterate every file in the export folder.
  static func parse(at url: URL) throws -> [EndsongRow] {
    let data = try Data(contentsOf: url)
    let raws = try JSONDecoder().decode([Raw].self, from: data)
    let iso = ISO8601DateFormatter()
    return raws.compactMap { r in
      guard let ts = r.ts,
            let ms = r.ms_played,
            let uri = r.spotify_track_uri,
            let at = iso.date(from: ts) else { return nil }
      return EndsongRow(
        playedAt: Int64(at.timeIntervalSince1970),
        msPlayed: ms,
        trackUri: uri,
        trackName: r.master_metadata_track_name,
        artistName: r.master_metadata_album_artist_name,
        albumName: r.master_metadata_album_album_name)
    }
  }
}
