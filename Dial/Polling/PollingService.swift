import Foundation

protocol PollingClient {
  func currentlyPlaying() async throws -> CurrentlyPlaying?
}
extension SpotifyClient: PollingClient {}

final class PollingService {
  private let client: PollingClient
  private let interval: TimeInterval
  private let clock: () -> Int64
  private var lastTrackUri: String?
  private var counted = false
  private var playbackState: Bool? = nil

  init(client: PollingClient,
       interval: TimeInterval = 3.0,
       clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
    self.client = client
    self.interval = interval
    self.clock = clock
  }

  func stream() -> AsyncThrowingStream<PlaybackEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        while !Task.isCancelled {
          do {
            let cp = try await client.currentlyPlaying()
            for e in interpret(cp) { continuation.yield(e) }
          } catch {
            continuation.finish(throwing: error); return
          }
          if interval > 0 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func interpret(_ cp: CurrentlyPlaying?) -> [PlaybackEvent] {
    guard let cp, let item = cp.item else {
      lastTrackUri = nil; counted = false; playbackState = nil
      return [.noPlayback]
    }
    var out: [PlaybackEvent] = []
    if item.uri != lastTrackUri {
      lastTrackUri = item.uri; counted = false
      out.append(.started(
        trackUri: item.uri, name: item.name,
        artistName: item.artists.first?.name ?? "",
        artistUri: item.artists.first?.uri,
        albumName: item.album.name,
        artUrl: item.album.images.first?.url,
        durationMs: item.duration_ms,
        at: clock()))
    }
    if let p = cp.progress_ms {
      out.append(.progress(ms: p))
      if !counted, DedupRule.shouldCount(progressMs: p, durationMs: item.duration_ms) {
        counted = true
        out.append(.countedPlay(trackUri: item.uri, msPlayed: Int64(p), at: clock()))
      }
    }
    if playbackState != cp.is_playing {
      out.append(cp.is_playing ? .resumed : .paused)
      playbackState = cp.is_playing
    }
    return out
  }
}
