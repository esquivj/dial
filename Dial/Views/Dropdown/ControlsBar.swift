import SwiftUI

struct ControlsBar: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void

  var body: some View {
    HStack {
      HStack(spacing: 10) {
        // Shuffle toggle — small icon-only button, color reflects state.
        // Optimistic flip: update menubar.shuffle immediately, fire API,
        // revert on error so the UI doesn't lie if Spotify rejects.
        Button {
          let prev = menubar.shuffle
          menubar.shuffle = !prev
          Task {
            do { try await client.setShuffle(!prev) }
            catch {
              await MainActor.run { menubar.shuffle = prev }
            }
          }
        } label: {
          Image(systemName: "shuffle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(menubar.shuffle ? Dial.Palette.amber : Dial.Palette.muted)
            .shadow(color: menubar.shuffle ? Dial.Palette.amber.opacity(0.6) : .clear,
                    radius: 4, x: 0, y: 0)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(menubar.shuffle ? "Shuffle on" : "Shuffle off")

        Button { Task { try? await client.prev() } } label: {
          Image(systemName: "backward.fill")
        }
        .buttonStyle(GelTransportStyle())
        Button {
          // Optimistic flip: update the local state immediately so the icon
          // changes on tap instead of waiting up to 3s for the next poll.
          // The polling loop will reaffirm (or correct) the state shortly after.
          let wasPlaying = menubar.state == .playing
          menubar.state = wasPlaying ? .paused : .playing
          Task {
            do {
              if wasPlaying { try await client.pause() }
              else          { try await client.play()  }
            } catch {
              // Revert if Spotify rejected the command (e.g. no active device).
              await MainActor.run {
                menubar.state = wasPlaying ? .playing : .paused
              }
            }
          }
        } label: {
          Image(systemName: menubar.state == .playing ? "pause.fill" : "play.fill")
            // Smooth SF-Symbol replace transition — scales / fades the
            // glyph between play↔pause instead of snap-cutting.
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GelTransportStyle())
        Button { Task { try? await client.next() } } label: {
          Image(systemName: "forward.fill")
        }
        .buttonStyle(GelTransportStyle())

        // Repeat cycle — off → context (whole album/playlist) → track → off.
        // SF Symbol switches to "repeat.1" in track-repeat mode and the tint
        // flips to magenta to make "this song will loop forever" visible at
        // a glance. Same optimistic pattern as shuffle.
        Button {
          let prev = menubar.repeatMode
          let next: RepeatMode = {
            switch prev {
            case .off:     return .context
            case .context: return .track
            case .track:   return .off
            }
          }()
          menubar.repeatMode = next
          Task {
            do { try await client.setRepeat(next.rawValue) }
            catch {
              await MainActor.run { menubar.repeatMode = prev }
            }
          }
        } label: {
          Image(systemName: menubar.repeatMode == .track ? "repeat.1" : "repeat")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(repeatColor)
            .shadow(color: menubar.repeatMode != .off ? repeatColor.opacity(0.6) : .clear,
                    radius: 4, x: 0, y: 0)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(repeatHelp)
      }
      // Slightly dimmer than the pure ivory of titles — gel pills are
      // already glow-bright, the icons sit better at 0.85 opacity ivory.
      .foregroundStyle(Dial.Palette.ivory.opacity(0.85))
      Spacer()
      HStack(spacing: 10) {
        Button(action: onOpenHistory) {
          Text("HISTORY")
            .font(Dial.Typography.monoLabel)
            .tracking(1.4)
            .foregroundStyle(Dial.Palette.muted)
        }
        .buttonStyle(.plain)
        Rectangle().fill(Dial.Palette.muted.opacity(0.4)).frame(width: 1, height: 10)
        Button(action: onOpenStats) {
          Text("STATS")
            .font(Dial.Typography.monoLabel)
            .tracking(1.4)
            .foregroundStyle(Dial.Palette.muted)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .background(Dial.Palette.subtle)
    .overlay(alignment: .top) {
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
    }
  }

  /// Color for the repeat icon — cyan for context-loop, magenta for the
  /// rarer track-loop (visually flags "this song will play forever"),
  /// muted when off.
  private var repeatColor: Color {
    switch menubar.repeatMode {
    case .off:     return Dial.Palette.muted
    case .context: return Dial.Palette.amber
    case .track:   return Dial.Palette.orange
    }
  }

  private var repeatHelp: String {
    switch menubar.repeatMode {
    case .off:     return "Repeat off"
    case .context: return "Repeat playlist"
    case .track:   return "Repeat track"
    }
  }
}

/// Gel-Aqua transport button — capsule pill with cyan glow, top-arc sheen,
/// and a hover/press response. Reads as a glassy hardware button below the
/// LCD screen, completing the "small crystal device" framing the rest of
/// the dropdown sets up. iTunes-Aqua inspiration; Y2K palette.
///
/// Implementation note: ButtonStyle.makeBody can't directly use @State,
/// so the body is wrapped in a private View where `hovering` lives.
private struct GelTransportStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    GelButtonView(configuration: configuration)
  }

  private struct GelButtonView: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        // 36×32 pill keeps the SF-Symbol glyph centered without empty
        // crowding it. Hit area survives less precise mousing.
        .frame(minWidth: 36, minHeight: 32)
        .contentShape(Capsule())
        .background(
          ZStack {
            // Base fill — top-lit cyan gradient. Subtle at rest, brightens
            // on hover so the button reads as "alive" without being noisy.
            Capsule()
              .fill(LinearGradient(colors: [
                Dial.Palette.amber.opacity(hovering ? 0.22 : 0.10),
                Dial.Palette.amber.opacity(0.03),
              ], startPoint: .top, endPoint: .bottom))

            // Border — thin cyan line that brightens on hover.
            Capsule()
              .stroke(
                Dial.Palette.amber.opacity(hovering ? 0.50 : 0.22),
                lineWidth: 0.5)

            // Top-arc highlight — the Aqua "gel sheen" at the top of the
            // pill. Half-trim of the capsule path, blurred slightly so it
            // reads as a soft reflection instead of a hard line.
            Capsule()
              .trim(from: 0, to: 0.5)
              .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
              .blur(radius: 0.4)
          }
          // Outer cyan glow — the Y2K "lit-from-within" halo. Stronger on
          // hover so motion through the controls bar feels responsive.
          .shadow(
            color: Dial.Palette.amber.opacity(hovering ? 0.45 : 0.18),
            radius: 6, x: 0, y: 0)
        )
        .opacity(configuration.isPressed ? 0.82 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
  }
}
