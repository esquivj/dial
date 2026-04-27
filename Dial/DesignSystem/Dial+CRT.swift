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
  /// 0.10 (was 0.06) — at 6% the banding was below the threshold of
  /// "I see scanlines" for most viewers; the lit-screen affordance was
  /// doing none of the work it was supposed to. 10% shows up clearly
  /// over album art and dark fills without making text harder to read.
  var opacity: CGFloat = 0.10
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
  /// 0.65 (was 0.45) — under the brighter mint accents the prior depth
  /// read as a faint smudge rather than "pressed into a bezel."
  var depth: CGFloat = 0.65
  /// Vertical extent of the shadow gradient.
  /// 14pt (was 8pt) — gives the recess room to breathe; 8pt was
  /// invisible past the StatusRail bottom edge.
  var height: CGFloat = 14

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

/// LCD panel — slightly-lighter inset rectangle that sits inside the
/// device body and contains the actual content (track row, stats, badge,
/// spectrum). The mockup render's body is divided into three visual zones:
///
///   * Status zone (top): items float directly on the device body
///   * LCD zone (middle): an inset rectangle one shade lighter than the
///     body, suggesting "the lit screen part of the device"
///   * Transport zone (bottom): a separate inset rectangle for controls
///
/// Without this division everything reads as "stacked on a single dark
/// surface." With it the device gains the legibility of "device chrome
/// surrounding a screen" — which is the actual aesthetic move.
///
/// Implemented as: rounded surface fill + thin mint hairline + soft inner
/// top shadow (light falls into the recessed cavity).
struct LCDPanel: ViewModifier {
  /// Corner radius — smaller than the outer device body's (40pt) so the
  /// LCD reads as concentrically inset. 10pt is the sweet spot for a
  /// content-sized panel.
  var cornerRadius: CGFloat = 10
  /// Plasticky-translucent stroke opacity. 0.45 (was 0.22) — clearly
  /// reads as "translucent plastic edge" rather than "barely-there
  /// hairline." Same hue (white) as the outer device shell so all
  /// panel chrome shares one material language.
  var strokeOpacity: Double = 0.45

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Dial.Palette.surface)
      )
      // Clip content to the rounded shape — without this, child views
      // (HistoryView/StatsView headers, scroll rows, etc.) render past
      // the rounded corners into the device body's dark area, leaving
      // text and rows visible "outside" the LCD panel boundary.
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay(
        // Plasticky-translucent white stroke. Wider 0.8pt line (was 0.5)
        // gives the panel a visible "shell edge thickness" matching the
        // outer device body's plastic chrome treatment.
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
      )
      .overlay(
        // Top-arc gel sheen — brighter specular at the upper curve
        // where light catches. Reinforces the "lit plastic shell" feel.
        RoundedRectangle(cornerRadius: cornerRadius)
          .trim(from: 0.05, to: 0.45)
          .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
          .blur(radius: 0.4)
          .allowsHitTesting(false)
      )
      .overlay(
        // Inner top shadow — light catches the upper rim of the recess.
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(Color.black.opacity(0.45), lineWidth: 2.5)
          .blur(radius: 1.5)
          .offset(y: 1.5)
          .mask(RoundedRectangle(cornerRadius: cornerRadius))
          .allowsHitTesting(false)
      )
  }
}

extension View {
  /// Wrap content in an LCD panel — the slightly-lighter inset zone that
  /// distinguishes "screen content" from "device body chrome." See
  /// `LCDPanel` for the visual contract.
  func lcdPanel(cornerRadius: CGFloat = 10, strokeOpacity: Double = 0.18) -> some View {
    self.modifier(LCDPanel(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
  }

  /// Wrap content in a transport panel — same chrome system as `lcdPanel`
  /// but using a horizontal Capsule (fully rounded short edges) instead
  /// of a rounded rectangle. Matches the Digivice render's "playback
  /// button cradle" silhouette: distinct from the LCD panel above so
  /// the eye reads it as a separate functional zone (controls vs screen).
  func transportPanel(strokeOpacity: Double = 0.45) -> some View {
    self.modifier(TransportPanel(strokeOpacity: strokeOpacity))
  }
}

/// Custom shape for the transport panel — flat top with small rounded
/// corners, straight sides going partway down, and a curved bottom that
/// sweeps from one side to the other. Matches the Digivice render's
/// "scoop"/"shield-bottom" silhouette: distinct from a Capsule (which
/// has equal curvature top and bottom) and from a RoundedRectangle
/// (which has straight edges).
///
/// Geometry:
///   * Top corners: small radius (6pt)
///   * Top edge: flat
///   * Sides: straight vertical for 55% of the height
///   * Bottom: single quadratic bezier curve sweeping right-to-left,
///     peaking at the rect's bottom edge — gives the "more curved bottom"
///     reading without extending past the input rect bounds
struct TransportPanelShape: Shape {
  var topCornerRadius: CGFloat = 6
  /// What fraction of the height the straight sides cover before the
  /// bottom curve begins. 0.80 = sides go 80% down, curve takes 20%.
  /// Higher values give a SHALLOWER bottom curve (more straight sides).
  /// Earlier 0.55 was too aggressive — the bottom read as a deep scoop
  /// rather than a subtle curve.
  var sideHeightFraction: CGFloat = 0.80

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = topCornerRadius
    let sideEnd = rect.height * sideHeightFraction
    // Control point y for the bottom curve, derived so the curve's
    // midpoint sits exactly at rect.height (the bottom edge). Quadratic
    // bezier midpoint y = (start + control + end) / 4 simplifies to
    // (sideEnd + controlY) / 2 for symmetric endpoints; solving for
    // peak at rect.height gives controlY = 2*rect.height - sideEnd.
    let controlY = 2 * rect.height - sideEnd

    path.move(to: CGPoint(x: r, y: 0))
    path.addLine(to: CGPoint(x: rect.width - r, y: 0))
    path.addArc(
      center: CGPoint(x: rect.width - r, y: r),
      radius: r,
      startAngle: .degrees(-90),
      endAngle: .degrees(0),
      clockwise: false
    )
    path.addLine(to: CGPoint(x: rect.width, y: sideEnd))
    path.addQuadCurve(
      to: CGPoint(x: 0, y: sideEnd),
      control: CGPoint(x: rect.midX, y: controlY)
    )
    path.addLine(to: CGPoint(x: 0, y: r))
    path.addArc(
      center: CGPoint(x: r, y: r),
      radius: r,
      startAngle: .degrees(180),
      endAngle: .degrees(270),
      clockwise: false
    )
    path.closeSubpath()
    return path
  }
}

/// Transport panel — uses `TransportPanelShape` with the same chrome
/// composition as `LCDPanel`. The custom shape (flat top + curved bottom)
/// is what makes this container read as "special" against the rectangular
/// LCD panel above.
struct TransportPanel: ViewModifier {
  /// Plasticky white stroke opacity — matches LCDPanel's default so the
  /// two panels share visual language even though their shapes differ.
  var strokeOpacity: Double = 0.45

  func body(content: Content) -> some View {
    let shape = TransportPanelShape()

    return content
      .background(
        shape.fill(Dial.Palette.surface)
      )
      // Clip child content to the special transport shape so playback
      // buttons and shuffle/repeat icons don't render past the curved
      // bottom edge into the device body.
      .clipShape(shape)
      .overlay(
        // Plasticky-translucent white stroke — same hue and weight as
        // LCDPanel for chrome consistency.
        shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
      )
      .overlay(
        // Top-arc sheen — bright highlight along the flat top edge.
        // Trim values are tuned for this shape's path parametrization
        // (path starts at top-left, goes clockwise; the top edge +
        // top-right corner cover roughly the first ~20% of the path).
        shape
          .trim(from: 0.02, to: 0.22)
          .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
          .blur(radius: 0.4)
          .allowsHitTesting(false)
      )
      .overlay(
        // Inner top shadow — light catches the upper rim of the recess.
        shape
          .stroke(Color.black.opacity(0.45), lineWidth: 2.5)
          .blur(radius: 1.5)
          .offset(y: 1.5)
          .mask(shape)
          .allowsHitTesting(false)
      )
  }
}
