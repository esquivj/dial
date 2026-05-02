// DialTests/Audio/FFTProcessorTests.swift
import XCTest

@testable import Dial

final class FFTProcessorTests: XCTestCase {
  func test_magnitudes_outputSizeIsHalfFFTSize() {
    let fft = FFTProcessor(fftSize: 1024)
    let samples = [Float](repeating: 1, count: 1024)
    let mags = samples.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 1024) }
    XCTAssertTrue(fft.isAvailable)
    XCTAssertEqual(mags.count, 512, "FFT magnitude output should be fftSize/2")
  }

  func test_magnitudes_emptyOnInsufficientFrames() {
    let fft = FFTProcessor(fftSize: 1024)
    let samples = [Float](repeating: 1, count: 512)  // half what FFT needs
    let mags = samples.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 512) }
    XCTAssertTrue(mags.isEmpty, "FFT should refuse to process when given fewer than fftSize frames")
  }

  func test_bands_silenceProducesZeroBands() {
    let fft = FFTProcessor(fftSize: 1024)
    let silence = [Float](repeating: 0, count: 1024)
    let mags = silence.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 1024) }
    let bands = fft.bands(from: mags, count: 32)
    XCTAssertEqual(bands.count, 32)
    // With dB floor at -60, 1e-6 magnitude maps to -120dB → normalized = 0.
    // All bands should sit at the floor for true silence.
    XCTAssertTrue(bands.allSatisfy { $0 < 0.01 }, "silence should produce near-zero band heights, got \(bands)")
  }

  func test_bands_emptyMagnitudesProducesZeroBands() {
    let fft = FFTProcessor(fftSize: 1024)
    let bands = fft.bands(from: [], count: 32)
    XCTAssertEqual(bands.count, 32)
    XCTAssertTrue(bands.allSatisfy { $0 == 0 })
  }

  func test_unavailableSetupReturnsEmptyMagnitudesAndZeroBands() {
    let fft = FFTProcessor(fftSize: 1024, setupFactory: { _, _ in nil })
    let samples = [Float](repeating: 1, count: 1024)
    let mags = samples.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 1024) }
    let bands = fft.bands(from: mags, count: 32)
    XCTAssertFalse(fft.isAvailable)
    XCTAssertTrue(mags.isEmpty)
    XCTAssertEqual(bands.count, 32)
    XCTAssertTrue(bands.allSatisfy { $0 == 0 })
  }

  func test_bands_peakAtKnownFrequency() {
    // Generate a 1kHz sine at 48kHz sample rate, the canonical "hello FFT" test.
    // The bands are log-spaced from 100Hz to 16kHz across 32 bins; 1kHz lands
    // at log10(1000) = 3.0, position = (3.0 - log10(100)) / (log10(16000) - log10(100))
    //   = (3.0 - 2.0) / 2.204 = 0.454 → band index 14 (≈45% of the way through).
    // We allow ±1 band of tolerance for FFT bin-edge effects and Hann leakage.
    let fft = FFTProcessor(fftSize: 1024)
    let sampleRate: Float = 48_000
    let frequency: Float = 1_000
    var samples = [Float](repeating: 0, count: 1024)
    for i in 0..<1024 {
      let t = Float(i) / sampleRate
      samples[i] = sin(2 * .pi * frequency * t)
    }
    let mags = samples.withUnsafeBufferPointer {
      fft.magnitudes(of: $0.baseAddress!, frameCount: 1024)
    }
    let bands = fft.bands(from: mags, count: 32, sampleRate: sampleRate)
    let peak = bands.indices.max { bands[$0] < bands[$1] }!
    XCTAssertGreaterThanOrEqual(peak, 13, "1kHz sine peak should be near band 14, got \(peak); bands = \(bands)")
    XCTAssertLessThanOrEqual(peak, 15, "1kHz sine peak should be near band 14, got \(peak); bands = \(bands)")
  }

  func test_bands_normalizationStaysWithinZeroOne() {
    // Even a clipping-loud sine (amplitude 10× full scale) shouldn't push
    // any band above 1.0 — the dB-floor formula clamps at the top.
    let fft = FFTProcessor(fftSize: 1024)
    let sampleRate: Float = 48_000
    var samples = [Float](repeating: 0, count: 1024)
    for i in 0..<1024 {
      samples[i] = 10 * sin(2 * .pi * 440 * Float(i) / sampleRate)
    }
    let mags = samples.withUnsafeBufferPointer {
      fft.magnitudes(of: $0.baseAddress!, frameCount: 1024)
    }
    let bands = fft.bands(from: mags, count: 32, sampleRate: sampleRate)
    XCTAssertTrue(bands.allSatisfy { (0...1).contains($0) },
      "all bands must stay in [0,1] regardless of input amplitude, got \(bands)")
  }

  func test_bands_melPowerModeReturnsRequestedDensity() {
    let fft = FFTProcessor(fftSize: 2048, windowKind: .blackman)
    let sampleRate: Float = 48_000
    var samples = [Float](repeating: 0, count: 2048)
    for i in 0..<2048 {
      let t = Float(i) / sampleRate
      samples[i] =
        0.7 * sin(2 * .pi * 120 * t) +
        0.3 * sin(2 * .pi * 1_200 * t) +
        0.1 * sin(2 * .pi * 7_500 * t)
    }
    let mags = samples.withUnsafeBufferPointer {
      fft.magnitudes(of: $0.baseAddress!, frameCount: 2048)
    }
    let bands = fft.bands(
      from: mags,
      count: 64,
      sampleRate: sampleRate,
      scale: .mel,
      aggregation: .power,
      floorDb: -80,
      ceilingDb: -8)
    XCTAssertEqual(bands.count, 64)
    XCTAssertTrue(bands.allSatisfy { (0...1).contains($0) },
      "mel/power bands must stay normalized, got \(bands)")
    XCTAssertGreaterThan(bands.max() ?? 0, 0.1, "mixed sine input should light at least one mel band")
  }
}
