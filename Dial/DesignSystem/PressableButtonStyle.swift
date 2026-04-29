// Dial/DesignSystem/PressableButtonStyle.swift
import SwiftUI

/// Replacement for `.buttonStyle(.plain)` that preserves the no-chrome
/// rendering but adds tactile press feedback: scale 0.96 + a small
/// opacity dim. Animates in 120ms easeOut so the press feels instant
/// but settles smoothly.
///
/// Why not use `.buttonStyle(.plain)`: it removes macOS's default
/// button chrome but provides no replacement feedback at all — taps
/// feel unresponsive because nothing visually changes. This style
/// matches the "make-interfaces-feel-better" guideline that every
/// interactive control should have a press response (scale 0.96
/// being the canonical value, never below 0.95 to avoid feeling
/// exaggerated).
///
/// Applied to: pet block, status bar nav icons + info, shuffle/repeat,
/// pixel grid permission overlay, back button. The gel transport buttons
/// have their own press feedback baked into `ToyTransportStyle`.
struct PressableButtonStyle: ButtonStyle {
  /// Per-press opacity dim. Subtle 0.85 reads as "pressed" without
  /// fighting the underlying color.
  var pressedOpacity: Double = 0.85
  var pressedOffsetY: CGFloat = 0.5

  func makeBody(configuration: Configuration) -> some View {
    PressableBody(
      configuration: configuration,
      pressedOpacity: pressedOpacity,
      pressedOffsetY: pressedOffsetY)
  }

  private struct PressableBody: View {
    let configuration: ButtonStyle.Configuration
    let pressedOpacity: Double
    let pressedOffsetY: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
        .offset(y: configuration.isPressed && !reduceMotion ? pressedOffsetY : 0)
        .opacity(configuration.isPressed ? pressedOpacity : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}

extension ButtonStyle where Self == PressableButtonStyle {
  /// Convenience accessor — `Button(...).buttonStyle(.pressable)`.
  static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
