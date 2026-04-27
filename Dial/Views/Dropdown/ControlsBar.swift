import SwiftUI

struct ControlsBar: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient

  var body: some View {
    // Centered playback strip — shuffle / transport / repeat. The earlier
    // version also held HISTORY · STATS labels on the right, but with the
    // shuffle + repeat additions the row didn't fit in 320pt and HISTORY
    // wrapped to two lines. Both screens are now reachable from the
    // status item's right-click menu (Open History / Open Stats), so the
    // controls bar is free to be exclusively about playback.
    HStack {
      Spacer(minLength: 0)
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
          DialIcon("shuffle")
            .frame(width: 14, height: 14)
            .foregroundStyle(menubar.shuffle ? Dial.Palette.amber : Dial.Palette.muted)
            .shadow(color: menubar.shuffle ? Dial.Palette.amber.opacity(0.6) : .clear,
                    radius: 4, x: 0, y: 0)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(menubar.shuffle ? "Shuffle on" : "Shuffle off")

        Button { Task { try? await client.prev() } } label: {
          DialIcon("backward.fill").frame(width: 14, height: 14)
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
          // Pixel-art glyph swap. Lost the SF-Symbol .replace transition
          // (which is symbol-specific) — we crossfade via id+opacity
          // instead so the play↔pause flip still animates rather than
          // snap-cutting. 120ms duration matches the optimistic flip's
          // perceived response time.
          DialIcon(menubar.state == .playing ? "pause.fill" : "play.fill")
            .frame(width: 14, height: 14)
            .id(menubar.state)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .animation(.easeOut(duration: 0.12), value: menubar.state)
        }
        // `prominent: true` reads as the primary action — brighter mint
        // fill, stronger stroke, larger outer halo. Without it, all three
        // pills carried equal visual weight and the play button didn't
        // earn its central position.
        .buttonStyle(GelTransportStyle(prominent: true))
        Button { Task { try? await client.next() } } label: {
          DialIcon("forward.fill").frame(width: 14, height: 14)
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
          // Same id+opacity crossfade pattern as play↔pause — the
          // repeat → repeat-1 transition is rarer but still benefits from
          // motion since it signals "this song will loop forever," which
          // is a meaningful state change.
          DialIcon(menubar.repeatMode == .track ? "repeat.1" : "repeat")
            .frame(width: 14, height: 14)
            .foregroundStyle(repeatColor)
            .shadow(color: menubar.repeatMode != .off ? repeatColor.opacity(0.6) : .clear,
                    radius: 4, x: 0, y: 0)
            .id(menubar.repeatMode)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .animation(.easeOut(duration: 0.12), value: menubar.repeatMode)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(repeatHelp)
      }
      // Slightly dimmer than the pure ivory of titles — gel pills are
      // already glow-bright, the icons sit better at 0.85 opacity ivory.
      .foregroundStyle(Dial.Palette.ivory.opacity(0.85))
      Spacer(minLength: 0)
    }
    // Tighter vertical padding (4 vs 6). Background + top hairline
    // removed — the parent's `.lcdPanel()` modifier provides the
    // inset-panel chrome.
    .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
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

/// Translucent gel transport button — matches the Digivice-style render's
/// playback pills: a glassy semi-transparent capsule with a clear top
/// sheen, cyan icon inside, and a soft contact shadow. Reads as gel /
/// translucent plastic that catches light, not as solid white rubber.
///
/// Composition:
///   * Fill: white at low opacity (the chassis surface behind shows
///     through, tinted slightly white) — this is what makes it "gel"
///     instead of "rubber"
///   * Top-arc sheen: bright white wet-glass highlight at the upper curve
///   * Edge stroke: thin white for definition
///   * Drop shadow: dark, soft, no color — physical contact shadow
///
/// `prominent` flag bumps the fill opacity and sheen brightness on the
/// play/pause button — same hierarchy idea as before, expressed through
/// translucency strength rather than colored glow.
///
/// Implementation note: ButtonStyle.makeBody can't directly use @State,
/// so the body is wrapped in a private View where `hovering` lives.
private struct GelTransportStyle: ButtonStyle {
  var prominent: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    GelButtonView(configuration: configuration, prominent: prominent)
  }

  private struct GelButtonView: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @State private var hovering = false

    /// Pill dimensions. Prominent (play) gets a slightly larger frame
    /// so it reads as the primary action without colored glow.
    private var pillWidth: CGFloat  { prominent ? 44 : 36 }
    private var pillHeight: CGFloat { prominent ? 30 : 26 }

    /// Fill opacity (top of gradient). Translucent — the dark chassis
    /// surface behind shows through, which is what gives the button its
    /// "gel" reading versus "solid rubber."
    private var fillTopOpacity: Double {
      if prominent { return hovering ? 0.36 : 0.24 }
      return hovering ? 0.24 : 0.15
    }
    private var fillBottomOpacity: Double {
      if prominent { return hovering ? 0.12 : 0.08 }
      return hovering ? 0.08 : 0.04
    }

    /// Top-arc sheen brightness — the bright wet-glass reflection at
    /// the upper curve.
    private var sheenOpacity: Double {
      if prominent { return hovering ? 0.95 : 0.75 }
      return hovering ? 0.75 : 0.55
    }

    var body: some View {
      configuration.label
        // Cyan icon inside — single contrast point against the
        // translucent gel.
        .foregroundStyle(Dial.Palette.amber)
        .frame(minWidth: pillWidth, minHeight: pillHeight)
        .contentShape(Capsule())
        .background(
          ZStack {
            // Translucent gel fill — white at low opacity so the chassis
            // surface behind shows through tinted. Top-down gradient
            // (lighter top, fainter bottom) suggests light from above.
            Capsule()
              .fill(LinearGradient(
                colors: [
                  Color.white.opacity(fillTopOpacity),
                  Color.white.opacity(fillBottomOpacity),
                ],
                startPoint: .top, endPoint: .bottom))

            // Top-arc sheen — bright wet-glass reflection at the upper
            // curve. The single highest-leverage detail for "this is gel."
            Capsule()
              .trim(from: 0.0, to: 0.5)
              .stroke(Color.white.opacity(sheenOpacity), lineWidth: 0.8)
              .blur(radius: 0.4)

            // Thin white edge stroke — defines the pill against the
            // dark transport panel. Lower opacity than the rubber pass
            // so it doesn't double up with the sheen.
            Capsule()
              .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
          }
          // Soft dark contact shadow — physical "mounted on chassis"
          // depth, no color. Press state pulls the shadow tight to the
          // button so it visually "presses down."
          .shadow(
            color: Color.black.opacity(configuration.isPressed ? 0.25 : 0.45),
            radius: 3, x: 0, y: configuration.isPressed ? 0.5 : 1.5)
        )
        .opacity(configuration.isPressed ? 0.90 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
  }
}
