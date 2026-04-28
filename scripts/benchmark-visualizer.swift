import Foundation

struct VisualizerBenchmarkCase {
  let name: String
  let fftSize: Int
  let windowKind: FFTProcessor.WindowKind
  let bandScale: FFTProcessor.BandScale
  let bandAggregation: FFTProcessor.BandAggregation
  let bandCount: Int
  let floorDb: Float
  let ceilingDb: Float
}

@main
enum VisualizerBenchmark {
  static func main() {
    let cases = [
      VisualizerBenchmarkCase(
        name: "Punchy 32",
        fftSize: 1024,
        windowKind: .hann,
        bandScale: .log,
        bandAggregation: .peak,
        bandCount: 32,
        floorDb: -60,
        ceilingDb: -6),
      VisualizerBenchmarkCase(
        name: "Precise 48",
        fftSize: 2048,
        windowKind: .blackman,
        bandScale: .mel,
        bandAggregation: .power,
        bandCount: 48,
        floorDb: -80,
        ceilingDb: -8),
      VisualizerBenchmarkCase(
        name: "Precise 64",
        fftSize: 2048,
        windowKind: .blackman,
        bandScale: .mel,
        bandAggregation: .power,
        bandCount: 64,
        floorDb: -80,
        ceilingDb: -8),
    ]

    let iterations = 3_000
    let budgetMs = 1_000.0 / 15.0

    for benchCase in cases {
      let fft = FFTProcessor(fftSize: benchCase.fftSize, windowKind: benchCase.windowKind)
      let samples = makeSamples(count: benchCase.fftSize)

      // Warm up vDSP setup/cache paths before measuring.
      for _ in 0..<100 {
        _ = runOneFrame(fft: fft, samples: samples, benchCase: benchCase)
      }

      var checksum: Float = 0
      let start = DispatchTime.now().uptimeNanoseconds
      for _ in 0..<iterations {
        checksum += runOneFrame(fft: fft, samples: samples, benchCase: benchCase)
      }
      let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
      let averageMs = elapsedMs / Double(iterations)
      let budgetPercent = averageMs / budgetMs * 100
      print("\(benchCase.name): \(format(averageMs)) ms/frame (\(format(budgetPercent))% of 15fps budget, checksum \(format(Double(checksum))))")
    }
  }

  @inline(never)
  private static func runOneFrame(
    fft: FFTProcessor,
    samples: [Float],
    benchCase: VisualizerBenchmarkCase
  ) -> Float {
    let mags = samples.withUnsafeBufferPointer {
      fft.magnitudes(of: $0.baseAddress!, frameCount: samples.count)
    }
    let bands = fft.bands(
      from: mags,
      count: benchCase.bandCount,
      scale: benchCase.bandScale,
      aggregation: benchCase.bandAggregation,
      floorDb: benchCase.floorDb,
      ceilingDb: benchCase.ceilingDb)
    return bands.reduce(0, +)
  }

  private static func makeSamples(count: Int) -> [Float] {
    let sampleRate: Float = 48_000
    return (0..<count).map { index in
      let t = Float(index) / sampleRate
      return
        0.55 * sin(2 * .pi * 57 * t) +
        0.35 * sin(2 * .pi * 480 * t) +
        0.22 * sin(2 * .pi * 2_400 * t) +
        0.08 * sin(2 * .pi * 9_500 * t)
    }
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.3f", value)
  }
}
