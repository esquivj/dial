import SwiftUI

struct StatusRail: View {
  @Bindable var vm: MenubarStripViewModel
  @Bindable var pet: PetViewModel
  @Binding var showingGlossary: Bool

  var body: some View {
    VStack(spacing: 0) {
      // Faint wine accent line where the amber LED used to be.
      Rectangle().fill(Dial.Palette.amber.opacity(0.4)).frame(height: 1)
      HStack(spacing: 8) {
        BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 28)
          .frame(width: 28, height: 28)
        Circle()
          .fill(Dial.Palette.amber)
          .frame(width: 6, height: 6)
          .shadow(color: Dial.Palette.amber, radius: 3)
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
