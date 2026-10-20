// Dial/Spotify/LocalSpotifySource.swift
import AppKit
import CoreServices
import Foundation
import os.log

private let localLog = Logger(subsystem: "com.dial.Dial", category: "LocalSpotifySource")

/// One read of the Spotify desktop app's player.
struct LocalPlaybackSnapshot: Equatable {
  struct Track: Equatable {
    let uri: String
    let name: String
    let artistName: String
    let albumName: String
    let artUrl: String?
    let durationMs: Int
  }

  /// nil when nothing is loaded, or the item isn't something the Web API
  /// reports as a track (ads, podcast episodes). Mirrors `/me/player`
  /// returning `item: null` for those, so counting stays identical.
  let track: Track?
  let isPlaying: Bool
  let progressMs: Int
}

enum LocalPlaybackReading: Equatable {
  /// The Spotify desktop app isn't running.
  case notRunning
  /// The user turned off Dial's Automation access to Spotify.
  case accessDenied
  /// The macOS permission prompt is up and hasn't been answered yet.
  case accessPending
  /// Spotify is running but didn't answer (busy, timed out, mid-launch).
  case unavailable
  /// Spotify answered. `track == nil, isPlaying == false` means stopped.
  case playback(LocalPlaybackSnapshot)
}

/// A source of now-playing state that doesn't touch the network.
protocol LocalPlaybackSource: AnyObject {
  func read() async -> LocalPlaybackReading
}

/// Reads the Spotify desktop app over Apple Events, the same interface
/// AppleScript uses (`player state`, `player position`, `current track`).
///
/// Events are addressed to Spotify's process id, never its bundle id, so a
/// read that races a quit fails with "process not found" instead of
/// relaunching Spotify. Every send happens on one serial queue with a short
/// timeout so a hung Spotify can't stall the poll loop for long.
final class SpotifyAppleEventsSource: LocalPlaybackSource, @unchecked Sendable {
  static let bundleIdentifier = "com.spotify.client"

  private enum Access { case unknown, pending, granted, denied }

  private let queue = DispatchQueue(label: "com.dial.Dial.spotify-apple-events", qos: .userInitiated)
  private let permissionQueue = DispatchQueue(label: "com.dial.Dial.spotify-apple-events-permission")
  private let replyTimeout: TimeInterval
  private let deniedRecheckInterval: TimeInterval

  // All state below is touched only on `queue`.
  private var access: Access = .unknown
  private var lastPermissionCheck: Date = .distantPast
  private var permissionRequestInFlight = false
  private var cachedTrackID: String?
  private var cachedTrack: LocalPlaybackSnapshot.Track?

  init(replyTimeout: TimeInterval = 1.5, deniedRecheckInterval: TimeInterval = 15) {
    self.replyTimeout = replyTimeout
    self.deniedRecheckInterval = deniedRecheckInterval
  }

  func read() async -> LocalPlaybackReading {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: self.readOnQueue())
      }
    }
  }

  private func readOnQueue() -> LocalPlaybackReading {
    guard let app = NSRunningApplication
      .runningApplications(withBundleIdentifier: Self.bundleIdentifier)
      .first(where: { !$0.isTerminated })
    else {
      cachedTrackID = nil
      cachedTrack = nil
      return .notRunning
    }

    if let blocked = checkAccess() { return blocked }

    let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
    do {
      let state = try getProperty(Code.playerState, of: .null(), target: target).enumCodeValue
      if state == Code.stopped {
        return .playback(.init(track: nil, isPlaying: false, progressMs: 0))
      }
      let isPlaying = state == Code.playing
      let positionSeconds = try getProperty(Code.playerPosition, of: .null(), target: target).doubleValue
      let track = try currentTrack(target: target)
      return .playback(.init(
        track: track,
        isPlaying: isPlaying,
        progressMs: max(0, Int((positionSeconds * 1_000).rounded()))))
    } catch let error as AppleEventError {
      return reading(for: error)
    } catch {
      return .unavailable
    }
  }

  /// Returns nil when reads may proceed, or the reading to report instead.
  private func checkAccess() -> LocalPlaybackReading? {
    switch access {
    case .granted:
      return nil
    case .pending:
      return .accessPending
    case .denied:
      guard Date().timeIntervalSince(lastPermissionCheck) >= deniedRecheckInterval else {
        return .accessDenied
      }
    case .unknown:
      break
    }

    // Re-check without prompting. This also picks up a change the user made
    // in System Settings while Dial was running.
    lastPermissionCheck = Date()
    switch Self.permissionStatus(askUserIfNeeded: false) {
    case noErr:
      access = .granted
      return nil
    case OSStatus(errAEEventWouldRequireUserConsent):
      requestPermission()
      return .accessPending
    case OSStatus(errAEEventNotPermitted):
      if access != .denied {
        localLog.notice("Automation access to Spotify is off; using the Web API")
      }
      access = .denied
      return .accessDenied
    case OSStatus(procNotFound):
      return .notRunning
    default:
      return .unavailable
    }
  }

  /// Shows the macOS "Dial wants to control Spotify" prompt once. The call
  /// blocks until the user answers, so it runs on its own queue and the poll
  /// loop keeps using the Web API meanwhile.
  private func requestPermission() {
    guard !permissionRequestInFlight else { return }
    permissionRequestInFlight = true
    access = .pending
    permissionQueue.async { [weak self] in
      let status = Self.permissionStatus(askUserIfNeeded: true)
      self?.queue.async {
        guard let self else { return }
        self.permissionRequestInFlight = false
        self.lastPermissionCheck = Date()
        switch status {
        case noErr:
          self.access = .granted
        case OSStatus(errAEEventNotPermitted):
          self.access = .denied
        default:
          // Spotify quit mid-prompt or the request failed; ask again later.
          self.access = .unknown
        }
        localLog.notice("Automation permission answered: \(status, privacy: .public)")
      }
    }
  }

  /// Asks macOS whether Dial may send Apple Events to Spotify. With
  /// `askUserIfNeeded: false` it never prompts, which is how Settings reads
  /// the permission (`PermissionStatus(automation:)`).
  static func permissionStatus(askUserIfNeeded: Bool) -> OSStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
    guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
    return AEDeterminePermissionToAutomateTarget(
      desc, typeWildCard, typeWildCard, askUserIfNeeded)
  }

  private func currentTrack(target: NSAppleEventDescriptor) throws -> LocalPlaybackSnapshot.Track? {
    let trackSpecifier = Self.propertySpecifier(Code.currentTrack, of: .null())
    let id: String
    do {
      id = try getProperty(Code.id, of: trackSpecifier, target: target).stringValue ?? ""
    } catch AppleEventError.status(let status) where status == Code.noSuchObject {
      return nil
    }
    guard let uri = Self.countableTrackURI(id) else {
      cachedTrackID = id
      cachedTrack = nil
      return nil
    }
    if id == cachedTrackID, let cachedTrack { return cachedTrack }

    // Metadata only changes with the track, so these five events are sent
    // once per track instead of on every read.
    func text(_ code: FourCharCode) -> String {
      (try? getProperty(code, of: trackSpecifier, target: target).stringValue) ?? ""
    }
    let durationRaw = (try? getProperty(Code.duration, of: trackSpecifier, target: target))
      .map { Double($0.int32Value) } ?? 0
    let artwork = text(Code.artworkURL)
    let track = LocalPlaybackSnapshot.Track(
      uri: uri,
      name: text(Code.name),
      artistName: text(Code.artist),
      albumName: text(Code.album),
      artUrl: artwork.isEmpty ? nil : artwork,
      durationMs: Self.durationMilliseconds(durationRaw))
    cachedTrackID = id
    cachedTrack = track
    return track
  }

  private func reading(for error: AppleEventError) -> LocalPlaybackReading {
    switch error {
    case .status(let status):
      switch status {
      case OSStatus(errAEEventNotPermitted):
        access = .denied
        lastPermissionCheck = Date()
        return .accessDenied
      case OSStatus(procNotFound), OSStatus(connectionInvalid):
        cachedTrackID = nil
        cachedTrack = nil
        return .notRunning
      default:
        localLog.debug("Spotify read failed: \(status, privacy: .public)")
        return .unavailable
      }
    }
  }

  // MARK: - Apple Events

  private enum AppleEventError: Error { case status(OSStatus) }

  private func getProperty(
    _ code: FourCharCode,
    of container: NSAppleEventDescriptor,
    target: NSAppleEventDescriptor
  ) throws -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kAECoreSuite),
      eventID: AEEventID(kAEGetData),
      targetDescriptor: target,
      returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(Self.propertySpecifier(code, of: container), forKeyword: keyDirectObject)
    let reply: NSAppleEventDescriptor
    do {
      reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: replyTimeout)
    } catch let error as NSError {
      throw AppleEventError.status(OSStatus(truncatingIfNeeded: error.code))
    }
    if let errorNumber = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value,
       errorNumber != 0 {
      throw AppleEventError.status(errorNumber)
    }
    guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else {
      throw AppleEventError.status(Code.noSuchObject)
    }
    return result
  }

  /// `property <code> of <container>`, the object specifier AppleScript
  /// builds for `get player state`. Internal so tests can check its shape.
  static func propertySpecifier(
    _ code: FourCharCode,
    of container: NSAppleEventDescriptor
  ) -> NSAppleEventDescriptor {
    let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: DescType(typeObjectSpecifier))
      ?? NSAppleEventDescriptor.record()
    spec.setDescriptor(NSAppleEventDescriptor(typeCode: DescType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
    spec.setDescriptor(NSAppleEventDescriptor(enumCode: DescType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
    spec.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
    spec.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
    return spec
  }

  /// Four-char codes from Spotify.app/Contents/Resources/Spotify.sdef.
  private enum Code {
    static let playerState = fourCC("pPlS")
    static let playerPosition = fourCC("pPos")
    static let currentTrack = fourCC("pTrk")
    static let playing = fourCC("kPSP")
    static let stopped = fourCC("kPSS")
    static let id = fourCC("ID  ")
    static let name = fourCC("pnam")
    static let artist = fourCC("pArt")
    static let album = fourCC("pAlb")
    static let duration = fourCC("pDur")
    static let artworkURL = fourCC("aUrl")
    static let noSuchObject = OSStatus(errAENoSuchObject)
  }

  // MARK: - Mapping (static so tests can cover it without Spotify)

  /// Keeps only what `/me/player` reports as an item by default: catalog
  /// tracks and local files. Ads and podcast episodes come back as nil,
  /// exactly like the Web API's `item: null`.
  static func countableTrackURI(_ id: String) -> String? {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("spotify:track:") || trimmed.hasPrefix("spotify:local:") {
      return trimmed
    }
    return nil
  }

  /// The sdef says seconds, but Spotify has returned milliseconds for years.
  /// No track is under 10 seconds long in ms, or over ~2.7 hours in seconds.
  static func durationMilliseconds(_ raw: Double) -> Int {
    guard raw > 0 else { return 0 }
    return raw >= 10_000 ? Int(raw.rounded()) : Int((raw * 1_000).rounded())
  }
}

private func fourCC(_ string: String) -> FourCharCode {
  string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
}
