// Dial/App/LaunchAtLogin.swift
import Foundation
import Observation
import ServiceManagement

/// What the "Launch at login" switch needs from `SMAppService`. Tests use a
/// fake so they never register the real login item.
protocol LoginItemService: AnyObject {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Backs the "Launch at login" switch in Settings with `SMAppService.mainApp`.
///
/// macOS owns the login item, so its status is the only source of truth:
/// nothing is stored in UserDefaults, and the switch reads the status again
/// whenever Settings comes back to the front (the user can also remove Dial
/// in System Settings › General › Login Items). Off by default: nothing
/// registers until the user turns the switch on.
@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: SMAppService.Status
  /// Why the last change failed, in words. Cleared by the next change.
  private(set) var problem: String?

  @ObservationIgnored private let service: LoginItemService

  init(service: LoginItemService = SMAppService.mainApp) {
    self.service = service
    self.status = service.status
  }

  var isOn: Bool { Self.isOn(status) }

  /// Registered, but macOS won't open Dial at login until the user allows it
  /// in Login Items.
  var needsApproval: Bool { status == .requiresApproval }

  func refresh() {
    status = service.status
  }

  func setOn(_ on: Bool) {
    problem = nil
    do {
      if on {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      problem = Self.problem(turningOn: on, error: error)
    }
    refresh()
  }

  /// `.requiresApproval` reads as on: the user asked for it and macOS kept
  /// the registration, it only waits for their OK. `.notFound` is what
  /// macOS reports for an app that was never registered.
  static func isOn(_ status: SMAppService.Status) -> Bool {
    switch status {
    case .enabled, .requiresApproval: true
    case .notRegistered, .notFound: false
    @unknown default: false
    }
  }

  static func problem(turningOn on: Bool, error: Error) -> String {
    let action = on ? "turn on" : "turn off"
    return "macOS couldn't \(action) launch at login: \(error.localizedDescription)"
  }
}
