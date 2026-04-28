// Dial/DesignSystem/DustTexture.swift
import SwiftUI

/// Static stippled-dust overlay matching mockup section 6 BACKGROUND
/// TEXTURE — a quiet single-population scatter of small dots. The earlier
/// three-layer version (gray dust + ivory speckles + mint twinkles) was
/// improvising past the spec; the spec is straightforward dust.
///
/// Density and opacity tuned so the pattern is just-visible on the dark
/// `ground` and effectively invisible over `surface` cards (so it doesn't
/// fight foreground content). Deterministic LCG so the pattern is stable
/// across renders and dropdown re-opens.
struct DustTexture: View {
  /// Dots per square point. 0.0025 ≈ ~300 dots over a 320×380 popover —
  /// enough to register as material noise, sparse enough to never read
  /// as a pattern.
  var density: Double = 0.0025
  /// Dot color — muted gray reads on dark ground without standing out
  /// over inset card fills.
  var color: Color = Dial.Palette.textMuted
  /// Per-dot alpha range; each dot is randomized within these bounds.
  var alphaRange: ClosedRange<Double> = 0.10...0.20
  /// Seed for the LCG. Default keeps every instance identical.
  var seed: UInt32 = 0xD1A1

  var body: some View {
    Canvas { ctx, size in
      var rng = LCG(seed: seed)
      let count = Int(size.width * size.height * density)
      for _ in 0..<count {
        let x = Double(size.width) * rng.unit()
        let y = Double(size.height) * rng.unit()
        let radius = 0.5 + rng.unit() * 0.7       // 0.5–1.2pt dots
        let alpha = alphaRange.lowerBound
                  + rng.unit() * (alphaRange.upperBound - alphaRange.lowerBound)
        ctx.fill(
          Path(ellipseIn: CGRect(
            x: x - radius / 2, y: y - radius / 2,
            width: radius, height: radius)),
          with: .color(color.opacity(alpha))
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// Linear congruential generator — Numerical Recipes constants. Cheap,
/// deterministic, plenty random for visual stippling. Not for crypto.
private struct LCG {
  private var state: UInt32
  init(seed: UInt32) { self.state = seed == 0 ? 0xDEAD_BEEF : seed }
  mutating func next() -> UInt32 {
    state = state &* 1_664_525 &+ 1_013_904_223
    return state
  }
  mutating func unit() -> Double {
    Double(next()) / Double(UInt32.max)
  }
}
