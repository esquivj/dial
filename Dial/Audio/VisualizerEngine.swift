// Dial/Audio/VisualizerEngine.swift
import AppKit
import CoreGraphics
import Foundation
import Observation

/// Orchestrates capture → FFT → smoothed band heights for the SwiftUI grid.
///
/// State model:
///   - `.idle` until the first `start()` call resolves
///   - `.running` once the capture is live
///   - `.denied` if Screen Recording permission isn't granted (or revoked)
///   - `.error` for everything else (no display, format issues)
///
/// Lifecycle: long-lived. The engine starts on first dropdown appearance and
/// keeps the SCStream running for the app's lifetime — closing/reopening the
/// dropdown is *not* a stop/start cycle. Two reasons:
///
///   1. **Permission stability.** macOS TCC for Screen Recording is fussy
///      under ad-hoc signing (every Xcode rebuild = new signature = TCC
///      sees a "different app"). The fewer times we ask `SCShareableContent`
///      for content, the fewer chances for a flaky re-prompt.
///   2. **Cost.** SCStream at 2×2 video / 1fps + 48kHz audio is ~1–2% CPU
///      on Apple Silicon. Far cheaper than the start/stop churn it replaces.
///
/// Threading:
///   - `start` / `stop` are `@MainActor` so state mutations are serialized
///   - the audio queue invokes `handleSamples` (nonisolated) which runs FFT
///     inline (~50µs for size 1024) and then hops to MainActor to mutate
///     `bands` / `peaks`
///   - SwiftUI reads `bands` / `peaks` on the main actor; `@Observable` wires
///     up the redraws automatically
@Observable
final class VisualizerEngine: @unchecked Sendable {
  enum State { case idle, running, denied, error }

  /// Number of frequency bands the FFT is binned into. The grid is intended
  /// to render exactly this many columns.
  static let bandCount = 32

  /// Smoothed band heights, 0…1. Updated on the main actor.
  private(set) var bands: [Float] = Array(repeating: 0, count: bandCount)
  /// Peak-hold dots per band, 0…1. Decay slowly so loud transients trail.
  private(set) var peaks: [Float] = Array(repeating: 0, count: bandCount)
  /// Public state for the view layer to render permission/error overlays.
  private(set) var state: State = .idle

  private let capture = AudioCaptureEngine()
  private let fft = FFTProcessor(fftSize: 1024)

  /// Sliding sample buffer: SCStream delivers chunks of variable size, but
  /// the FFT wants a fixed-size window. We accumulate, then on each delivery
  /// run FFT over the most recent `fftSize` samples.
  private let lock = NSLock()
  private var sampleBuffer: [Float] = []

  /// Visibility throttle: views call `attach()`/`detach()` to register/
  /// unregister themselves as consumers. While zero consumers are attached,
  /// `handleSamples` short-circuits — the SCStream stays alive (so we don't
  /// re-prompt for permission) but the FFT, MainActor dispatch, and SwiftUI
  /// updates all skip. Saves ~5ms/sec of CPU plus main-thread wakeups while
  /// the popover sits closed (which is most of the time).
  private let visibilityLock = NSLock()
  private var _consumers = 0

  // Smoothing constants. Tuned so:
  //   - bars rise fast (attack 0.4) → transients feel snappy
  //   - bars fall slow (release 0.12) → no flicker on percussive material
  //   - peaks decay very slowly (0.008/tick ≈ 0.7/sec at typical buffer rate)
  //     → loud hits leave a satisfying drift back down
  private let attack: Float = 0.4
  private let release: Float = 0.12
  private let peakDecay: Float = 0.008

  /// Observer for app activation — used to auto-retry start() after the user
  /// grants permission via System Settings (which deactivates Dial, then
  /// reactivates it on return).
  private var activationObserver: NSObjectProtocol?

  init() {
    capture.onSamples = { [weak self] samples in
      self?.handleSamples(samples)
    }

    // Auto-retry start when the app becomes active again. Common path: user
    // saw the .denied overlay, tapped → System Settings opened → granted →
    // came back. This kicks the state back to .idle so the next start()
    // (either via this notification or via .task on dropdown open) will try
    // SCShareableContent again with the now-valid permission.
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.state == .denied {
          self.state = .idle
          await self.start()
        }
      }
    }
  }

  deinit {
    if let obs = activationObserver {
      NotificationCenter.default.removeObserver(obs)
    }
  }

  // MARK: - Lifecycle

  @MainActor
  func start() async {
    // Idempotent — calling start() while already running is a no-op. This is
    // what makes long-lived capture safe under SwiftUI's `.task` modifier,
    // which fires on every view appearance.
    guard state != .running else { return }

    // Peek at TCC without prompting. If permission isn't already granted,
    // surface .denied immediately and skip the SCShareableContent call —
    // calling it under denied state can cause flaky prompt behavior under
    // ad-hoc signing.
    guard CGPreflightScreenCaptureAccess() else {
      state = .denied
      return
    }

    do {
      try await capture.start()
      state = .running
    } catch {
      // ScreenCaptureKit reports permission denial as a generic error from
      // SCShareableContent. Map any failure to either `.denied` (most common
      // first-launch case) or `.error`. Either way the UI shows a fallback.
      let nsErr = error as NSError
      if nsErr.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
        || nsErr.domain == "com.apple.TCC"
        || nsErr.code == -3801
      {
        state = .denied
      } else {
        state = .error
      }
    }
  }

  @MainActor
  func stop() async {
    // Idempotent — only do work if we're actually running. Note: with the
    // long-lived lifecycle, the production code path doesn't call stop()
    // anymore; it's kept for tests and for future surfaces (e.g. an
    // explicit "pause visualizer" toggle in settings).
    guard state == .running else { return }
    await capture.stop()
    state = .idle
    bands = Array(repeating: 0, count: Self.bandCount)
    peaks = Array(repeating: 0, count: Self.bandCount)
  }

  // MARK: - Visibility throttle

  /// View calls this on `.onAppear`. Increments the consumer count;
  /// FFT processing resumes if it had been paused.
  func attach() {
    visibilityLock.lock()
    _consumers += 1
    visibilityLock.unlock()
  }

  /// View calls this on `.onDisappear`. Decrements the consumer count;
  /// FFT processing pauses when count reaches zero. The capture stream
  /// stays alive (pausing/restarting it would re-trigger permission
  /// prompt risk under ad-hoc signing).
  func detach() {
    visibilityLock.lock()
    _consumers = max(0, _consumers - 1)
    let stillVisible = _consumers > 0
    visibilityLock.unlock()

    if !stillVisible {
      // Reset to zero so when a view next attaches, the visualizer starts
      // from a clean state instead of stale residual values from the last
      // visible session.
      Task { @MainActor in
        self.bands = Array(repeating: 0, count: Self.bandCount)
        self.peaks = Array(repeating: 0, count: Self.bandCount)
      }
    }
  }

  /// Lock-protected read of consumer count for the audio thread's gate.
  private func hasVisibleConsumer() -> Bool {
    visibilityLock.lock()
    defer { visibilityLock.unlock() }
    return _consumers > 0
  }

  // MARK: - Audio thread

  nonisolated private func handleSamples(_ samples: [Float]) {
    // Skip everything when no view is observing. Done before the buffer
    // lock so we don't even allocate the snapshot array.
    guard hasVisibleConsumer() else { return }

    let snapshot: [Float]?
    lock.lock()
    sampleBuffer.append(contentsOf: samples)
    // Cap sliding buffer at a few FFT-windows worth so memory stays bounded
    // even if the consumer falls behind.
    let cap = fft.fftSize * 4
    if sampleBuffer.count > cap {
      sampleBuffer.removeFirst(sampleBuffer.count - cap)
    }
    if sampleBuffer.count >= fft.fftSize {
      snapshot = Array(sampleBuffer.suffix(fft.fftSize))
    } else {
      snapshot = nil
    }
    lock.unlock()
    guard let s = snapshot else { return }

    let mags = s.withUnsafeBufferPointer { buf in
      fft.magnitudes(of: buf.baseAddress!, frameCount: buf.count)
    }
    guard !mags.isEmpty else { return }
    let raw = fft.bands(from: mags, count: Self.bandCount)

    Task { @MainActor [weak self, raw] in
      self?.applyBands(raw)
    }
  }

  // MARK: - Main thread

  @MainActor
  private func applyBands(_ raw: [Float]) {
    for i in 0..<Self.bandCount {
      let prev = bands[i]
      let next = raw[i]
      let alpha: Float = next > prev ? attack : release
      let smoothed = prev + (next - prev) * alpha
      bands[i] = smoothed

      if smoothed > peaks[i] {
        peaks[i] = smoothed
      } else {
        peaks[i] = max(0, peaks[i] - peakDecay)
      }
    }
  }
}
