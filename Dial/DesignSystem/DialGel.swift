// Dial/DesignSystem/DialGel.swift
import SwiftUI

/// Shared material system for the handheld shell.
///
/// The important rule: plastic is described by white highlights, dark
/// contact shadows, and subtle translucency. Cyan/pink are reserved for
/// content and active state. Colored glow everywhere is how this turns
/// into mall-kiosk nonsense.
enum DialMaterial {
  enum Chassis {
    static let topTintOpacity = 0.08
    static let bottomShadeOpacity = 0.30
    static let cornerShadeOpacity = 0.38
    static let innerLipOpacity = 0.32
    static let strokeTopOpacity = 0.62
    static let strokeBottomOpacity = 0.10
    static let topSheenOpacity = 0.24
  }

  enum Recessed {
    static let strokeOpacity = 0.30
    static let topSheenOpacity = 0.24
    static let innerShadowOpacity = 0.42
    static let lowerShadeOpacity = 0.14
  }

  enum Raised {
    static let fillTopOpacity = 0.13
    static let fillBottomOpacity = 0.035
    static let edgeOpacity = 0.30
    static let sheenOpacity = 0.42
    static let contactShadowOpacity = 0.28
  }

  enum Printed {
    static let fillOpacity = 0.045
    static let edgeOpacity = 0.22
  }
}

struct ChassisPlastic<S: Shape>: ViewModifier {
  var shape: S

  func body(content: Content) -> some View {
    content
      .background(
        ZStack {
          Dial.Palette.ground
          LinearGradient(
            colors: [
              Color.white.opacity(DialMaterial.Chassis.topTintOpacity),
              Color.clear,
              Color.clear,
              Color.black.opacity(DialMaterial.Chassis.bottomShadeOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom)
          RadialGradient(
            colors: [
              Color.clear,
              Color.clear,
              Color.black.opacity(DialMaterial.Chassis.cornerShadeOpacity),
            ],
            center: .center,
            startRadius: 100,
            endRadius: 240)
          DustTexture()
        }
      )
      .clipShape(shape)
      .overlay(
        shape
          .stroke(Color.black.opacity(DialMaterial.Chassis.innerLipOpacity), lineWidth: 3)
          .blur(radius: 2)
          .offset(y: 2)
          .mask(shape)
          .allowsHitTesting(false)
      )
      .overlay(
        shape
          .stroke(LinearGradient(colors: [
            Color.white.opacity(DialMaterial.Chassis.strokeTopOpacity),
            Color.white.opacity(0.28),
            Color.white.opacity(0.15),
            Color.white.opacity(DialMaterial.Chassis.strokeBottomOpacity),
          ], startPoint: .top, endPoint: .bottom), lineWidth: 1.25)
          .allowsHitTesting(false)
      )
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [
            Color.white.opacity(DialMaterial.Chassis.topSheenOpacity),
            Color.white.opacity(0.08),
            Color.clear,
          ],
          startPoint: .top,
          endPoint: .bottom)
          .frame(height: 22)
          .clipShape(shape)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .topLeading) {
        RadialGradient(
          colors: [
            Color.white.opacity(0.16),
            Color.white.opacity(0.04),
            Color.clear,
          ],
          center: .topLeading,
          startRadius: 0,
          endRadius: 96)
          .frame(width: 132, height: 74)
          .offset(x: -18, y: -12)
          .clipShape(shape)
          .allowsHitTesting(false)
      }
  }
}

struct RecessedPanelMaterial<S: Shape>: ViewModifier {
  var shape: S
  var fill: Color = Dial.Palette.surface
  var strokeOpacity: Double = DialMaterial.Recessed.strokeOpacity
  var topSheenOpacity: Double = DialMaterial.Recessed.topSheenOpacity
  var innerShadowOpacity: Double = DialMaterial.Recessed.innerShadowOpacity

  func body(content: Content) -> some View {
    content
      .background(
        ZStack {
          shape.fill(fill)
          shape.fill(LinearGradient(
            colors: [
              Color.white.opacity(0.035),
              Color.clear,
              Color.black.opacity(DialMaterial.Recessed.lowerShadeOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom))
          shape
            .stroke(Color.black.opacity(innerShadowOpacity), lineWidth: 2.5)
            .blur(radius: 1.5)
            .offset(y: 1.5)
            .mask(shape)
        }
      )
      .clipShape(shape)
      .overlay(
        shape
          .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.75)
          .allowsHitTesting(false)
      )
      .overlay(
        shape
          .trim(from: 0.03, to: 0.30)
          .stroke(Color.white.opacity(topSheenOpacity), lineWidth: 0.65)
          .blur(radius: 0.25)
          .allowsHitTesting(false)
      )
      .overlay(alignment: .topLeading) {
        LinearGradient(
          colors: [
            Color.white.opacity(0.045),
            Color.clear,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
          .frame(width: 72, height: 12)
          .clipShape(shape)
          .allowsHitTesting(false)
      }
  }
}

struct RaisedGelMaterial<S: Shape>: ViewModifier {
  var shape: S
  var fill: Color = Dial.Palette.surface
  var edgeColor: Color = .white
  var edgeOpacity: Double = DialMaterial.Raised.edgeOpacity
  var fillTopOpacity: Double = DialMaterial.Raised.fillTopOpacity
  var fillBottomOpacity: Double = DialMaterial.Raised.fillBottomOpacity
  var sheenOpacity: Double = DialMaterial.Raised.sheenOpacity
  var sheenLineWidth: CGFloat = 0.8
  var contactShadowOpacity: Double = DialMaterial.Raised.contactShadowOpacity
  var contactShadowRadius: CGFloat = 2
  var contactShadowY: CGFloat = 1
  var innerShadowOpacity: Double = 0.18

  func body(content: Content) -> some View {
    content
      .background(
        ZStack {
          shape.fill(fill)
          shape.fill(LinearGradient(
            colors: [
              Color.white.opacity(fillTopOpacity),
              Color.white.opacity(fillBottomOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom))
          shape.fill(LinearGradient(
            colors: [
              Color.white.opacity(fillTopOpacity * 0.65),
              Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .center))
          shape
            .stroke(Color.black.opacity(innerShadowOpacity), lineWidth: 2)
            .blur(radius: 1.2)
            .offset(y: 1)
            .mask(shape)
          shape
            .trim(from: 0.04, to: 0.46)
            .stroke(Color.white.opacity(sheenOpacity), lineWidth: sheenLineWidth)
            .blur(radius: 0.35)
        }
      )
      .overlay(
        shape
          .stroke(edgeColor.opacity(edgeOpacity), lineWidth: 0.65)
          .allowsHitTesting(false)
      )
      .shadow(
        color: Color.black.opacity(contactShadowOpacity),
        radius: contactShadowRadius,
        x: 0,
        y: contactShadowY)
  }
}

struct PrintedChipMaterial<S: Shape>: ViewModifier {
  var shape: S
  var color: Color
  var fillOpacity: Double = DialMaterial.Printed.fillOpacity
  var edgeOpacity: Double = DialMaterial.Printed.edgeOpacity

  func body(content: Content) -> some View {
    content
      .background(
        ZStack {
          shape.fill(color.opacity(fillOpacity))
          shape.fill(Color.white.opacity(0.018))
        }
      )
      .overlay(
        shape
          .stroke(color.opacity(edgeOpacity), lineWidth: 0.55)
          .allowsHitTesting(false)
      )
      .clipShape(shape)
  }
}

struct MediaFrameMaterial<S: Shape>: ViewModifier {
  var shape: S

  func body(content: Content) -> some View {
    content
      .background(shape.fill(Dial.Palette.surface))
      .clipShape(shape)
      .overlay(
        shape
          .stroke(Color.black.opacity(0.48), lineWidth: 3)
          .blur(radius: 1.6)
          .offset(y: 1.4)
          .mask(shape)
          .allowsHitTesting(false)
      )
      .overlay(alignment: .topLeading) {
        LinearGradient(
          colors: [
            Color.white.opacity(0.30),
            Color.white.opacity(0.10),
            Color.clear,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
          .frame(width: 54, height: 26)
          .clipShape(shape)
          .allowsHitTesting(false)
      }
      .overlay(
        shape
          .stroke(Color.white.opacity(0.38), lineWidth: 0.75)
          .allowsHitTesting(false)
      )
      .shadow(color: Color.black.opacity(0.38), radius: 4, x: 0, y: 2)
  }
}

/// Backward-compatible wrapper for older call sites. New UI should prefer
/// `dialRaisedGel(...)` so the material intent is explicit.
struct GelContainer: ViewModifier {
  var cornerRadius: CGFloat
  var strokeColor: Color = .white
  var haloColor: Color = Dial.Palette.accent
  var strokeOpacity: Double = 0.50
  var sheenOpacity: Double = 0.45
  var sheenLineWidth: CGFloat = 1.2
  var haloOpacity: Double = 0.30
  var haloRadius: CGFloat = 9
  var convexTopOpacity: Double = 0.20
  var convexBottomOpacity: Double = 0.22
  var innerShadowOpacity: Double = 0.45
  var innerShadowOffset: CGFloat = 1.5
  var baseFill: Color = Dial.Palette.surface

  func body(content: Content) -> some View {
    content
      .dialRaisedGel(
        shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
        fill: baseFill,
        edgeColor: strokeColor,
        edgeOpacity: strokeOpacity,
        fillTopOpacity: convexTopOpacity,
        fillBottomOpacity: convexBottomOpacity,
        sheenOpacity: sheenOpacity,
        sheenLineWidth: sheenLineWidth,
        contactShadowOpacity: 0,
        innerShadowOpacity: innerShadowOpacity
      )
      .shadow(color: haloColor.opacity(haloOpacity), radius: haloRadius, x: 0, y: 0)
  }
}

extension View {
  func dialChassisPlastic<S: Shape>(shape: S) -> some View {
    self.modifier(ChassisPlastic(shape: shape))
  }

  func dialRecessedPanel<S: Shape>(
    shape: S,
    fill: Color = Dial.Palette.surface,
    strokeOpacity: Double = DialMaterial.Recessed.strokeOpacity,
    topSheenOpacity: Double = DialMaterial.Recessed.topSheenOpacity,
    innerShadowOpacity: Double = DialMaterial.Recessed.innerShadowOpacity
  ) -> some View {
    self.modifier(RecessedPanelMaterial(
      shape: shape,
      fill: fill,
      strokeOpacity: strokeOpacity,
      topSheenOpacity: topSheenOpacity,
      innerShadowOpacity: innerShadowOpacity))
  }

  func dialRaisedGel<S: Shape>(
    shape: S,
    fill: Color = Dial.Palette.surface,
    edgeColor: Color = .white,
    edgeOpacity: Double = DialMaterial.Raised.edgeOpacity,
    fillTopOpacity: Double = DialMaterial.Raised.fillTopOpacity,
    fillBottomOpacity: Double = DialMaterial.Raised.fillBottomOpacity,
    sheenOpacity: Double = DialMaterial.Raised.sheenOpacity,
    sheenLineWidth: CGFloat = 0.8,
    contactShadowOpacity: Double = DialMaterial.Raised.contactShadowOpacity,
    contactShadowRadius: CGFloat = 2,
    contactShadowY: CGFloat = 1,
    innerShadowOpacity: Double = 0.18
  ) -> some View {
    self.modifier(RaisedGelMaterial(
      shape: shape,
      fill: fill,
      edgeColor: edgeColor,
      edgeOpacity: edgeOpacity,
      fillTopOpacity: fillTopOpacity,
      fillBottomOpacity: fillBottomOpacity,
      sheenOpacity: sheenOpacity,
      sheenLineWidth: sheenLineWidth,
      contactShadowOpacity: contactShadowOpacity,
      contactShadowRadius: contactShadowRadius,
      contactShadowY: contactShadowY,
      innerShadowOpacity: innerShadowOpacity))
  }

  func dialPrintedChip<S: Shape>(
    shape: S,
    color: Color,
    fillOpacity: Double = DialMaterial.Printed.fillOpacity,
    edgeOpacity: Double = DialMaterial.Printed.edgeOpacity
  ) -> some View {
    self.modifier(PrintedChipMaterial(
      shape: shape,
      color: color,
      fillOpacity: fillOpacity,
      edgeOpacity: edgeOpacity))
  }

  func dialMediaFrame<S: Shape>(shape: S) -> some View {
    self.modifier(MediaFrameMaterial(shape: shape))
  }

  /// Apply the gel/convex container chrome. See `GelContainer` for the
  /// compatibility details. Prefer `dialRaisedGel(...)` for new UI.
  func gelContainer(
    cornerRadius: CGFloat,
    strokeColor: Color = .white,
    haloColor: Color = Dial.Palette.accent,
    strokeOpacity: Double = 0.50,
    sheenOpacity: Double = 0.55,
    sheenLineWidth: CGFloat = 1.0,
    haloOpacity: Double = 0,
    haloRadius: CGFloat = 8,
    convexTopOpacity: Double = 0.10,
    convexBottomOpacity: Double = 0.04,
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
