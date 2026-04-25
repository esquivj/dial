// Dial/DesignSystem/Dial+CRT.swift
import SwiftUI

/// LCD-style horizontal scanline texture. Sits on top of "screen" content
/// to suggest the surface is a lit panel rather than a flat layer of pixels.
///
/// At 6% opacity / 3pt pitch it averages ~2% darkening over the whole
/// surface — readable text remains readable, but album art and dark fills
/// pick up just enough banding to read as "this is on a screen."
///
/// Implemented as a Canvas overlay so it stays cheap regardless of the
/// underlying view tree's complexity.
struct LCDScanlines: View {
  var pitch: CGFloat = 3
  var opacity: CGFloat = 0.06
  var color: Color = .black

  var body: some View {
    Canvas { ctx, size in
      let line = color.opacity(opacity)
      var y: CGFloat = 0
      while y < size.height {
        ctx.fill(
          Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
          with: .color(line)
        )
        y += pitch
      }
    }
    .allowsHitTesting(false)
  }
}

/// Recessed-screen treatment: places a short dark gradient at the top of
/// the wrapped content so it reads as if the screen is pressed *into* a
/// surrounding bezel, with light falling from above. Sells the "this is
/// a device's LCD" mental model that the chrome-bevel border starts.
struct RecessedScreen: ViewModifier {
  /// Strength of the top inner shadow (alpha at the top edge).
  var depth: CGFloat = 0.45
  /// Vertical extent of the shadow gradient.
  var height: CGFloat = 8

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [
            Color.black.opacity(depth),
            Color.black.opacity(0),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
      }
  }
}
