import SwiftUI

struct StatusRail: View {
  @Bindable var vm: MenubarStripViewModel
  @Binding var showingGlossary: Bool
  /// History + Stats are reachable directly from the rail. The pet
  /// thumbnail moved out of StatusRail entirely — it's now in TrackHero
  /// at 48×48 (was 24×24 here, too small to read the pixel-art detail).
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void
  let onOpenSettings: () -> Void

  /// Flips true for ~700ms when the URI changes, so the indicator dot
  /// flashes magenta (event tone) before settling back to cyan (steady).
  @State private var trackPulse = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dialTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      // Status bar items float free on the device body — earlier
      // version wrapped them in a Capsule pill chrome, but the actual
      // mockup render shows them ungrouped (the pill in section 5 of
      // the design system is shown as a *reusable component*, not as
      // how it appears in the rendered shell).
      HStack(spacing: Dial.Layout.StatusRail.spacing) {
        // Pet thumbnail relocated to TrackHero. Rail starts directly with
        // the indicator dot now — frees up ~40pt of horizontal space.
        Circle()
          .fill(trackPulse ? theme.memoryAccent : theme.accent)
          .frame(width: Dial.Layout.StatusRail.ledSize, height: Dial.Layout.StatusRail.ledSize)
          // Single tight halo — keeps the dot reading as a powered LED
          // without the prior two-layer bloom that pushed the glow into
          // "neon tacky" territory. The dot's color contrast against
          // the dark body does most of the "lit" work; the halo is
          // just a soft edge softening.
          .shadow(color: (trackPulse ? theme.memoryAccent : theme.accent).opacity(0.55), radius: 3)
          .animation(.easeOut(duration: 0.5), value: trackPulse)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(theme.accent)
        Spacer(minLength: 18)
        // Inline nav icons — surface History / Stats here so they're 1-tap
        // reachable instead of requiring the (undiscoverable) menubar
        // right-click. Pet stays accessible via the sprite tap on the left.
        // Uses our pixel-art icon set; filenames mirror SF Symbol names so
        // the call site reads identically to the prior systemName: variant.
        navIcon(name: "clock.arrow.circlepath", help: "Open History", action: onOpenHistory)
        navIcon(name: "chart.bar.fill", help: "Open Stats", action: onOpenStats)
        systemNavIcon(name: "gearshape.fill", help: "Open Settings", action: onOpenSettings)
        Button {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            showingGlossary.toggle()
          }
        } label: {
          statusIcon(showingGlossary ? "xmark.circle" : "info.circle")
        }
        .buttonStyle(.pressable)
        .help(showingGlossary ? "Hide glossary" : "What do these badges mean?")
        .accessibilityLabel(showingGlossary ? "Hide glossary" : "Show badge glossary")
      }
      // Keep the live controls inside the shortened hardware pocket so the
      // rail does not visually cut through the corner screws.
      .padding(.horizontal, Dial.Layout.StatusRail.horizontalPadding)
      .padding(.vertical, Dial.Layout.StatusRail.verticalPadding)
      .frame(
        width: Dial.Layout.StatusRail.contentWidth,
        height: Dial.Layout.StatusRail.railHeight)
    }
    // No background — status bar floats directly on the device body.
    // Earlier we painted a surface→ground gradient here, but with the
    // three-zone layout (status / LCD / transport) the LCD panel below
    // is the only zone that should look "lit," and the status bar reads
    // cleaner sitting flush on the device chrome.
    .onChange(of: vm.track?.uri) { _, _ in
      guard !reduceMotion else { return }
      // Track changed mid-session → flash the indicator magenta as a
      // celebration beat, then fade back to the cyan steady state.
      // (No fire on initial mount: SwiftUI's onChange skips the first
      // observation, so opening the popover with a song already playing
      // doesn't trigger a spurious pulse.)
      trackPulse = true
      Task {
        try? await Task.sleep(for: .milliseconds(700))
        await MainActor.run { trackPulse = false }
      }
    }
  }

  /// Compact icon-only nav button. Same hit slot as the info button
  /// for consistent thumbing. Renders our pixel-art icon set rather than
  /// SF Symbols — the chunky 1-bit glyph reads more "device chrome" than
  /// SF's smooth vector geometry.
  @ViewBuilder
  private func navIcon(
    name: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      statusIcon(name)
    }
    .buttonStyle(.pressable)
    .help(help)
    .accessibilityLabel(help)
  }

  @ViewBuilder
  private func systemNavIcon(
    name: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      statusIcon(name)
    }
    .buttonStyle(.pressable)
    .help(help)
    .accessibilityLabel(help)
  }

  private func statusIcon(_ name: String) -> some View {
    let metrics = statusIconMetrics(for: name)

    return DialIcon(name)
      .frame(width: metrics.size, height: metrics.size)
      .offset(y: metrics.yOffset)
      .foregroundStyle(theme.textPrimary.opacity(0.76))
      .frame(width: Dial.Layout.StatusRail.hitSize, height: Dial.Layout.StatusRail.hitSize)
      .background {
        RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
          .fill(theme.surface.opacity(0.26))
          .overlay(
            RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
              .stroke(theme.hairline.opacity(0.48), lineWidth: 0.7))
          .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
              .fill(Color.white.opacity(0.07))
              .frame(height: 1)
          }
      }
      .dialHitSlop(
        horizontal: max(0, (44 - Dial.Layout.StatusRail.hitSize) / 2),
        vertical: max(0, (44 - Dial.Layout.StatusRail.hitSize) / 2))
  }

  private func statusIconMetrics(for name: String) -> (size: CGFloat, yOffset: CGFloat) {
    switch name {
    case "chart.bar.fill":
      // This bitmap has a smaller opaque bounding box than the circular rail
      // icons, so equal frames make it look short. Scale the glyph, not the
      // hit target, to keep the row optically even.
      return (13.25, 0)
    default:
      return (Dial.Layout.StatusRail.iconSize, 0)
    }
  }
}
