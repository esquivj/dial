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
      // Faint wine accent line where the amber LED used to be.
      Rectangle().fill(Dial.Palette.amber.opacity(0.4)).frame(height: 1)
      HStack(spacing: 8) {
        // Pet thumbnail relocated to TrackHero. Rail starts directly with
        // the indicator dot now — frees up ~40pt of horizontal space.
        Circle()
          .fill(trackPulse ? Dial.Palette.orange : Dial.Palette.amber)
          .frame(width: 6, height: 6)
          .shadow(color: trackPulse ? Dial.Palette.orange : Dial.Palette.amber, radius: 3)
          .animation(.easeOut(duration: 0.5), value: trackPulse)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.amber)
        Spacer()
        // Inline nav icons — surface History / Stats here so they're 1-tap
        // reachable instead of requiring the (undiscoverable) menubar
        // right-click. Pet stays accessible via the sprite tap on the left.
        navIcon(systemName: "clock.arrow.circlepath", help: "Open History", action: onOpenHistory)
        navIcon(systemName: "chart.bar", help: "Open Stats", action: onOpenStats)
        Button {
          showingGlossary.toggle()
        } label: {
          Image(systemName: showingGlossary ? "xmark.circle" : "info.circle")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Dial.Palette.muted)
            .contentTransition(.symbolEffect(.replace))
            // Pad to a 28×28 hit slot — the visible glyph is 11pt, but
            // padding makes the tap target survive less precise mousing.
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
    }
    .background(LinearGradient(colors: [Dial.Palette.surface, Dial.Palette.ground],
                               startPoint: .top, endPoint: .bottom))
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
  /// for consistent thumbing.
  @ViewBuilder
  private func navIcon(
    systemName: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(Dial.Palette.muted)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
