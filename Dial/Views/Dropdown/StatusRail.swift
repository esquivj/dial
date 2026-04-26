import SwiftUI

struct StatusRail: View {
  @Bindable var vm: MenubarStripViewModel
  @Bindable var pet: PetViewModel
  @Binding var showingGlossary: Bool

  /// Flips true for ~700ms when the URI changes, so the indicator dot
  /// flashes magenta (event tone) before settling back to cyan (steady).
  @State private var trackPulse = false

  var body: some View {
    VStack(spacing: 0) {
      // Faint wine accent line where the amber LED used to be.
      Rectangle().fill(Dial.Palette.amber.opacity(0.4)).frame(height: 1)
      HStack(spacing: 8) {
        // Pet screen-within-screen: the bulldog lives inside its own little
        // LCD window. Cyan-tinted bezel + dim recessed background sells
        // the tamagotchi-on-a-handheld framing — the sprite is visibly
        // contained, like the LCD on the original Tamagotchi housing.
        // Sprite shrinks 2pt to leave room for the bezel without changing
        // the row's outer 28×28 footprint.
        ZStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.black.opacity(0.35))
          BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 24)
            .frame(width: 24, height: 24)
        }
        .frame(width: 28, height: 28)
        .overlay(
          RoundedRectangle(cornerRadius: 3)
            .stroke(Dial.Palette.amber.opacity(0.45), lineWidth: 0.5)
        )
        // Faint cyan halo so it reads as "lit" against the dark rail.
        .shadow(color: Dial.Palette.amber.opacity(0.25), radius: 3, x: 0, y: 0)
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
