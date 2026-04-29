// Dial/Views/Dropdown/BackButton.swift
import SwiftUI

/// Header back-button used by HistoryView and StatsView. The chevron is
/// visually the same size, but the hit target is 36×28 (vs. ~12×12 for a
/// bare `Image`) and a subtle background highlight on hover makes the
/// affordance clear at a glance.
struct BackButton: View {
  let action: () -> Void
  @State private var hover = false
  @Environment(\.dialTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        DialIcon("chevron.left")
          .frame(width: 10, height: 10)
        Text("BACK")
          .font(Dial.Typography.monoLabel)
          .tracking(1.2)
      }
      .foregroundStyle(Dial.Palette.textPrimary.opacity(hover ? 1.0 : 0.7))
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: Dial.Radius.tiny)
          .fill(theme.accent.opacity(hover ? 0.08 : 0))
      )
    }
    .buttonStyle(.pressable)
    .accessibilityLabel("Back")
    .onHover { hover = $0 }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hover)
  }
}
