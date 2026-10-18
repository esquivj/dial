// Dial/ViewModels/HotkeyActionRouter.swift
import Foundation

/// Turns a global hotkey press into the same command the HUD sends, plus a
/// confirmation flash. Play, pause and skip go through `TransportCommands`
/// (the transport row's code); like goes through `LikedTrackController`
/// (the heart button's code).
@MainActor
final class HotkeyActionRouter {
  static let volumeStep = 5
  /// How long a volume we set stays trusted before we ask Spotify again
  /// (the user may have moved Spotify's own slider since).
  static let volumeFreshness: TimeInterval = 5

  private let menubar: MenubarStripViewModel
  private let transport: PlaybackTransport
  private let liked: LikedTrackController
  private let openHUD: () -> Void
  private let flash: (HotkeyFlashContent) -> Void
  private let now: () -> Date

  private var volumeTarget: Int?
  private var volumeTargetAt: Date?
  private var queuedVolumeSteps: [Bool] = []
  private var queuedVolume: Int?
  private(set) var volumeFetch: Task<Void, Never>?
  private(set) var volumeSend: Task<Void, Never>?

  init(
    menubar: MenubarStripViewModel,
    transport: PlaybackTransport,
    library: LikedLibrary,
    onReconnect: @escaping () async throws -> Void = {},
    openHUD: @escaping () -> Void,
    flash: @escaping (HotkeyFlashContent) -> Void,
    now: @escaping () -> Date = Date.init
  ) {
    self.menubar = menubar
    self.transport = transport
    self.liked = LikedTrackController(menubar: menubar, library: library, onReconnect: onReconnect)
    self.openHUD = openHUD
    self.flash = flash
    self.now = now
  }

  func perform(_ action: HotkeyAction) {
    let commands = TransportCommands(menubar: menubar, transport: transport)
    let flash = flash
    let failed: () -> Void = { flash(.noPlayer) }
    switch action {
    case .playPause:
      let playing = commands.togglePlayPause(onFailure: failed)
      flash(playing ? .play : .pause)
    case .next:
      flash(.next)
      commands.next(onFailure: failed)
    case .previous:
      flash(.previous)
      commands.previous(onFailure: failed)
    case .like:
      switch liked.toggle(allowReconnect: false) {
      case .liked:          flash(.liked)
      case .unliked:        flash(.unliked)
      case .needsReconnect: flash(.reconnect)
      case .unavailable:    flash(.noTrack)
      }
    case .volumeUp:
      adjustVolume(up: true)
    case .volumeDown:
      adjustVolume(up: false)
    case .openHUD:
      openHUD()
    }
  }

  /// Next 5% mark in the pressed direction: 47 → 50 up, 47 → 45 down.
  static func steppedVolume(from current: Int, up: Bool) -> Int {
    let step = volumeStep
    let clamped = max(0, min(100, current))
    if up {
      return min(100, (clamped / step + 1) * step)
    }
    return max(0, ((clamped + step - 1) / step - 1) * step)
  }

  /// Waits for any volume read or write in flight. Tests use it.
  func settle() async {
    await volumeFetch?.value
    await volumeSend?.value
  }

  // MARK: - Volume

  private func adjustVolume(up: Bool) {
    if let target = volumeTarget, let at = volumeTargetAt,
       now().timeIntervalSince(at) < Self.volumeFreshness {
      commitVolume(Self.steppedVolume(from: target, up: up))
      return
    }
    // Presses that land while we're still reading the volume are applied
    // in order once the read comes back.
    queuedVolumeSteps.append(up)
    guard volumeFetch == nil else { return }
    let transport = transport
    volumeFetch = Task { [weak self] in
      let current = try? await transport.volumePercent()
      guard let self else { return }
      self.volumeFetch = nil
      let steps = self.queuedVolumeSteps
      self.queuedVolumeSteps = []
      guard let start = current else {
        self.flash(.noPlayer)
        return
      }
      self.commitVolume(steps.reduce(start) { Self.steppedVolume(from: $0, up: $1) })
    }
  }

  private func commitVolume(_ value: Int) {
    volumeTarget = value
    volumeTargetAt = now()
    flash(.volume(value))
    send(volume: value)
  }

  /// One write at a time; while one is out, only the newest value waits.
  private func send(volume value: Int) {
    if volumeSend != nil {
      queuedVolume = value
      return
    }
    let transport = transport
    volumeSend = Task { [weak self] in
      var next: Int? = value
      while let volume = next {
        do {
          try await transport.setVolume(percent: volume)
        } catch {
          self?.volumeTarget = nil
          self?.queuedVolume = nil
          self?.flash(.noPlayer)
          break
        }
        next = self?.queuedVolume
        self?.queuedVolume = nil
      }
      self?.volumeSend = nil
    }
  }
}
