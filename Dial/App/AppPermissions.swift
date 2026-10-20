// Dial/App/AppPermissions.swift
import CoreGraphics
import CoreServices
import Foundation

/// The macOS privacy permissions Dial needs, as Settings lists them.
enum DialPermission {
  /// Apple Events control of the Spotify app (Privacy & Security ›
  /// Automation), so Dial can read playback from the app instead of the
  /// Web API.
  case spotifyAutomation
  /// Screen & System Audio Recording, which ScreenCaptureKit requires before
  /// it hands over system audio for the spectrum.
  case screenRecording

  /// The Privacy & Security pane in System Settings that lists Dial.
  var settingsURL: URL {
    switch self {
    case .spotifyAutomation:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    case .screenRecording:
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    }
  }
}

/// Where a permission stands, in the words Settings shows.
enum PermissionStatus: Equatable {
  case allowed
  case notAllowed
  case notAsked
  /// macOS can't say right now: the Automation check needs Spotify running.
  case unknown

  var label: String {
    switch self {
    case .allowed:    "Allowed"
    case .notAllowed: "Not allowed"
    case .notAsked:   "Not asked yet"
    case .unknown:    "Unknown"
    }
  }

  /// `DialIcon` name. The shape and the label carry the state, so it never
  /// depends on color alone.
  var icon: String {
    switch self {
    case .allowed:            "checkmark.circle"
    case .notAllowed:         "xmark.circle"
    case .notAsked, .unknown: "questionmark.circle"
    }
  }
}

extension PermissionStatus {
  /// Maps `AEDeterminePermissionToAutomateTarget`'s answer for Spotify.
  /// macOS answers only while Spotify runs; anything else, mostly
  /// `procNotFound`, is unknown.
  init(automation status: OSStatus) {
    switch status {
    case noErr:
      self = .allowed
    case OSStatus(errAEEventNotPermitted):
      self = .notAllowed
    case OSStatus(errAEEventWouldRequireUserConsent):
      self = .notAsked
    default:
      self = .unknown
    }
  }

  /// `CGPreflightScreenCaptureAccess` can't tell "never asked" from "turned
  /// off", so Dial remembers whether it ever started a capture, which is
  /// when macOS asks. A running spectrum counts as allowed whatever the
  /// preflight says, so this row never contradicts the audio meter.
  init(screenRecordingAllowed allowed: Bool, captureRequested: Bool, visualizer: VisualizerEngine.State) {
    if allowed || visualizer == .running {
      self = .allowed
    } else if captureRequested || visualizer == .denied {
      self = .notAllowed
    } else {
      self = .notAsked
    }
  }
}

/// Screen Recording state that can be read without showing a prompt.
enum ScreenRecordingAccess {
  static let requestedKey = "permissions.screenRecordingRequested"

  /// True when macOS allows Dial to record. Never prompts.
  static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

  /// Called right before Dial asks ScreenCaptureKit for content, which is
  /// when macOS shows its prompt the first time.
  static func noteRequested(in defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: requestedKey)
  }

  static func wasRequested(in defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: requestedKey)
  }
}
