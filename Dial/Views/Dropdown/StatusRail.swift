import SwiftUI

struct StatusRail: View {
  @Bindable var vm: MenubarStripViewModel
  @Binding var showingGlossary: Bool
  /// History + Stats are reachable directly from the rail. The pet
  /// thumbnail moved out of StatusRail entirely — it's now in TrackHero
  /// at 48×48 (was 24×24 here, too small to read the pixel-art detail).
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void

  /// Flips true for ~700ms when the URI changes, so the indicator dot
  /// flashes magenta (event tone) before settling back to cyan (steady).
  @State private var trackPulse = false

  var body: some View {
    VStack(spacing: 0) {
      // Status bar items float free on the device body — earlier
      // version wrapped them in a Capsule pill chrome, but the actual
      // mockup render shows them ungrouped (the pill in section 5 of
      // the design system is shown as a *reusable component*, not as
      // how it appears in the rendered shell).
      HStack(spacing: 8) {
        // Pet thumbnail relocated to TrackHero. Rail starts directly with
        // the indicator dot now — frees up ~40pt of horizontal space.
        Circle()
          .fill(trackPulse ? Dial.Palette.orange : Dial.Palette.amber)
          .frame(width: 6, height: 6)
          // Single tight halo — keeps the dot reading as a powered LED
          // without the prior two-layer bloom that pushed the glow into
          // "neon tacky" territory. The dot's color contrast against
          // the dark body does most of the "lit" work; the halo is
          // just a soft edge softening.
          .shadow(color: (trackPulse ? Dial.Palette.orange : Dial.Palette.amber).opacity(0.55), radius: 3)
          .animation(.easeOut(duration: 0.5), value: trackPulse)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.amber)
        Spacer()
        // Inline nav icons — surface History / Stats here so they're 1-tap
        // reachable instead of requiring the (undiscoverable) menubar
        // right-click. Pet stays accessible via the sprite tap on the left.
        // Uses our pixel-art icon set; filenames mirror SF Symbol names so
        // the call site reads identically to the prior systemName: variant.
        navIcon(name: "clock.arrow.circlepath", help: "Open History", action: onOpenHistory)
        navIcon(name: "chart.bar.fill", help: "Open Stats", action: onOpenStats)
        Button {
          showingGlossary.toggle()
        } label: {
          Image(systemName: showingGlossary ? "xmark.circle" : "info.circle")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Dial.Palette.muted)
            .contentTransition(.symbolEffect(.replace))
            // 24×24 hit slot to match navIcon — earlier 28×28 was
            // larger than the other status bar icons, breaking the
            // even rhythm across the bar.
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(showingGlossary ? "Hide glossary" : "What do these badges mean?")
        // Tick once a second while the dropdown is open so the timer reads
        // realtime even though we only poll Spotify every 3s.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          Text(timing(at: ctx.date))
            .font(Dial.Typography.monoLabel)
            .tracking(0.8)
            .foregroundStyle(Dial.Palette.muted)
            .monospacedDigit()
        }
      }
      // Horizontal padding 24pt (was 20) — at the status bar's vertical
      // position (y≈8–24pt inside the body), the 40pt corner curves
      // are still cutting inward; 20pt put NOW PLAYING and the time
      // visibly close to the curve boundary. 24pt gives both sides
      // symmetric breathing room and reads as deliberately balanced
      // rather than crowded.
      .padding(.horizontal, 24)
      .padding(.vertical, 4)
    }
    // No background — status bar floats directly on the device body.
    // Earlier we painted a surface→ground gradient here, but with the
    // three-zone layout (status / LCD / transport) the LCD panel below
    // is the only zone that should look "lit," and the status bar reads
    // cleaner sitting flush on the device chrome.
    .onChange(of: vm.track?.uri) { _, _ in
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

  /// Compact icon-only nav button. Same 28×28 hit slot as the info button
  /// for consistent thumbing. Renders our pixel-art icon set rather than
  /// SF Symbols — the chunky 1-bit glyph reads more "device chrome" than
  /// SF's smooth vector geometry.
  @ViewBuilder
  private func navIcon(
    name: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      DialIcon(name)
        .frame(width: 13, height: 13)
        .foregroundStyle(Dial.Palette.muted)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.pressable)
    .help(help)
  }

  /// Realtime-interpolated track progress.
  /// Adds (now − lastPoll) to the polled progressMs while playing, so the
  /// `MM:SS` reads continuously between 3-second poll cycles.
  private func timing(at now: Date) -> String {
    var ms = vm.progressMs
    if vm.state == .playing, let lastPoll = vm.lastProgressUpdate {
      ms += max(0, Int(now.timeIntervalSince(lastPoll) * 1000))
    }
    let s = max(ms, 0) / 1000
    return String(format: "%02d:%02d", s / 60, s % 60)
  }
}
