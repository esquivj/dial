// Dial/ViewModels/MenubarStripViewModel.swift
import Observation
import Foundation

enum MenubarDisplayState: Equatable { case playing, paused, nothingPlaying }

enum LikedTrackState: Equatable {
  case unknown
  case checking
  case notLiked
  case liked
  case needsReconnect
}

private struct PendingPlayerMode<Value: Equatable> {
  let value: Value
  let expiresAt: Date
}

@Observable
final class MenubarStripViewModel {
  private static let playerModeOptimisticHold: TimeInterval = 5

  var track: NowPlayingViewModel.Track?
  var state: MenubarDisplayState = .nothingPlaying
  var progressMs: Int = 0
  var durationMs: Int = 0
  var playsYTD: Int = 0
  var likedTrackState: LikedTrackState = .unknown
  /// Set whenever a fresh `.progress(ms:)` event lands. Views interpolate
  /// between polls by adding `(now - lastProgressUpdate)` to `progressMs`
  /// while `state == .playing`.
  var lastProgressUpdate: Date? = nil
  /// Current player modes. Updated on every modesChanged event from the
  /// polling service. The optimistic-flip pattern in ControlsBar mutates
  /// these directly when the user taps the toggle, then a subsequent
  /// poll either reaffirms or corrects.
  var shuffle: Bool = false
  var repeatMode: RepeatMode = .off
  private var pendingShuffle: PendingPlayerMode<Bool>?
  private var pendingRepeatMode: PendingPlayerMode<RepeatMode>?

  var hasSeekableTrack: Bool {
    track != nil && durationMs > 0
  }

  var hasLibraryTrack: Bool {
    track?.uri.hasPrefix("spotify:track:") == true
  }

  func interpolatedProgressMs(at now: Date = Date()) -> Int {
    var ms = progressMs
    if state == .playing, let lastProgressUpdate {
      ms += max(0, Int(now.timeIntervalSince(lastProgressUpdate) * 1000))
    }
    guard durationMs > 0 else { return max(0, ms) }
    return min(durationMs, max(0, ms))
  }

  func setOptimisticProgress(_ ms: Int, at now: Date = Date()) {
    progressMs = durationMs > 0 ? min(durationMs, max(0, ms)) : max(0, ms)
    lastProgressUpdate = now
  }

  func setOptimisticShuffle(_ value: Bool, at now: Date = Date()) {
    shuffle = value
    pendingShuffle = .init(
      value: value,
      expiresAt: now.addingTimeInterval(Self.playerModeOptimisticHold))
  }

  func revertOptimisticShuffle(to value: Bool) {
    shuffle = value
    pendingShuffle = nil
  }

  func setOptimisticRepeatMode(_ value: RepeatMode, at now: Date = Date()) {
    repeatMode = value
    pendingRepeatMode = .init(
      value: value,
      expiresAt: now.addingTimeInterval(Self.playerModeOptimisticHold))
  }

  func revertOptimisticRepeatMode(to value: RepeatMode) {
    repeatMode = value
    pendingRepeatMode = nil
  }

  func applyRemoteModes(shuffle remoteShuffle: Bool, repeatMode remoteRepeatMode: RepeatMode, at now: Date = Date()) {
    if shouldAcceptRemote(remoteShuffle, pending: &pendingShuffle, at: now) {
      shuffle = remoteShuffle
    }
    if shouldAcceptRemote(remoteRepeatMode, pending: &pendingRepeatMode, at: now) {
      repeatMode = remoteRepeatMode
    }
  }

  private func shouldAcceptRemote<Value: Equatable>(
    _ remoteValue: Value,
    pending: inout PendingPlayerMode<Value>?,
    at now: Date
  ) -> Bool {
    guard let pendingMode = pending else { return true }
    if remoteValue == pendingMode.value {
      pending = nil
      return true
    }
    if now < pendingMode.expiresAt {
      return false
    }
    pending = nil
    return true
  }
}
