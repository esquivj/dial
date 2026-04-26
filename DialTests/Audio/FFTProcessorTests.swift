// DialTests/Audio/FFTProcessorTests.swift
import XCTest

@testable import Dial

final class FFTProcessorTests: XCTestCase {
  func test_magnitudes_outputSizeIsHalfFFTSize() {
    let fft = FFTProcessor(fftSize: 1024)
    var samples = [Float](repeating: 1, count: 1024)
    let mags = samples.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 1024) }
    XCTAssertEqual(mags.count, 512, "FFT magnitude output should be fftSize/2")
  }

  func test_magnitudes_emptyOnInsufficientFrames() {
    let fft = FFTProcessor(fftSize: 1024)
    var samples = [Float](repeating: 1, count: 512)  // half what FFT needs
    let mags = samples.withUnsafeBufferPointer { fft.magnitudes(of: $0.baseAddress!, frameCount: 512) }
    XCTAssertTrue(mags.isEmpty, "FFT should refuse to process when given fewer than fftSize frames")
  }

  func test_bands_silenceProducesZeroBands() {
    let fft = FFTProcessor(fftSize: 1024)
    var silence = [Float](repeating: 0, count: 1024)
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

  func test_bands_peakAtKnownFrequency() {
    // Generate a 1kHz sine at 48kHz sample rate, the canonical "hello FFT" test.
    // The bands are log-spaced from 60Hz to 16kHz across 32 bins; 1kHz lands
    // at log10(1000) = 3.0, position = (3.0 - log10(60)) / (log10(16000) - log10(60))
    //   = (3.0 - 1.778) / 2.426 = 0.504 → band index 16 (50% of the way through).
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
    XCTAssertGreaterThanOrEqual(peak, 15, "1kHz sine peak should be near band 16, got \(peak); bands = \(bands)")
    XCTAssertLessThanOrEqual(peak, 17, "1kHz sine peak should be near band 16, got \(peak); bands = \(bands)")
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
}
