import Foundation

/// Spotify's macOS app posts a distributed notification whenever local
/// playback changes. Dial uses it as the cue to read the Spotify app right
/// away (`PollingService.wake()`). Its payload only feeds the HUD directly
/// while the app can't be read (Automation access off), as a latency path in
/// front of the Web API poll, which then stays the source of counted plays.
final class SpotifyDesktopPlaybackObserver: NSObject {
  static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")

  private let center: DistributedNotificationCenter
  private var onEvents: (([PlaybackEvent]) -> Void)?
  private var lastTrackUri: String?
  private var playbackState: Bool?

  init(center: DistributedNotificationCenter = .default()) {
    self.center = center
    super.init()
  }

  deinit {
    stop()
  }

  func start(onEvents: @escaping ([PlaybackEvent]) -> Void) {
    self.onEvents = onEvents
    center.removeObserver(self, name: Self.notificationName, object: nil)
    center.addObserver(
      self,
      selector: #selector(received(_:)),
      name: Self.notificationName,
      object: nil,
      suspensionBehavior: .deliverImmediately)
  }

  func stop() {
    center.removeObserver(self, name: Self.notificationName, object: nil)
    onEvents = nil
    lastTrackUri = nil
    playbackState = nil
  }

  @objc private func received(_ notification: Notification) {
    guard let userInfo = notification.userInfo else { return }
    let events = Self.events(
      from: userInfo,
      previousTrackUri: &lastTrackUri,
      previousPlaybackState: &playbackState,
      now: Int64(Date().timeIntervalSince1970))
    if !events.isEmpty {
      onEvents?(events)
    }
  }

  static func events(
    from userInfo: [AnyHashable: Any],
    previousTrackUri: inout String?,
    previousPlaybackState: inout Bool?,
    now: Int64
  ) -> [PlaybackEvent] {
    let playerState = stringValue(for: ["Player State", "playerState", "state"], in: userInfo)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    let isPlaying: Bool? = {
      guard let playerState else { return nil }
      if playerState.contains("play") { return true }
      if playerState.contains("pause") { return false }
      return nil
    }()

    if playerState?.contains("stop") == true {
      previousTrackUri = nil
      previousPlaybackState = nil
      return [.noPlayback]
    }

    var out: [PlaybackEvent] = []
    let uri = normalizedTrackURI(from: userInfo)

    if let uri, uri != previousTrackUri {
      previousTrackUri = uri
      out.append(.started(
        trackUri: uri,
        name: stringValue(for: ["Name", "Track Name", "Title"], in: userInfo) ?? "",
        artistName: stringValue(for: ["Artist", "Artist Name"], in: userInfo) ?? "",
        artistUri: nil,
        artists: [],
        albumName: stringValue(for: ["Album", "Album Name"], in: userInfo) ?? "",
        artUrl: stringValue(for: ["Artwork URL", "ArtworkURL", "Artwork Url"], in: userInfo),
        durationMs: durationMilliseconds(from: userInfo) ?? 0,
        at: now))
    }

    if let progress = progressMilliseconds(from: userInfo) {
      out.append(.progress(ms: progress))
    } else if uri != nil, out.contains(where: { if case .started = $0 { return true } else { return false } }) {
      out.append(.progress(ms: 0))
    }

    if let isPlaying, previousPlaybackState != isPlaying {
      out.append(isPlaying ? .resumed : .paused)
      previousPlaybackState = isPlaying
    }

    return out
  }

  private static func normalizedTrackURI(from userInfo: [AnyHashable: Any]) -> String? {
    if let raw = stringValue(for: ["Track ID", "TrackID", "trackID", "track_id"], in: userInfo) {
      if raw.hasPrefix("spotify:track:") { return raw }
      if raw.hasPrefix("spotify:") { return nil }
      if !raw.isEmpty { return "spotify:track:\(raw)" }
    }

    guard let url = stringValue(for: ["Spotify URL", "SpotifyURL", "URL"], in: userInfo) else {
      return nil
    }
    if url.hasPrefix("spotify:track:") { return url }
    if let range = url.range(of: "/track/") {
      let tail = url[range.upperBound...]
      let id = tail.split(separator: "?").first.map(String.init) ?? String(tail)
      return id.isEmpty ? nil : "spotify:track:\(id)"
    }
    return nil
  }

  private static func durationMilliseconds(from userInfo: [AnyHashable: Any]) -> Int? {
    guard let raw = numberValue(for: ["Duration", "duration"], in: userInfo), raw > 0 else {
      return nil
    }
    return raw < 1_000 ? Int((raw * 1_000).rounded()) : Int(raw.rounded())
  }

  private static func progressMilliseconds(from userInfo: [AnyHashable: Any]) -> Int? {
    guard let raw = numberValue(
      for: ["Playback Position", "PlaybackPosition", "Position", "position"],
      in: userInfo), raw >= 0
    else { return nil }

    let durationMs = durationMilliseconds(from: userInfo)
    let secondsLimit = durationMs.map { Double($0) / 1_000 + 5 }
    let looksLikeSeconds = raw < 1_000 && secondsLimit.map({ raw <= $0 }) != false
    return looksLikeSeconds ? Int((raw * 1_000).rounded()) : Int(raw.rounded())
  }

  private static func stringValue(
    for names: [String],
    in userInfo: [AnyHashable: Any]
  ) -> String? {
    for name in names {
      if let value = userInfo[AnyHashable(name)] {
        if let string = value as? String, !string.isEmpty { return string }
        if let string = value as? NSString, string.length > 0 { return string as String }
      }
    }
    return nil
  }

  private static func numberValue(
    for names: [String],
    in userInfo: [AnyHashable: Any]
  ) -> Double? {
    for name in names {
      guard let value = userInfo[AnyHashable(name)] else { continue }
      if let number = value as? NSNumber { return number.doubleValue }
      if let double = value as? Double { return double }
      if let int = value as? Int { return Double(int) }
      if let string = value as? String, let double = Double(string) { return double }
      if let string = value as? NSString, let double = Double(string as String) { return double }
    }
    return nil
  }
}
