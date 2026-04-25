// Dial/Audio/VisualizerEngine.swift
import Foundation
import Observation

/// Orchestrates capture → FFT → smoothed band heights for the SwiftUI grid.
///
/// State model:
///   - `state == .idle` until the first `start()` call resolves
///   - `.running` once the capture is live
///   - `.denied` if Screen Recording permission isn't granted (or revoked)
///   - `.error` for everything else (no display, format issues)
///
/// Threading:
///   - `start` / `stop` are actor-free (callable from anywhere)
///   - the audio queue invokes `handleSamples`, which runs FFT inline (~50µs
///     for size 1024 on Apple Silicon — well within the audio queue's budget)
///     and then hops to MainActor to mutate `bands` / `peaks`
///   - SwiftUI reads `bands` / `peaks` on the main actor; @Observable wires up
///     the redraws automatically
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

  // Smoothing constants. Tuned so:
  //   - bars rise fast (attack 0.4) → transients feel snappy
  //   - bars fall slow (release 0.12) → no flicker on percussive material
  //   - peaks decay very slowly (0.008/tick ≈ 0.7/sec at typical buffer rate)
  //     → loud hits leave a satisfying drift back down
  private let attack: Float = 0.4
  private let release: Float = 0.12
  private let peakDecay: Float = 0.008

  init() {
    capture.onSamples = { [weak self] samples in
      self?.handleSamples(samples)
    }
  }

  // MARK: - Lifecycle

  func start() async {
    do {
      try await capture.start()
      await MainActor.run { self.state = .running }
    } catch {
      // ScreenCaptureKit reports permission denial as a generic error from
      // SCShareableContent. Map any failure to either `.denied` (most common
      // first-launch case) or `.error`. Either way the UI shows a fallback.
      await MainActor.run {
        let nsErr = error as NSError
        // -3801 / TCC denial-style codes → .denied
        if nsErr.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
          || nsErr.domain == "com.apple.TCC"
          || nsErr.code == -3801
        {
          self.state = .denied
        } else {
          self.state = .error
        }
      }
    }
  }

  func stop() async {
    await capture.stop()
    await MainActor.run {
      self.state = .idle
      self.bands = Array(repeating: 0, count: Self.bandCount)
      self.peaks = Array(repeating: 0, count: Self.bandCount)
    }
  }

  // MARK: - Audio thread

  private func handleSamples(_ samples: [Float]) {
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
