// Dial/Views/Dropdown/BackButton.swift
import SwiftUI

/// Header back-button used by HistoryView and StatsView. The chevron is
/// visually the same size, but the hit target is 36×28 (vs. ~12×12 for a
/// bare `Image`) and a subtle background highlight on hover makes the
/// affordance clear at a glance.
struct BackButton: View {
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: "chevron.left")
          .font(.system(size: 13, weight: .semibold))
        Text("BACK")
          .font(Dial.Typography.monoLabel)
          .tracking(1.2)
      }
      .foregroundStyle(Dial.Palette.ivory.opacity(hover ? 1.0 : 0.7))
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(Dial.Palette.amber.opacity(hover ? 0.08 : 0))
      )
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}
