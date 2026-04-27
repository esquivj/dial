// Dial/DesignSystem/DialGel.swift
import SwiftUI

/// Gel/convex treatment for any rounded container — turns a flat
/// `.fill().stroke()` rectangle into a "lit 3D object" with the
/// top-arc sheen + convex-curvature gradient that matches the mockup
/// render's container chrome.
///
/// Originally only the transport buttons (`GelTransportStyle`) had this
/// treatment. Then album art / stat cards / pet block were flat
/// rectangles, which read as "panels with strokes" against the buttons'
/// glass-object feel — visual inconsistency that flattened the whole
/// device. This modifier applies the same chrome system to every
/// container shape.
///
/// Composition stack (bottom → top):
///   1. Base surface fill (the "body" of the container)
///   2. Convex linear gradient — subtle mint at top, fade through clear,
///      hint of black at bottom. Sells the "light falling on a curve"
///      illusion without committing to a real 3D render.
///   3. Top-arc gel sheen — half-trim of the perimeter, blurred white
///      stroke. The single highest-leverage detail; without it the
///      shape reads as cardboard.
///   4. Outer mint stroke (the "lit edge" of the container)
///   5. Outer mint glow (the "device material catching the lit edge")
///
/// All layers respect the same `cornerRadius`, so the chrome stays
/// concentric whether the parent renders a 6pt album frame or a 16pt
/// device body.
struct GelContainer: ViewModifier {
  var cornerRadius: CGFloat
  /// Stroke color — translucent white by default ("plasticky shell"),
  /// `.amber` for explicitly lit/branded edges (pet bezel, album frame),
  /// `.orange` for celebration tones.
  var strokeColor: Color = .white
  /// Halo color — defaults to `.amber` (mint) so the surrounding glow
  /// stays in the brand palette even when the stroke is plasticky white.
  /// Pass a matching color to keep stroke and halo in lockstep, or pass
  /// `.clear` (and set `haloOpacity: 0`) to remove the halo entirely.
  var haloColor: Color = Dial.Palette.amber
  /// 0.50 reads as "lit edge of clear plastic" against the dark body.
  var strokeOpacity: Double = 0.50
  /// Top-arc sheen brightness. **The single highest-leverage value
  /// for making this read as gel.** 0.45 reads as wet glass; below
  /// 0.30 the highlight is too subtle to register against the dark.
  var sheenOpacity: Double = 0.45
  /// Sheen line width. 1.2 reads as a clear specular bright; 0.5
  /// reads as a faint reflection.
  var sheenLineWidth: CGFloat = 1.2
  /// Outer halo (the lit material ring around the container).
  var haloOpacity: Double = 0.30
  var haloRadius: CGFloat = 9
  /// Top of the convex gradient — mint glow suggesting light catching
  /// the upper curve. 0.20 sells the curvature illusion; lower values
  /// read as flat.
  var convexTopOpacity: Double = 0.20
  /// Bottom of the convex gradient — black falling away from the light.
  /// Equal-ish to top opacity for symmetric convex shape.
  var convexBottomOpacity: Double = 0.22
  /// Inner top shadow — makes the container read as "pressed into the
  /// body" rather than sitting on top of it. Combined with the top-arc
  /// sheen it gives the depth illusion: bright sheen ON TOP of dark
  /// inner recess = "lit lip + recessed cavity" = gel.
  var innerShadowOpacity: Double = 0.45
  var innerShadowOffset: CGFloat = 1.5
  /// Base fill color — `surface` for inset cards, `subtle` for deeper
  /// recesses, custom (e.g. `lcd`) for the pet bezel.
  var baseFill: Color = Dial.Palette.surface

  func body(content: Content) -> some View {
    content
      .background(
        ZStack {
          // 1 — base body
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(baseFill)

          // 2 — convex gradient. Top mint glow → clear → bottom shadow.
          // Two clear stops in the middle keep the highlight tight to
          // the top edge instead of bleeding into the body.
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(
              colors: [
                Dial.Palette.amber.opacity(convexTopOpacity),
                Color.clear,
                Color.clear,
                Color.black.opacity(convexBottomOpacity),
              ],
              startPoint: .top, endPoint: .bottom))

          // 3 — INNER TOP SHADOW. Reads as "the container's lip casts
          // a shadow into its own cavity." This is what flips the
          // overall reading from "raised plate" to "recessed gel."
          // Implemented as a stroke with vertical offset, then masked
          // to the container shape so it only shows inside.
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.black.opacity(innerShadowOpacity), lineWidth: 3)
            .blur(radius: 2)
            .offset(y: innerShadowOffset)
            .mask(RoundedRectangle(cornerRadius: cornerRadius))

          // 4 — top-arc gel sheen. Half-trim of the perimeter so the
          // highlight only catches the upper half of the curve. The
          // line width is the second highest-leverage value here —
          // 1.2pt reads as a clear specular bright.
          RoundedRectangle(cornerRadius: cornerRadius)
            .trim(from: 0.05, to: 0.45)
            .stroke(Color.white.opacity(sheenOpacity), lineWidth: sheenLineWidth)
            .blur(radius: 0.6)
        }
      )
      .overlay(
        // 5 — edge stroke (plasticky white by default, or branded color
        // when explicitly passed in)
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(strokeColor.opacity(strokeOpacity), lineWidth: 1)
      )
      // 6 — outer halo. Uses `haloColor` (default mint) so cards get a
      // plasticky white edge with a mint glow around them — the edge
      // catches "ambient light" while the halo reads as "device emits
      // brand-color light." Decoupling these lets us tune them independently.
      .shadow(
        color: haloColor.opacity(haloOpacity),
        radius: haloRadius, x: 0, y: 0)
  }
}

extension View {
  /// Apply the gel/convex container chrome. See `GelContainer` for the
  /// composition details. Defaults are tuned for the standard inset card
  /// case (`surface` fill, mint stroke, soft halo) — override for
  /// special-case containers like the pet bezel (`baseFill: .lcd`,
  /// stronger stroke and halo).
  func gelContainer(
    cornerRadius: CGFloat,
    strokeColor: Color = .white,
    haloColor: Color = Dial.Palette.amber,
    strokeOpacity: Double = 0.50,
    sheenOpacity: Double = 0.55,
    sheenLineWidth: CGFloat = 1.0,
    haloOpacity: Double = 0.20,
    haloRadius: CGFloat = 8,
    convexTopOpacity: Double = 0.18,
    convexBottomOpacity: Double = 0.22,
    innerShadowOpacity: Double = 0.45,
    innerShadowOffset: CGFloat = 1.5,
    baseFill: Color = Dial.Palette.surface
  ) -> some View {
    self.modifier(GelContainer(
      cornerRadius: cornerRadius,
      strokeColor: strokeColor,
      haloColor: haloColor,
      strokeOpacity: strokeOpacity,
      sheenOpacity: sheenOpacity,
      sheenLineWidth: sheenLineWidth,
      haloOpacity: haloOpacity,
      haloRadius: haloRadius,
      convexTopOpacity: convexTopOpacity,
      convexBottomOpacity: convexBottomOpacity,
      innerShadowOpacity: innerShadowOpacity,
      innerShadowOffset: innerShadowOffset,
      baseFill: baseFill))
  }
}
