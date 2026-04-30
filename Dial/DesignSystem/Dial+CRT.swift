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
/// spectrum). The body is divided into three visual zones:
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
/// Implemented through the shared recessed-panel material so the LCD and
/// transport cradle use one lighting model.
struct LCDPanel: ViewModifier {
  /// Corner radius — smaller than the outer device body's so the
  /// LCD reads as concentrically inset.
  var cornerRadius: CGFloat = Dial.Radius.panel
  var fill: Color?
  var strokeOpacity: Double = DialMaterial.Recessed.strokeOpacity
  @Environment(\.dialTheme) private var theme

  func body(content: Content) -> some View {
    content
      .dialRecessedPanel(
        shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
        fill: fill ?? theme.subtle,
        strokeOpacity: strokeOpacity)
  }
}

extension View {
  /// Wrap content in an LCD panel — the slightly-lighter inset zone that
  /// distinguishes "screen content" from "device body chrome." See
  /// `LCDPanel` for the visual contract.
  func lcdPanel(
    cornerRadius: CGFloat = Dial.Radius.panel,
    fill: Color? = nil,
    strokeOpacity: Double = DialMaterial.Recessed.strokeOpacity
  ) -> some View {
    self.modifier(LCDPanel(cornerRadius: cornerRadius, fill: fill, strokeOpacity: strokeOpacity))
  }

  /// Wrap content in a transport panel — same chrome system as `lcdPanel`
  /// but using the special flat-top / curved-bottom panel silhouette
  /// instead of a rounded rectangle. Matches the Digivice render's
  /// "playback button cradle" shape: distinct from the LCD panel above
  /// so the eye reads it as a separate functional zone.
  func transportPanel(strokeOpacity: Double = DialMaterial.Transport.strokeOpacity) -> some View {
    self.modifier(TransportPanel(strokeOpacity: strokeOpacity))
  }
}

/// Custom shape for the transport panel: flat hardware top, tight upper
/// corners, and a straight lower ledge. The generated shell already owns
/// the outer toy curvature; the live controls need to read as a stable
/// inserted tray, not another curved shell piece.
///
/// Geometry:
///   * Top corners: tiny radius, closer to stamped plastic than app chrome
///   * Top edge: flat
///   * Sides: straight
///   * Bottom: flat ledge with small corner fillets
struct TransportPanelShape: Shape {
  var topCornerRadius: CGFloat = Dial.Radius.transportTop
  var bottomJoinRadius: CGFloat = Dial.Radius.transportFoot

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let topR = min(max(0, topCornerRadius), rect.width / 2, rect.height / 2)
    let bottomR = min(max(0, bottomJoinRadius), rect.width / 5, rect.height / 3)

    path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + topR),
      control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomR))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - bottomR, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + bottomR, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - bottomR),
      control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + topR, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

/// Transport panel — uses `TransportPanelShape` with the same recessed
/// material as `LCDPanel`. The custom shape is what makes this container
/// read as the dedicated playback cradle.
struct TransportPanel: ViewModifier {
  var strokeOpacity: Double = DialMaterial.Transport.strokeOpacity
  @Environment(\.dialTheme) private var theme

  func body(content: Content) -> some View {
    let shape = TransportPanelShape()

    return content
      .dialRecessedPanel(
        shape: shape,
        fill: theme.surface.opacity(0.96),
        strokeOpacity: strokeOpacity,
        topSheenOpacity: DialMaterial.Transport.topSheenOpacity,
        innerShadowOpacity: DialMaterial.Transport.innerShadowOpacity)
      .overlay {
        DialHardwareImage(name: "transport-faceplate")
          .opacity(0.46)
          .allowsHitTesting(false)
          .clipShape(shape)
      }
  }
}
