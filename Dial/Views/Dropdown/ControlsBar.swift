import SwiftUI

struct ControlsBar: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient

  var body: some View {
    VStack(spacing: Dial.Layout.Transport.stackSpacing) {
      PlaybackScrubber(menubar: menubar, client: client)
      transportButtons
    }
    .padding(Dial.Layout.Transport.padding)
  }

  private var transportButtons: some View {
    ZStack {
      HStack {
        shuffleButton
        Spacer(minLength: 0)
        repeatButton
      }
      .padding(.horizontal, Dial.Layout.Transport.edgeButtonInset)

      HStack(spacing: Dial.Layout.Transport.clusterSpacing) {
        previousButton
        playPauseButton
        nextButton
      }
    }
    .foregroundStyle(Dial.Palette.textPrimary.opacity(0.85))
    .frame(maxWidth: .infinity, minHeight: Dial.Layout.Transport.minButtonRowHeight)
  }

  private var shuffleButton: some View {
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
      DialThickIcon("shuffle", size: 14)
        .foregroundStyle(menubar.shuffle ? Dial.Palette.accent : Dial.Palette.textMuted)
        .frame(width: Dial.Layout.Transport.iconHitSize, height: Dial.Layout.Transport.iconHitSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.pressable)
    .help(menubar.shuffle ? "Shuffle on" : "Shuffle off")
    .accessibilityLabel(menubar.shuffle ? "Turn shuffle off" : "Turn shuffle on")
  }

  private var previousButton: some View {
    Button { Task { try? await client.prev() } } label: {
      DialThickIcon("backward.fill", size: 14)
    }
    .buttonStyle(GelTransportStyle())
    .help("Previous track")
    .accessibilityLabel("Previous track")
  }

  private var playPauseButton: some View {
    Button {
      let wasPlaying = menubar.state == .playing
      let now = Date()
      let anchoredProgress = menubar.interpolatedProgressMs(at: now)
      menubar.setOptimisticProgress(anchoredProgress, at: now)
      menubar.state = wasPlaying ? .paused : .playing
      Task {
        do {
          if wasPlaying { try await client.pause() }
          else          { try await client.play()  }
        } catch {
          await MainActor.run {
            menubar.state = wasPlaying ? .playing : .paused
          }
        }
      }
    } label: {
      DialThickIcon(menubar.state == .playing ? "pause.fill" : "play.fill", size: 14)
        .id(menubar.state)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .animation(.easeOut(duration: 0.12), value: menubar.state)
    }
    .buttonStyle(GelTransportStyle(prominent: true))
    .help(menubar.state == .playing ? "Pause" : "Play")
    .accessibilityLabel(menubar.state == .playing ? "Pause" : "Play")
  }

  private var nextButton: some View {
    Button { Task { try? await client.next() } } label: {
      DialThickIcon("forward.fill", size: 14)
    }
    .buttonStyle(GelTransportStyle())
    .help("Next track")
    .accessibilityLabel("Next track")
  }

  private var repeatButton: some View {
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
      DialThickIcon(menubar.repeatMode == .track ? "repeat.1" : "repeat", size: 14)
        .foregroundStyle(repeatColor)
        .id(menubar.repeatMode)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .animation(.easeOut(duration: 0.12), value: menubar.repeatMode)
        .frame(width: Dial.Layout.Transport.iconHitSize, height: Dial.Layout.Transport.iconHitSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.pressable)
    .help(repeatHelp)
    .accessibilityLabel(repeatAccessibilityLabel)
  }

  /// Color for the repeat icon — cyan for context-loop, magenta for the
  /// rarer track-loop (visually flags "this song will play forever"),
  /// muted when off.
  private var repeatColor: Color {
    switch menubar.repeatMode {
    case .off:     return Dial.Palette.textMuted
    case .context: return Dial.Palette.accent
    case .track:   return Dial.Palette.accentAlt
    }
  }

  private var repeatHelp: String {
    switch menubar.repeatMode {
    case .off:     return "Repeat off"
    case .context: return "Repeat playlist"
    case .track:   return "Repeat track"
    }
  }

  private var repeatAccessibilityLabel: String {
    switch menubar.repeatMode {
    case .off:     return "Turn repeat on"
    case .context: return "Repeat playlist is on. Switch to repeat track"
    case .track:   return "Repeat track is on. Turn repeat off"
    }
  }
}

private struct PlaybackScrubber: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient

  @State private var draggingFraction: Double?
  @State private var hovering = false
  @State private var seekTask: Task<Void, Never>?

  private var durationMs: Int { max(0, menubar.durationMs) }
  private var isSeekable: Bool { menubar.hasSeekableTrack }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let progress = displayedProgress(at: context.date)
      let currentFraction = progressFraction(progress)

      HStack(spacing: Dial.Layout.Transport.scrubberSpacing) {
        Text(timeLabel(progress))
          .frame(width: Dial.Layout.Transport.scrubberTimeWidth, alignment: .trailing)

        scrubberTrack(fraction: currentFraction)
          .frame(height: Dial.Layout.Transport.scrubberHeight)

        Text(timeLabel(durationMs))
          .frame(width: Dial.Layout.Transport.scrubberTimeWidth, alignment: .leading)
      }
      .font(Dial.Typography.monoLabel)
      .tracking(0.4)
      .foregroundStyle(isSeekable ? Dial.Palette.textPrimary.opacity(0.78) : Dial.Palette.textMuted.opacity(0.6))
      .monospacedDigit()
    }
    .opacity(isSeekable ? 1 : 0.55)
    .allowsHitTesting(isSeekable)
    .help(isSeekable ? "Seek in track" : "No seekable track")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Playback position")
    .accessibilityValue(isSeekable ? "\(timeLabel(displayedProgress(at: Date()))) of \(timeLabel(durationMs))" : "No seekable track")
    .accessibilityAdjustableAction { direction in
      guard isSeekable else { return }
      let current = menubar.interpolatedProgressMs()
      let delta = 15_000
      switch direction {
      case .increment:
        commitSeek(toMilliseconds: current + delta)
      case .decrement:
        commitSeek(toMilliseconds: current - delta)
      @unknown default:
        break
      }
    }
    .onDisappear {
      seekTask?.cancel()
      seekTask = nil
    }
  }

  private func displayedProgress(at date: Date) -> Int {
    if let draggingFraction {
      return Int((Double(durationMs) * draggingFraction).rounded())
    }
    return menubar.interpolatedProgressMs(at: date)
  }

  private func progressFraction(_ progress: Int) -> Double {
    guard durationMs > 0 else { return 0 }
    return min(1, max(0, Double(progress) / Double(durationMs)))
  }

  private func scrubberTrack(fraction: Double) -> some View {
    GeometryReader { proxy in
      let width = max(1, proxy.size.width)
      let fillWidth = width * fraction
      let thumbSize = (draggingFraction != nil || hovering)
        ? Dial.Layout.Transport.thumbActiveSize
        : Dial.Layout.Transport.thumbRestingSize

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.12))
          .frame(height: Dial.Layout.Transport.trackHeight)

        Capsule()
          .fill(Dial.Palette.accent.opacity(0.82))
          .frame(width: max(Dial.Layout.Transport.trackHeight, fillWidth), height: Dial.Layout.Transport.trackHeight)

        Circle()
          .fill(Dial.Palette.textPrimary)
          .overlay(Circle().stroke(Dial.Palette.accent.opacity(0.55), lineWidth: 0.8))
          .frame(width: thumbSize, height: thumbSize)
          .offset(x: min(max(0, fillWidth - thumbSize / 2), width - thumbSize))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            draggingFraction = scrubFraction(for: value.location.x, width: width)
          }
          .onEnded { value in
            commitSeek(to: scrubFraction(for: value.location.x, width: width))
          }
      )
      .onHover { hovering = $0 }
    }
  }

  private func scrubFraction(for x: CGFloat, width: CGFloat) -> Double {
    guard width > 0 else { return 0 }
    return min(1, max(0, Double(x / width)))
  }

  private func commitSeek(to fraction: Double) {
    guard isSeekable else {
      draggingFraction = nil
      return
    }

    let targetMs = Int((Double(durationMs) * fraction).rounded())
    draggingFraction = nil
    commitSeek(toMilliseconds: targetMs)
  }

  private func commitSeek(toMilliseconds targetMs: Int) {
    guard isSeekable else { return }
    let clamped = min(durationMs, max(0, targetMs))
    menubar.setOptimisticProgress(clamped)

    seekTask?.cancel()
    seekTask = Task {
      try? await client.seek(positionMs: clamped)
    }
  }

  private func timeLabel(_ ms: Int) -> String {
    guard isSeekable else { return "--:--" }

    let totalSeconds = max(0, ms) / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pill dimensions. Prominent (play) gets a slightly larger frame
    /// so it reads as the primary action without colored glow.
    private var pillWidth: CGFloat {
      prominent ? Dial.Layout.Transport.prominentPillWidth : Dial.Layout.Transport.secondaryPillWidth
    }
    private var pillHeight: CGFloat {
      prominent ? Dial.Layout.Transport.prominentPillHeight : Dial.Layout.Transport.secondaryPillHeight
    }

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
      let pressed = configuration.isPressed

      configuration.label
        .foregroundStyle(Dial.Palette.accent)
        .frame(minWidth: pillWidth, minHeight: pillHeight)
        .contentShape(Capsule())
        .dialRaisedGel(
          shape: Capsule(),
          fill: .clear,
          edgeOpacity: 0.35,
          fillTopOpacity: pressed ? fillTopOpacity * 0.62 : fillTopOpacity,
          fillBottomOpacity: pressed ? fillBottomOpacity * 0.55 : fillBottomOpacity,
          sheenOpacity: pressed ? sheenOpacity * 0.52 : sheenOpacity,
          sheenLineWidth: 0.8,
          contactShadowOpacity: pressed ? 0.25 : 0.45,
          contactShadowRadius: 3,
          contactShadowY: pressed ? 0.5 : 1.5,
          innerShadowOpacity: 0.10)
        .opacity(pressed ? 0.90 : 1.0)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .offset(y: pressed ? 0.5 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
  }
}
