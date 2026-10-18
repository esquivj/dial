// Dial/App/HotkeyController.swift
import Foundation
import Observation

/// Keeps the global shortcuts registered to match Settings, and hands each
/// press to `HotkeyActionRouter`. Owned by `StatusBarController`, which
/// supplies "open the HUD" and "show a flash".
@MainActor
final class HotkeyController {
  private let settings: HotkeySettings
  private let center: HotkeyRegistering
  private let router: HotkeyActionRouter

  init(
    settings: HotkeySettings,
    router: HotkeyActionRouter,
    center: HotkeyRegistering = CarbonHotkeyCenter()
  ) {
    self.settings = settings
    self.router = router
    self.center = center
    center.onPress = { [weak self] action in
      Task { @MainActor in self?.router.perform(action) }
    }
    observeSettings()
  }

  private func observeSettings() {
    withObservationTracking {
      _ = settings.enabled
      _ = settings.isRecording
      _ = settings.activeBindings
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSettings() }
    }
    apply()
  }

  private func apply() {
    guard settings.enabled, !settings.isRecording else {
      center.unregisterAll()
      return
    }
    let refused = center.register(settings.activeBindings)
    if settings.unavailable != refused {
      settings.unavailable = refused
    }
  }
}
