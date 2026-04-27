import Foundation
import os.log

private let pollingLog = Logger(subsystem: "com.dial.Dial", category: "PollingService")

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
  // Track previous shuffle/repeat so we only emit modesChanged on actual
  // change, not every 3s. nil means we haven't observed yet — first
  // observation always emits.
  private var lastShuffle: Bool? = nil
  private var lastRepeat: RepeatMode? = nil

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
        // Tracks consecutive failures so we can back off exponentially.
        // Reset to zero on every successful call so a single transient
        // glitch (Wi-Fi blip, brief 5xx) doesn't permanently penalize
        // future polls.
        var consecutiveFailures = 0
        pollingLog.notice("polling stream started, interval=\(self.interval)s")
        while !Task.isCancelled {
          do {
            let cp = try await client.currentlyPlaying()
            // Per-poll outcome at debug level — quiet by default but
            // available via `log show --debug` for live-play diagnosis.
            if let item = cp?.item {
              pollingLog.debug("poll: \(item.name, privacy: .public) at \(cp?.progress_ms ?? -1)ms (playing=\(cp?.is_playing ?? false))")
            } else {
              pollingLog.debug("poll: no playback")
            }
            for e in interpret(cp) { continuation.yield(e) }
            consecutiveFailures = 0
          } catch {
            // Auth permanently broken — surface to the caller. The refresh
            // token is dead and cycling here at 60s forever just wastes
            // battery while the menubar lies about being connected. Caller
            // (AppCoordinator) handles this by marking signed-out so the
            // dropdown flips to the connect view.
            if (error as? SpotifyAuthError) == .refreshFailed {
              continuation.finish(throwing: error)
              return
            }
            // Everything else: don't terminate the stream. Pre-fix, the
            // line here was `continuation.finish(throwing: error); return`,
            // which meant a single Wi-Fi blip permanently killed polling
            // for the rest of the session — the menubar would silently
            // freeze with the user thinking everything was fine.
            // Now: log + back off + keep trying.
            consecutiveFailures += 1
            pollingLog.error("error #\(consecutiveFailures): \(String(describing: error), privacy: .public)")
            // Backoff schedule (interval = 3s baseline):
            //   1st fail: 3s, 2nd: 6s, 3rd: 12s, 4th: 24s, 5th: 48s, then 60s cap.
            let multiplier = pow(2.0, Double(min(consecutiveFailures - 1, 6)))
            let backoff = min(interval * multiplier, 60.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            continue  // skip the steady-state sleep below; backoff already covered it
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
    // Modes (shuffle, repeat). Only emit if changed since last observation.
    // /me/player returns these consistently; /currently-playing wouldn't have,
    // hence the optional unwraps with sensible defaults.
    let shuffle = cp.shuffle_state ?? false
    let repeatMode = cp.repeat_state.flatMap(RepeatMode.init(rawValue:)) ?? .off
    if lastShuffle != shuffle || lastRepeat != repeatMode {
      out.append(.modesChanged(shuffle: shuffle, repeatMode: repeatMode))
      lastShuffle = shuffle
      lastRepeat = repeatMode
    }
    return out
  }
}
