// Dial/Audio/FFTProcessor.swift
import Accelerate
import Foundation

/// Real-input FFT wrapper around vDSP, plus log-spaced frequency binning.
///
/// We're not building a spectrum analyser — we're driving a compact visualizer
/// where each band has to "feel" representative of a frequency range you can
/// hear. That means two things:
///   1. Window the input so transient leakage doesn't smear the bins.
///   2. Bin linearly-spaced FFT output into perceptual bands, because linear
///      bins would make the top half of the visualizer almost always dead.
final class FFTProcessor {
  enum WindowKind {
    case hann
    case blackman
  }

  enum BandScale {
    case log
    case mel
  }

  enum BandAggregation {
    case peak
    case power
  }

  let fftSize: Int
  let windowKind: WindowKind
  private let log2N: vDSP_Length
  private let setup: FFTSetup
  private let window: [Float]
  private let coherentGain: Float

  init(fftSize: Int = 1024, windowKind: WindowKind = .hann) {
    precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "FFT size must be a positive power of two")
    self.fftSize = fftSize
    self.windowKind = windowKind
    self.log2N = vDSP_Length(Int(log2(Float(fftSize))))
    guard let s = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
      fatalError("Failed to create vDSP FFT setup for size \(fftSize)")
    }
    self.setup = s

    let w = Self.window(kind: windowKind, count: fftSize)
    self.window = w
    self.coherentGain = max(0.0001, w.reduce(0, +) / Float(fftSize))
  }

  deinit {
    vDSP_destroy_fftsetup(setup)
  }

  /// Returns the magnitude spectrum (size `fftSize/2`) for the given samples.
  /// Caller must supply at least `fftSize` frames.
  func magnitudes(of samples: UnsafePointer<Float>, frameCount: Int) -> [Float] {
    guard frameCount >= fftSize else { return [] }
    let halfSize = fftSize / 2

    // 1. Apply the configured analysis window.
    var windowed = [Float](repeating: 0, count: fftSize)
    vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

    // 2. Pack the real signal into split-complex form, run forward FFT,
    //    take squared magnitudes, then sqrt for actual magnitudes.
    var realp = [Float](repeating: 0, count: halfSize)
    var imagp = [Float](repeating: 0, count: halfSize)
    var squaredMags = [Float](repeating: 0, count: halfSize)

    realp.withUnsafeMutableBufferPointer { rPtr in
      imagp.withUnsafeMutableBufferPointer { iPtr in
        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
        windowed.withUnsafeBufferPointer { wPtr in
          wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
          }
        }
        vDSP_fft_zrip(setup, &split, 1, log2N, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &squaredMags, 1, vDSP_Length(halfSize))
      }
    }

    var mags = [Float](repeating: 0, count: halfSize)
    var n = Int32(halfSize)
    vvsqrtf(&mags, squaredMags, &n)
    return mags
  }

  /// Compresses a linear-frequency magnitude array into `bandCount` log-spaced
  /// bands and normalizes each to roughly 0…1 via dB scaling.
  ///
  /// `minFreq`/`maxFreq` clamp out subsonic rumble (below 60Hz is mostly DC
  /// noise from the capture path) and the very top of the audible range
  /// (above ~16kHz there's rarely useful musical content).
  func bands(
    from magnitudes: [Float],
    count bandCount: Int,
    sampleRate: Float = 48_000,
    scale: BandScale = .log,
    aggregation: BandAggregation = .peak,
    minFreq: Float = 100,
    maxFreq: Float = 16_000,
    floorDb: Float = -60,
    ceilingDb: Float = 0
  ) -> [Float] {
    guard !magnitudes.isEmpty else {
      return [Float](repeating: 0, count: bandCount)
    }
    let nyquist = sampleRate / 2
    let binWidth = nyquist / Float(magnitudes.count)
    let edges = frequencyEdges(count: bandCount, minFreq: minFreq, maxFreq: maxFreq, scale: scale)

    // Normalization factor for vDSP_fft_zrip output → amplitude-correct dBFS:
    //
    //   * vDSP's forward FFT does no 1/N scaling; raw magnitudes scale with N/2,
    //     so a unit sine through a rectangular window comes out at magnitude N/2.
    //   * Window functions reduce coherent amplitude; divide by measured
    //     coherent gain so Hann and Blackman land on the same dB scale.
    //
    // Without this normalization, raw magnitudes for typical music sit around
    // +30 to +50 dB into the formula below, which pegs every band to 1.0 —
    // the "all bars at full height, identical across columns" symptom.
    let ampCorrection: Float = 1.0 / (Float(magnitudes.count) * coherentGain)
    let dbSpan = max(1, ceilingDb - floorDb)

    var out = [Float](repeating: 0, count: bandCount)
    for i in 0..<bandCount {
      let amp = bandAmplitude(
        magnitudes: magnitudes,
        bandIndex: i,
        edges: edges,
        binWidth: binWidth,
        aggregation: aggregation
      ) * ampCorrection

      // dB scale → 0..1, with configurable floor/ceiling like Web Audio's
      // minDecibels/maxDecibels analyzer controls.
      let db = 20 * log10(max(amp, 1e-6))
      let normalized = (db - floorDb) / dbSpan
      out[i] = max(0, min(1, normalized))
    }
    return out
  }

  private static func window(kind: WindowKind, count: Int) -> [Float] {
    var result = [Float](repeating: 0, count: count)
    switch kind {
    case .hann:
      vDSP_hann_window(&result, vDSP_Length(count), Int32(vDSP_HANN_NORM))
    case .blackman:
      for n in 0..<count {
        let phase = 2 * Double.pi * Double(n) / Double(count)
        result[n] = Float(0.42 - 0.5 * cos(phase) + 0.08 * cos(2 * phase))
      }
    }
    return result
  }

  private func frequencyEdges(
    count bandCount: Int,
    minFreq: Float,
    maxFreq: Float,
    scale: BandScale
  ) -> [Float] {
    let edgeCount = bandCount + (scale == .mel ? 2 : 1)
    return (0..<edgeCount).map { index in
      let t = Float(index) / Float(edgeCount - 1)
      switch scale {
      case .log:
        let logMin = log10(minFreq)
        let logRange = log10(maxFreq) - logMin
        return pow(10, logMin + t * logRange)
      case .mel:
        let melMin = hertzToMel(minFreq)
        let melRange = hertzToMel(maxFreq) - melMin
        return melToHertz(melMin + t * melRange)
      }
    }
  }

  private func bandAmplitude(
    magnitudes: [Float],
    bandIndex: Int,
    edges: [Float],
    binWidth: Float,
    aggregation: BandAggregation
  ) -> Float {
    switch aggregation {
    case .peak:
      let freqLow = edges[bandIndex]
      let freqHigh = edges[bandIndex + 1]
      let binLow = max(0, Int(freqLow / binWidth))
      let binHigh = min(magnitudes.count, max(binLow + 1, Int(freqHigh / binWidth)))
      var peak: Float = 0
      for j in binLow..<binHigh {
        if magnitudes[j] > peak { peak = magnitudes[j] }
      }
      return peak

    case .power:
      let left = edges[bandIndex]
      let center = edges[bandIndex + 1]
      let right = edges[bandIndex + 2]
      let binLow = max(0, Int(left / binWidth))
      let binHigh = min(magnitudes.count, max(binLow + 1, Int(ceil(right / binWidth))))
      var weightedPower: Float = 0
      var weightSum: Float = 0

      for j in binLow..<binHigh {
        let freq = Float(j) * binWidth
        let weight: Float
        if freq <= center {
          weight = (freq - left) / max(1, center - left)
        } else {
          weight = (right - freq) / max(1, right - center)
        }
        let clamped = max(0, min(1, weight))
        weightedPower += magnitudes[j] * magnitudes[j] * clamped
        weightSum += clamped
      }

      if weightSum <= 0 { return 0 }
      return sqrt(weightedPower / weightSum)
    }
  }

  private func hertzToMel(_ hz: Float) -> Float {
    2595 * log10(1 + hz / 700)
  }

  private func melToHertz(_ mel: Float) -> Float {
    700 * (pow(10, mel / 2595) - 1)
  }
}
