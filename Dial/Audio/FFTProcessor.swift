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
    minFreq: Float = 60,
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

    var out = [Float](repeating: 0, count: bandCount)
    for i in 0..<bandCount {
      let freqLow = pow(10, logMin + Float(i) / Float(bandCount) * logRange)
      let freqHigh = pow(10, logMin + Float(i + 1) / Float(bandCount) * logRange)
      let binLow = max(0, Int(freqLow / binWidth))
      let binHigh = min(magnitudes.count, max(binLow + 1, Int(freqHigh / binWidth)))

      var sum: Float = 0
      for j in binLow..<binHigh {
        sum += magnitudes[j]
      }
      let avg = sum / Float(binHigh - binLow)

      // dB scale → 0..1, with `floorDb` as silence and 0dB as full scale.
      let db = 20 * log10(max(avg, 1e-6))
      let normalized = (db - floorDb) / -floorDb
      out[i] = max(0, min(1, normalized))
    }
    return out
  }
}
