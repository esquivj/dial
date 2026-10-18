// Dial/ViewModels/PlaybackCommands.swift
import Foundation

/// Player commands Dial sends. `SpotifyClient` sends them over the Web API,
/// which reaches whichever device is playing (the desktop app, a phone, a
/// speaker) no matter which source is reading now-playing.
protocol PlaybackTransport: AnyObject {
  func play() async throws
  func pause() async throws
  func next() async throws
  func prev() async throws
  func volumePercent() async throws -> Int?
  func setVolume(percent: Int) async throws
}

extension SpotifyClient: PlaybackTransport {}

/// Liked Songs reads and writes.
protocol LikedLibrary: AnyObject {
  func likeTrack(uri: String) async throws
  func unlikeTrack(uri: String) async throws
  func isTrackLiked(uri: String) async throws -> Bool
}

extension SpotifyClient: LikedLibrary {
  func likeTrack(uri: String) async throws { try await saveToLibrary(uri: uri) }
  func unlikeTrack(uri: String) async throws { try await removeFromLibrary(uri: uri) }
  func isTrackLiked(uri: String) async throws -> Bool { try await libraryContains(uri: uri) }
}

/// The transport row's play/pause/next/previous, shared by the HUD buttons
/// and the global hotkeys so both update the strip the same way.
struct TransportCommands {
  let menubar: MenubarStripViewModel
  let transport: PlaybackTransport

  /// Flips the shown state at once, then asks Spotify. Returns true when
  /// the command was "play". `onFailure` runs on the main actor after the
  /// shown state has been put back.
  @discardableResult
  func togglePlayPause(onFailure: @escaping () -> Void = {}) -> Bool {
    let wasPlaying = menubar.state == .playing
    let now = Date()
    menubar.setOptimisticProgress(menubar.interpolatedProgressMs(at: now), at: now)
    menubar.state = wasPlaying ? .paused : .playing
    let transport = transport
    let menubar = menubar
    Task {
      do {
        if wasPlaying { try await transport.pause() }
        else          { try await transport.play() }
      } catch {
        await MainActor.run {
          menubar.state = wasPlaying ? .playing : .paused
          onFailure()
        }
      }
    }
    return !wasPlaying
  }

  func next(onFailure: @escaping () -> Void = {}) {
    send(onFailure: onFailure) { try await $0.next() }
  }

  func previous(onFailure: @escaping () -> Void = {}) {
    send(onFailure: onFailure) { try await $0.prev() }
  }

  private func send(onFailure: @escaping () -> Void, _ command: @escaping (PlaybackTransport) async throws -> Void) {
    let transport = transport
    Task {
      do { try await command(transport) }
      catch { await MainActor.run { onFailure() } }
    }
  }
}

enum LikedToggleOutcome: Equatable {
  case liked
  case unliked
  /// Spotify needs a fresh sign-in with library access.
  case needsReconnect
  /// Nothing likeable is playing, or a check is already in flight.
  case unavailable
}

/// The heart button's logic: flip the shown state, write it to Liked
/// Songs, then confirm with a read. Shared by the button and the hotkey.
struct LikedTrackController {
  let menubar: MenubarStripViewModel
  let library: LikedLibrary
  let onReconnect: () async throws -> Void

  var canToggle: Bool {
    menubar.hasLibraryTrack && menubar.likedTrackState != .checking
  }

  /// - Parameter allowReconnect: when Spotify needs a new sign-in, the
  ///   button starts it; a hotkey shouldn't open a browser, so it passes
  ///   false and just reports `.needsReconnect`.
  @discardableResult
  func toggle(allowReconnect: Bool = true) -> LikedToggleOutcome {
    guard let uri = menubar.track?.uri, canToggle else { return .unavailable }
    let previous = menubar.likedTrackState

    if previous == .needsReconnect {
      guard allowReconnect else { return .needsReconnect }
      menubar.likedTrackState = .checking
      Task {
        do {
          try await onReconnect()
          let sameTrack = await MainActor.run { menubar.track?.uri == uri }
          guard sameTrack else { return }
          await writeLikedState(uri: uri, shouldLike: true, previous: .notLiked)
        } catch {
          await MainActor.run {
            guard menubar.track?.uri == uri else { return }
            menubar.likedTrackState = .needsReconnect
          }
        }
      }
      return .needsReconnect
    }

    let shouldLike = previous != .liked
    menubar.likedTrackState = shouldLike ? .liked : .notLiked
    Task {
      await writeLikedState(uri: uri, shouldLike: shouldLike, previous: previous)
    }
    return shouldLike ? .liked : .unliked
  }

  private func writeLikedState(uri: String, shouldLike: Bool, previous: LikedTrackState) async {
    do {
      if shouldLike {
        try await library.likeTrack(uri: uri)
      } else {
        try await library.unlikeTrack(uri: uri)
      }
      let confirmed = try await library.isTrackLiked(uri: uri)
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = confirmed ? .liked : .notLiked
      }
    } catch SpotifyAPIError.httpStatus(403) {
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = .needsReconnect
      }
    } catch {
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = previous
      }
    }
  }
}
