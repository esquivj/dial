// Dial/Views/Dropdown/Marquee.swift
import SwiftUI

/// Y2K-cliché horizontal scrolling text. When the text fits within the
/// container, renders as a normal lineLimit(1). When it overflows,
/// auto-scrolls left at a constant speed with a duplicate copy trailing
/// for seamless wrap.
///
/// Respects `accessibilityReduceMotion` — when set, falls back to plain
/// truncated text regardless of length.
struct Marquee: View {
  let text: String
  let font: Font
  var foreground: Color = Dial.Palette.textPrimary
  /// Pixels per second of horizontal travel. 30 reads as "deliberate"
  /// — fast enough to be lively, slow enough to be readable.
  var speed: Double = 30
  /// Visible gap between the trailing copy and the next leading copy.
  var gap: CGFloat = 40

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var textWidth: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let containerWidth = proxy.size.width
      let needsScroll = textWidth > containerWidth && !reduceMotion
      // Keep the repeated copy fully off-screen until the first copy has
      // left. A small fixed gap let fragments of the next copy appear beside
      // the current title, which read like broken duplicate text in the HUD.
      let effectiveGap = max(gap, containerWidth)

      Group {
        if needsScroll {
          // TimelineView ticks at the display refresh rate. We compute the
          // offset each tick from a phase modulo the cycle length — no
          // SwiftUI .animation() involved, so the loop is naturally
          // seamless and doesn't fight track-change reloads or other
          // state mutations.
          TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cycleLen = (Double(textWidth) + Double(effectiveGap)) / speed
            let phase = elapsed.truncatingRemainder(dividingBy: cycleLen) / cycleLen
            let offsetX = -CGFloat(phase) * (textWidth + effectiveGap)

            HStack(spacing: effectiveGap) {
              Text(text).font(font).foregroundStyle(foreground).fixedSize()
              Text(text).font(font).foregroundStyle(foreground).fixedSize()
            }
            .offset(x: offsetX)
          }
        } else {
          Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
        }
      }
      .frame(width: containerWidth, alignment: .leading)
      .clipped()
    }
    // Background-measurer trick: render an off-screen, transparent copy
    // at its natural size so we can read its width via GeometryReader.
    // Updates on text change so swapping tracks recomputes the scroll.
    .background(
      Text(text)
        .font(font)
        .fixedSize()
        .opacity(0)
        .background(
          GeometryReader { textProxy in
            Color.clear
              .onAppear { textWidth = textProxy.size.width }
              .onChange(of: textProxy.size.width) { _, w in textWidth = w }
          }
        )
    )
    // While scrolling there are two visible copies of the text (plus the
    // hidden measurer); VoiceOver should hear the title once.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .accessibilityAddTraits(.isStaticText)
  }
}
