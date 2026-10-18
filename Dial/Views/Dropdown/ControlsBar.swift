import SwiftUI

struct ControlsBar: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient
  @Environment(\.dialTheme) private var theme

  var body: some View {
    VStack(spacing: Dial.Layout.Transport.stackSpacing) {
      PlaybackScrubber(menubar: menubar, client: client)
      transportButtons
    }
    .padding(Dial.Layout.Transport.padding)
  }

  private var commands: TransportCommands {
    TransportCommands(menubar: menubar, transport: client)
  }

  private var transportButtons: some View {
    ZStack {
      TransportWellRow()

      HStack(spacing: 0) {
        shuffleButton

        Spacer(minLength: 12)

        HStack(spacing: TransportHardware.centralSpacing) {
          previousButton
          playPauseButton
          nextButton
        }

        Spacer(minLength: 12)

        repeatButton
      }
      .padding(.horizontal, TransportHardware.deckHorizontalPadding)
    }
    .foregroundStyle(theme.textPrimary.opacity(0.92))
    .frame(maxWidth: .infinity, minHeight: TransportHardware.rowHeight)
    .offset(y: Dial.Layout.Transport.buttonRowYOffset)
  }

  private var shuffleButton: some View {
    Button {
      let prev = menubar.shuffle
      let next = !prev
      menubar.setOptimisticShuffle(next)
      Task {
        do { try await client.setShuffle(next) }
        catch {
          await MainActor.run { menubar.revertOptimisticShuffle(to: prev) }
        }
      }
    } label: {
      DialThickIcon("shuffle", size: 14)
        .foregroundStyle(menubar.shuffle ? theme.accent : theme.textMuted)
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
    }
    .buttonStyle(ToyUtilityStyle(active: menubar.shuffle))
    .help(menubar.shuffle ? "Shuffle on" : "Shuffle off")
    .accessibilityLabel(menubar.shuffle ? "Turn shuffle off" : "Turn shuffle on")
  }

  private var previousButton: some View {
    Button { commands.previous() } label: {
      DialThickIcon("backward.fill", size: 14)
    }
    .buttonStyle(ToyTransportStyle())
    .help("Previous track")
    .accessibilityLabel("Previous track")
  }

  private var playPauseButton: some View {
    Button {
      commands.togglePlayPause()
    } label: {
      DialThickIcon(menubar.state == .playing ? "pause.fill" : "play.fill", size: 14)
        .id(menubar.state)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .animation(.easeOut(duration: 0.12), value: menubar.state)
    }
    .buttonStyle(ToyTransportStyle(prominent: true))
    .help(menubar.state == .playing ? "Pause" : "Play")
    .accessibilityLabel(menubar.state == .playing ? "Pause" : "Play")
  }

  private var nextButton: some View {
    Button { commands.next() } label: {
      DialThickIcon("forward.fill", size: 14)
    }
    .buttonStyle(ToyTransportStyle())
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
      menubar.setOptimisticRepeatMode(next)
      Task {
        do { try await client.setRepeat(next.rawValue) }
        catch {
          await MainActor.run { menubar.revertOptimisticRepeatMode(to: prev) }
        }
      }
    } label: {
      DialThickIcon(menubar.repeatMode == .track ? "repeat.1" : "repeat", size: 14)
        .foregroundStyle(repeatColor)
        .id(menubar.repeatMode)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .animation(.easeOut(duration: 0.12), value: menubar.repeatMode)
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
    }
    .buttonStyle(ToyUtilityStyle(active: menubar.repeatMode != .off))
    .help(repeatHelp)
    .accessibilityLabel(repeatAccessibilityLabel)
  }

  /// Color for the repeat icon — cyan for context-loop, magenta for the
  /// rarer track-loop (visually flags "this song will play forever"),
  /// muted when off.
  private var repeatColor: Color {
    switch menubar.repeatMode {
    case .off:     return theme.textMuted
    case .context: return theme.accent
    case .track:   return theme.memoryAccent
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
  @Environment(\.dialTheme) private var theme

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
      .foregroundStyle(isSeekable ? theme.textPrimary.opacity(0.78) : theme.textMuted.opacity(0.6))
      .monospacedDigit()
    }
    .offset(y: Dial.Layout.Transport.scrubberYOffset)
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
          .fill(Color.black.opacity(0.36))
          .frame(height: Dial.Layout.Transport.trackHeight)
          .overlay(
            Capsule()
              .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
          )

        Capsule()
          .fill(theme.accent.opacity(0.86))
          .frame(width: max(Dial.Layout.Transport.trackHeight, fillWidth), height: Dial.Layout.Transport.trackHeight)

        Circle()
          .fill(theme.buttonChrome)
          .overlay(Circle().stroke(theme.accent.opacity(0.55), lineWidth: 0.8))
          .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 1)
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

enum TransportHardware {
  static let rowHeight: CGFloat = 39
  static let deckHorizontalPadding: CGFloat = 22
  static let centralSpacing: CGFloat = 8
  static let utilitySize = CGSize(width: 38, height: 28)
  static let transportSize = CGSize(width: 44, height: 31)
  static let playSize = CGSize(width: 58, height: 35)
  static let buttonInset: CGFloat = 2.5

  static func buttonSize(prominent: Bool) -> CGSize {
    let slot = prominent ? playSize : transportSize
    return CGSize(width: slot.width - buttonInset, height: slot.height - buttonInset)
  }
}

private struct TransportWellRow: View {
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 0) {
      TransportDeckWell(size: TransportHardware.utilitySize, glowOpacity: 0.035)

      Spacer(minLength: 12)

      HStack(spacing: TransportHardware.centralSpacing) {
        TransportDeckWell(size: TransportHardware.transportSize, glowOpacity: 0.045)
        TransportDeckWell(size: TransportHardware.playSize, glowOpacity: 0.055)
        TransportDeckWell(size: TransportHardware.transportSize, glowOpacity: 0.045)
      }

      Spacer(minLength: 12)

      TransportDeckWell(size: TransportHardware.utilitySize, glowOpacity: 0.035)
    }
    .padding(.horizontal, TransportHardware.deckHorizontalPadding)
    .frame(height: TransportHardware.rowHeight)
    .allowsHitTesting(false)
  }
}

private struct TransportDeckWell: View {
  let size: CGSize
  let glowOpacity: Double
  @Environment(\.dialTheme) private var theme

  private var assetName: String {
    if size == TransportHardware.playSize { return "transport-well-play" }
    if size == TransportHardware.transportSize { return "transport-well-button" }
    return "transport-well-utility"
  }

  var body: some View {
    Capsule()
      .fill(LinearGradient(
        colors: [
          Color.black.opacity(0.22),
          theme.surface.opacity(0.36),
          theme.buttonGlow.opacity(glowOpacity),
        ],
        startPoint: .top,
        endPoint: .bottom))
      .frame(width: size.width, height: size.height)
      .overlay(
        Capsule()
          .stroke(Color.black.opacity(0.30), lineWidth: 1.2)
          .blur(radius: 0.7)
          .offset(y: 0.5)
          .mask(Capsule())
      )
      .overlay(
        Capsule()
          .stroke(Color.white.opacity(0.075), lineWidth: 0.65)
      )
      .overlay {
        DialHardwareImage(name: assetName)
          .opacity(0.62)
          .allowsHitTesting(false)
      }
  }
}

/// Oval hardware transport button. Less app pill, more toy control:
/// chrome bevel outside, rubber insert inside, and a pressed state that
/// sinks instead of blooming.
private struct ToyTransportStyle: ButtonStyle {
  var prominent: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    ToyButtonView(configuration: configuration, prominent: prominent)
  }

  private struct ToyButtonView: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dialTheme) private var theme

    private var buttonWidth: CGFloat {
      TransportHardware.buttonSize(prominent: prominent).width
    }
    private var buttonHeight: CGFloat {
      TransportHardware.buttonSize(prominent: prominent).height
    }
    private var slotWidth: CGFloat {
      prominent ? TransportHardware.playSize.width : TransportHardware.transportSize.width
    }
    private var slotHeight: CGFloat {
      prominent ? TransportHardware.playSize.height : TransportHardware.transportSize.height
    }

    private var rubberInset: CGFloat {
      prominent ? 3.6 : 3.1
    }
    private var lowerSeatWidth: CGFloat {
      buttonWidth * (prominent ? 0.46 : 0.44)
    }
    private var lowerSeatHeight: CGFloat {
      prominent ? 3.0 : 2.4
    }
    private var lowerSeatYOffset: CGFloat {
      (buttonHeight / 2) - rubberInset - (lowerSeatHeight / 2) - (prominent ? 2.2 : 2.0)
    }

    private var chromeOpacity: Double {
      if prominent { return hovering ? 0.56 : 0.48 }
      return hovering ? 0.46 : 0.38
    }

    private var rimOpacity: Double {
      if prominent { return hovering ? 0.32 : 0.24 }
      return hovering ? 0.25 : 0.17
    }

    private var iconGlowOpacity: Double {
      if prominent { return hovering ? 0.34 : 0.20 }
      return hovering ? 0.22 : 0.10
    }

    private var warmThemeLift: Double {
      theme.id == .ember ? 1.22 : 1
    }

    var body: some View {
      let pressed = configuration.isPressed

      ZStack {
        ZStack {
          hardwareBody(pressed: pressed)

          configuration.label
            .foregroundStyle(theme.accent)
            .shadow(color: theme.buttonGlow.opacity(iconGlowOpacity * warmThemeLift), radius: prominent ? 2 : 1)
            .frame(width: buttonWidth, height: buttonHeight)
            .allowsHitTesting(false)
        }
        .frame(width: buttonWidth, height: buttonHeight)
        .brightness(pressed ? -0.04 : 0)
        .scaleEffect(pressed ? 0.965 : 1.0)
        .offset(y: pressed ? 1 : 0)
      }
        .frame(width: slotWidth, height: slotHeight)
        .contentShape(Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .onDisappear { hovering = false }
    }

    private func hardwareBody(pressed: Bool) -> some View {
      ZStack {
        Capsule()
          .fill(LinearGradient(
            colors: [
              theme.buttonChrome.opacity(chromeOpacity),
              Color.white.opacity(prominent ? 0.10 : 0.07),
              theme.surface.opacity(prominent ? 0.58 : 0.66),
              Color.black.opacity(theme.id == .ember ? 0.18 : 0.22),
            ],
            startPoint: .top,
            endPoint: .bottom))
          .overlay(
            Capsule()
              .stroke(Color.white.opacity(min(0.56, rimOpacity * warmThemeLift)), lineWidth: prominent ? 0.9 : 0.7)
          )
          .overlay(
            Capsule()
              .stroke(Color.black.opacity(0.34), lineWidth: 1.4)
              .blur(radius: 0.7)
              .offset(y: 0.6)
              .mask(Capsule())
          )
          .shadow(color: Color.black.opacity(pressed ? 0.12 : 0.26), radius: pressed ? 0.4 : 1.4, x: 0, y: pressed ? 0.2 : 0.9)

        Capsule()
          .inset(by: rubberInset)
          .fill(LinearGradient(
            colors: [
              Color.white.opacity(hovering ? 0.10 : 0.065),
              theme.surface.opacity(prominent ? 0.82 : 0.88),
              theme.ground.opacity(prominent ? 0.82 : 0.88),
            ],
            startPoint: .top,
            endPoint: .bottom))
          .overlay(
            Capsule()
              .inset(by: rubberInset)
              .stroke(theme.buttonRubber.opacity((prominent ? 0.34 : 0.24) * warmThemeLift), lineWidth: prominent ? 1.0 : 0.8)
          )

        Capsule()
          .fill(theme.buttonGlow.opacity((prominent ? 0.13 : 0.095) * warmThemeLift))
          .frame(width: lowerSeatWidth, height: lowerSeatHeight)
          .blur(radius: 0.45)
          .offset(y: lowerSeatYOffset)
          .allowsHitTesting(false)

        DialHardwareImage(name: prominent ? "transport-button-play" : "transport-button")
          .opacity(pressed ? 0.14 : 0.24)
          .frame(width: buttonWidth, height: buttonHeight)
          .allowsHitTesting(false)

        Capsule()
          .fill(Color.white.opacity(pressed ? 0.025 : (hovering ? 0.11 : 0.07)))
          .frame(width: buttonWidth * (prominent ? 0.46 : 0.40), height: prominent ? 2.2 : 1.8)
          .padding(.top, 3.5)
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
  }
}

private struct ToyUtilityStyle: ButtonStyle {
  var active: Bool

  func makeBody(configuration: Configuration) -> some View {
    UtilityButtonView(configuration: configuration, active: active)
  }

  private struct UtilityButtonView: View {
    let configuration: ButtonStyle.Configuration
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dialTheme) private var theme
    @State private var hovering = false

    var body: some View {
      let pressed = configuration.isPressed
      configuration.label
        .frame(width: TransportHardware.utilitySize.width,
               height: TransportHardware.utilitySize.height)
        .contentShape(Capsule())
        .background {
          Capsule()
            .fill(LinearGradient(
              colors: [
                theme.accent.opacity(active ? 0.045 : 0.0),
                Color.black.opacity(active ? 0.10 : 0.05),
              ],
              startPoint: .top,
              endPoint: .bottom))
            .overlay(
              Capsule()
                .stroke(Color.white.opacity(hovering || active ? 0.11 : 0.04), lineWidth: 0.6)
            )
            .overlay(
              Capsule()
                .stroke(Color.black.opacity(0.22), lineWidth: 1.4)
                .blur(radius: 0.8)
                .offset(y: 0.7)
                .mask(Capsule())
            )
        }
        .overlay {
          if active {
            Capsule()
              .inset(by: 3)
              .stroke(theme.accent.opacity(0.24), lineWidth: 0.7)
              .allowsHitTesting(false)
          }
        }
        .opacity(pressed ? 0.82 : 1)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
  }
}
