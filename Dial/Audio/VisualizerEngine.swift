// Dial/Audio/VisualizerEngine.swift
import AppKit
import CoreGraphics
import Foundation
import Observation
import os.log

private let visualizerLog = Logger(subsystem: "com.dial.Dial", category: "VisualizerEngine")

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
///     inline and then hops to MainActor to mutate
///     `bands` / `peaks`
///   - SwiftUI reads `bands` / `peaks` on the main actor; `@Observable` wires
///     up the redraws automatically
///   - publishes are capped at 15fps so the HUD feels live without turning
///     the menu bar popover into a tiny space heater
@Observable
final class VisualizerEngine: @unchecked Sendable {
  enum State { case idle, running, denied, error }

  /// Smoothed band heights, 0…1. Updated on the main actor.
  private(set) var bands: [Float] = Array(repeating: 0, count: SpectrumDensity.detailed.bandCount)
  /// Peak-hold dots per band, 0…1. Decay slowly so loud transients trail.
  private(set) var peaks: [Float] = Array(repeating: 0, count: SpectrumDensity.detailed.bandCount)
  /// Number of frequency bands the grid should render.
  private(set) var bandCount: Int = SpectrumDensity.detailed.bandCount
  /// Whether the brightest held peak cell should render above each band.
  private(set) var showPeakMarkers = true
  /// Public state for the view layer to render permission/error overlays.
  private(set) var state: State = .idle

  @ObservationIgnored private let capture = AudioCaptureEngine()
  @ObservationIgnored private var fft = FFTProcessor(fftSize: 2048, windowKind: .blackman)
  @ObservationIgnored private var analysisBandCount = SpectrumDensity.detailed.bandCount
  @ObservationIgnored private var bandScale: FFTProcessor.BandScale = .mel
  @ObservationIgnored private var bandAggregation: FFTProcessor.BandAggregation = .power
  @ObservationIgnored private var floorDb: Float = -80
  @ObservationIgnored private var ceilingDb: Float = -8

  /// Sliding sample buffer: SCStream delivers chunks of variable size, but
  /// the FFT wants a fixed-size window. We accumulate, then on each delivery
  /// run FFT over the most recent `fftSize` samples.
  @ObservationIgnored private let lock = NSLock()
  @ObservationIgnored private var sampleBuffer: [Float] = []
  @ObservationIgnored private var lastPublishNanos: UInt64 = 0
  @ObservationIgnored private let publishIntervalNanos: UInt64 = 1_000_000_000 / 15

  /// Visibility throttle: views call `attach()`/`detach()` to register/
  /// unregister themselves as consumers. While zero consumers are attached,
  /// `handleSamples` short-circuits — the SCStream stays alive (so we don't
  /// re-prompt for permission) but the FFT, MainActor dispatch, and SwiftUI
  /// updates all skip. Saves ~5ms/sec of CPU plus main-thread wakeups while
  /// the popover sits closed (which is most of the time).
  @ObservationIgnored private let visibilityLock = NSLock()
  @ObservationIgnored private var _consumers = 0

  // Smoothing constants. Tuned so:
  //   - bars rise fast (attack 0.4) → transients feel snappy
  //   - bars fall slow (release 0.12) → no flicker on percussive material
  //   - peaks decay very slowly (0.008/tick ≈ 0.7/sec at typical buffer rate)
  //     → loud hits leave a satisfying drift back down
  @ObservationIgnored private var attack: Float = 0.42
  @ObservationIgnored private var release: Float = 0.13
  @ObservationIgnored private var peakDecay: Float = 0.010

  /// Observer for app activation — used to auto-retry start() after the user
  /// grants permission via System Settings (which deactivates Dial, then
  /// reactivates it on return).
  @ObservationIgnored private var activationObserver: NSObjectProtocol?

  init() {
    capture.shouldProcessSamples = { [weak self] in
      self?.hasVisibleConsumer() ?? false
    }

    capture.onSamples = { [weak self] samples in
      self?.handleSamples(samples)
    }

    // System-initiated stop (most commonly: user revoked Screen Recording
    // permission while we were running). Flip state so the UI surfaces
    // the overlay instead of rendering frozen bars over a dead stream.
    // CGPreflightScreenCaptureAccess() distinguishes "user pulled the rug"
    // (.denied) from any other system-initiated stop (.error).
    capture.onStop = { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.state = CGPreflightScreenCaptureAccess() ? .error : .denied
        self.resetBands()
      }
    }

    // Auto-retry start when the app becomes active again. Common path: user
    // saw the .denied or .error overlay, tapped → System Settings opened →
    // granted → came back. We retry from any non-running state (idle/denied/
    // error) since SCShareableContent is now the source of truth — if the
    // permission really is granted now, start() will succeed; if not, it'll
    // re-set to .denied and we're no worse off.
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.state != .running {
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
  func configure(
    style: SpectrumStyle,
    density: SpectrumDensity,
    motion: SpectrumMotion,
    showPeakMarkers: Bool
  ) {
    let profile = analysisProfile(for: style)

    let configuredFFT: FFTProcessor
    lock.lock()
    if fft.fftSize != profile.fftSize || fft.windowKind != profile.windowKind {
      fft = FFTProcessor(fftSize: profile.fftSize, windowKind: profile.windowKind)
      sampleBuffer.removeAll(keepingCapacity: true)
      lastPublishNanos = 0
    }
    configuredFFT = fft
    analysisBandCount = density.bandCount
    bandScale = profile.bandScale
    bandAggregation = profile.bandAggregation
    floorDb = profile.floorDb
    ceilingDb = profile.ceilingDb
    lock.unlock()

    let motionProfile = motionProfile(for: motion)
    attack = motionProfile.attack
    release = motionProfile.release
    peakDecay = motionProfile.peakDecay

    if bands.count != density.bandCount {
      bands = Array(repeating: 0, count: density.bandCount)
      peaks = Array(repeating: 0, count: density.bandCount)
    }
    bandCount = density.bandCount
    self.showPeakMarkers = showPeakMarkers

    if !configuredFFT.isAvailable {
      markFFTUnavailable(configuredFFT)
    }
  }

  #if DEBUG
  /// Test/export hook for deterministic marketing renders. The live app still
  /// gets all spectrum values from ScreenCaptureKit; this just lets the asset
  /// exporter render the real visualizer component without starting capture.
  @MainActor
  func setPreviewSpectrum(bands previewBands: [Float], peaks previewPeaks: [Float]? = nil) {
    let count = max(1, previewBands.count)
    bands = previewBands.map { min(1, max(0, $0)) }
    peaks = (previewPeaks ?? previewBands).map { min(1, max(0, $0)) }
    if peaks.count != count {
      peaks = bands
    }
    bandCount = count
    state = .running
  }
  #endif

  @MainActor
  func start() async {
    // Idempotent — calling start() while already running is a no-op. This is
    // what makes long-lived capture safe under SwiftUI's `.task` modifier,
    // which fires on every view appearance.
    guard state != .running else { return }

    // No preflight gate. SCShareableContent itself is the source of truth
    // for permission — if it succeeds, we're authed.
    //
    // We previously used CGPreflightScreenCaptureAccess() here to short-
    // circuit when TCC reported "not granted" (rationale: avoid potential
    // re-prompt flakiness on every start). But under ad-hoc signing — which
    // is what Xcode produces and we ship to /Applications via cp -R every
    // rebuild — TCC tracks grants by code signature. When the binary's
    // signature changes (every rebuild), TCC's cached entry no longer
    // matches and the preflight returns false-negative even though the
    // user clearly granted permission and System Settings shows it as on.
    // Result: visualizer would surface the "ENABLE VISUALIZER" overlay
    // forever despite the permission being authentic.
    //
    // Letting SCShareableContent decide is cleaner: it succeeds when the
    // permission is actually usable and throws otherwise. The activation-
    // observer auto-retry below still handles the post-grant return path.

    let currentFFT = fft
    guard currentFFT.isAvailable else {
      markFFTUnavailable(currentFFT)
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
      visualizerLog.error("start failed: domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code) \(nsErr.localizedDescription, privacy: .public)")
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
    resetBands()
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
        self.resetBands()
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
    let localFFT: FFTProcessor
    let localBandCount: Int
    let localBandScale: FFTProcessor.BandScale
    let localBandAggregation: FFTProcessor.BandAggregation
    let localFloorDb: Float
    let localCeilingDb: Float
    let now = DispatchTime.now().uptimeNanoseconds
    lock.lock()
    localFFT = fft
    guard localFFT.isAvailable else {
      sampleBuffer.removeAll(keepingCapacity: true)
      lastPublishNanos = 0
      lock.unlock()
      return
    }
    localBandCount = analysisBandCount
    localBandScale = bandScale
    localBandAggregation = bandAggregation
    localFloorDb = floorDb
    localCeilingDb = ceilingDb
    sampleBuffer.append(contentsOf: samples)
    // Cap sliding buffer at a few FFT-windows worth so memory stays bounded
    // even if the consumer falls behind.
    let cap = localFFT.fftSize * 4
    if sampleBuffer.count > cap {
      sampleBuffer.removeFirst(sampleBuffer.count - cap)
    }
    let shouldPublish = lastPublishNanos == 0 || now - lastPublishNanos >= publishIntervalNanos
    if shouldPublish, sampleBuffer.count >= localFFT.fftSize {
      lastPublishNanos = now
      snapshot = Array(sampleBuffer.suffix(localFFT.fftSize))
    } else {
      snapshot = nil
    }
    lock.unlock()
    guard let s = snapshot else { return }

    let perf = DialPerf.begin("visualizer.frame_work")
    defer { perf.end() }

    let mags = s.withUnsafeBufferPointer { buf in
      guard let baseAddress = buf.baseAddress else { return [Float]() }
      return localFFT.magnitudes(of: baseAddress, frameCount: buf.count)
    }
    guard !mags.isEmpty else { return }
    let raw = localFFT.bands(
      from: mags,
      count: localBandCount,
      scale: localBandScale,
      aggregation: localBandAggregation,
      floorDb: localFloorDb,
      ceilingDb: localCeilingDb)

    Task { @MainActor [weak self, raw] in
      self?.applyBands(raw)
    }
  }

  // MARK: - Main thread

  @MainActor
  private func applyBands(_ raw: [Float]) {
    guard raw.count == bands.count else { return }
    var nextBands = bands
    var nextPeaks = peaks

    for i in raw.indices {
      let prev = nextBands[i]
      let next = raw[i]
      let alpha: Float = next > prev ? attack : release
      let smoothed = prev + (next - prev) * alpha
      nextBands[i] = smoothed

      if smoothed > nextPeaks[i] {
        nextPeaks[i] = smoothed
      } else {
        nextPeaks[i] = max(0, nextPeaks[i] - peakDecay)
      }
    }

    bands = nextBands
    peaks = nextPeaks
  }

  @MainActor
  private func resetBands() {
    bands = Array(repeating: 0, count: bandCount)
    peaks = Array(repeating: 0, count: bandCount)
  }

  @MainActor
  private func markFFTUnavailable(_ fft: FFTProcessor) {
    visualizerLog.error("FFT setup unavailable for size \(fft.fftSize, privacy: .public)")
    if state != .denied {
      state = .error
    }
    resetBands()
  }

  private func analysisProfile(for style: SpectrumStyle) -> (
    fftSize: Int,
    windowKind: FFTProcessor.WindowKind,
    bandScale: FFTProcessor.BandScale,
    bandAggregation: FFTProcessor.BandAggregation,
    floorDb: Float,
    ceilingDb: Float
  ) {
    switch style {
    case .precise:
      return (
        fftSize: 2048,
        windowKind: .blackman,
        bandScale: .mel,
        bandAggregation: .power,
        floorDb: -80,
        ceilingDb: -8
      )
    case .punchy:
      return (
        fftSize: 1024,
        windowKind: .hann,
        bandScale: .log,
        bandAggregation: .peak,
        floorDb: -60,
        ceilingDb: -6
      )
    }
  }

  private func motionProfile(for motion: SpectrumMotion) -> (
    attack: Float,
    release: Float,
    peakDecay: Float
  ) {
    switch motion {
    case .fast:
      return (attack: 0.62, release: 0.22, peakDecay: 0.018)
    case .balanced:
      return (attack: 0.42, release: 0.13, peakDecay: 0.010)
    case .smooth:
      return (attack: 0.28, release: 0.07, peakDecay: 0.005)
    }
  }
}
