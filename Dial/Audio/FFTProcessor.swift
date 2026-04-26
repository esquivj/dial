// Dial/Audio/FFTProcessor.swift
import Accelerate
import Foundation

/// Real-input FFT wrapper around vDSP, plus log-spaced frequency binning.
///
/// We're not building a spectrum analyser — we're driving a 32-band visualizer
/// where each band has to "feel" representative of a frequency range you can
/// hear. That means two things:
///   1. Hann window the input so transient leakage doesn't smear the bins.
///   2. Bin linearly-spaced FFT output into log-spaced bands, because the ear
///      hears frequency logarithmically. Linear bins would make the top half
///      of the visualizer almost always dead — there's just not much music
///      energy above 4kHz.
final class FFTProcessor {
  let fftSize: Int
  private let log2N: vDSP_Length
  private let setup: FFTSetup
  private let window: [Float]

  init(fftSize: Int = 1024) {
    self.fftSize = fftSize
    self.log2N = vDSP_Length(Int(log2(Float(fftSize))))
    guard let s = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
      fatalError("Failed to create vDSP FFT setup for size \(fftSize)")
    }
    self.setup = s

    var w = [Float](repeating: 0, count: fftSize)
    vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    self.window = w
  }

  deinit {
    vDSP_destroy_fftsetup(setup)
  }

  /// Returns the magnitude spectrum (size `fftSize/2`) for the given samples.
  /// Caller must supply at least `fftSize` frames.
  func magnitudes(of samples: UnsafePointer<Float>, frameCount: Int) -> [Float] {
    guard frameCount >= fftSize else { return [] }
    let halfSize = fftSize / 2

    // 1. Apply Hann window.
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
    // 100Hz floor (was 60Hz) — kick-drum fundamentals and sub-bass rumble
    // dominated the leftmost bands and made the bottom of the grid feel
    // permanently maxed out. 100Hz cuts the rumble and spreads the 32
    // bands across more useful musical territory (bass guitar second
    // harmonics → cymbals).
    minFreq: Float = 100,
    maxFreq: Float = 16_000,
    floorDb: Float = -60
  ) -> [Float] {
    guard !magnitudes.isEmpty else {
      return [Float](repeating: 0, count: bandCount)
    }
    let nyquist = sampleRate / 2
    let binWidth = nyquist / Float(magnitudes.count)
    let logMin = log10(minFreq)
    let logMax = log10(maxFreq)
    let logRange = logMax - logMin

    // Normalization factor for vDSP_fft_zrip output → amplitude-correct dBFS:
    //
    //   * vDSP's forward FFT does no 1/N scaling; raw magnitudes scale with N/2,
    //     so a unit sine through a rectangular window comes out at magnitude N/2.
    //   * The Hann window has coherent gain 0.5 — every sample is multiplied by
    //     a value averaging 0.5 — so windowed magnitudes are halved again. The
    //     standard amplitude-correction factor for Hann is 2.
    //
    // Combined: `magnitude * 2 / (N/2)` recovers the original amplitude, where
    // `magnitudes.count == N/2`. After this, 0 dBFS = full-scale sine wave.
    //
    // Without this normalization, raw magnitudes for typical music sit around
    // +30 to +50 dB into the formula below, which pegs every band to 1.0 —
    // the "all bars at full height, identical across columns" symptom.
    let ampCorrection: Float = 2.0 / Float(magnitudes.count)

    var out = [Float](repeating: 0, count: bandCount)
    for i in 0..<bandCount {
      let freqLow = pow(10, logMin + Float(i) / Float(bandCount) * logRange)
      let freqHigh = pow(10, logMin + Float(i + 1) / Float(bandCount) * logRange)
      let binLow = max(0, Int(freqLow / binWidth))
      let binHigh = min(magnitudes.count, max(binLow + 1, Int(freqHigh / binWidth)))

      // MAX (was AVERAGE). The grid's bands are log-spaced over linear FFT
      // bins, so the top-end bands cover many more bins than the bottom-end
      // ones (band 31 ≈ 51 bins, band 0 ≈ 1 bin). Real music in the high
      // bands is mostly silence with sharp peaks (cymbal sheen, sibilance);
      // averaging 50 quiet neighbors against 1 hot bin drowned the peaks
      // by ~30dB. MAX captures the loudest bin in the band — for the
      // narrow lower bands max == avg, so the fix only lifts the highs.
      var peak: Float = 0
      for j in binLow..<binHigh {
        if magnitudes[j] > peak { peak = magnitudes[j] }
      }
      let amp = peak * ampCorrection

      // dB scale → 0..1, with `floorDb` as silence and 0dB as full scale.
      let db = 20 * log10(max(amp, 1e-6))
      let normalized = (db - floorDb) / -floorDb
      out[i] = max(0, min(1, normalized))
    }
    return out
  }
}
