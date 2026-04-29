import SwiftUI
import AppKit

struct ConnectSetupView: View {
  @Binding var showingGlossary: Bool
  let onConnect: () -> Void
  let onOpenSettings: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dialTheme) private var theme
  @State private var appeared = false

  var body: some View {
    VStack(spacing: 0) {
      setupRail

      if showingGlossary {
        GlossaryPanel()
          .transition(.opacity.combined(with: .move(edge: .leading)))
      } else {
        VStack(alignment: .center, spacing: 10) {
          DialChromeWordmark()
            .frame(maxWidth: .infinity, alignment: .center)
            .modifier(SetupAppear(delay: 0.00))

          Text("Connect Spotify. Dial turns the songs that keep finding you into a pet, a room, and a private archive.")
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(3)
            .frame(width: 296)
            .modifier(SetupAppear(delay: 0.06))

          setupPreview
            .frame(width: 188)
            .modifier(SetupAppear(delay: 0.12))

          Button(action: onConnect) {
            HStack(spacing: 8) {
              DialIcon("music.note")
                .frame(width: 13, height: 13)
              Text("CONNECT SPOTIFY")
                .font(Dial.Typography.monoLabel)
                .tracking(1.25)
            }
            .foregroundStyle(Dial.Palette.ground)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.30), radius: 3, x: 0, y: 1.5)
          }
          .frame(width: 304)
          .buttonStyle(.pressable)
          .modifier(SetupAppear(delay: 0.18))

          Text("Secure OAuth. Token stays in Keychain.")
            .font(Dial.Typography.monoTiny)
            .tracking(0.55)
            .foregroundStyle(Dial.Palette.textMuted.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, alignment: .center)
            .modifier(SetupAppear(delay: 0.24))
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .onAppear { appeared = true }
  }

  private var setupRail: some View {
    HStack(spacing: Dial.Layout.StatusRail.spacing) {
      Circle()
        .fill(theme.accent)
        .frame(width: Dial.Layout.StatusRail.ledSize, height: Dial.Layout.StatusRail.ledSize)
        .shadow(color: theme.accent.opacity(0.55), radius: 3)
      Text("SETUP")
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.accent)
      Spacer()
      Button(action: onOpenSettings) {
        railIcon("gearshape.fill")
      }
      .buttonStyle(.pressable)
      .help("Open Settings")
      .accessibilityLabel("Open Settings")
      Button {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
          showingGlossary.toggle()
        }
      } label: {
        railIcon(showingGlossary ? "xmark.circle" : "info.circle")
      }
      .buttonStyle(.pressable)
      .help(showingGlossary ? "Hide glossary" : "What do these badges mean?")
      .accessibilityLabel(showingGlossary ? "Hide glossary" : "Show badge glossary")
    }
    .padding(.horizontal, Dial.Layout.StatusRail.horizontalPadding)
    .padding(.vertical, Dial.Layout.StatusRail.verticalPadding)
  }

  private var setupPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .fill(theme.lcd)

      LCDScanlines(pitch: 3, opacity: 0.08, color: .black)
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))

      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height

        RoomObjectSprite(name: "rug", color: Color.black.opacity(0.72), size: 58)
          .position(x: w * 0.50, y: h * 0.80)
        RoomObjectSprite(name: "shelf", color: Color.black.opacity(0.78), size: 40)
          .position(x: w * 0.32, y: h * 0.30)
        RoomObjectSprite(name: "window", color: Color.black.opacity(0.82), size: 32)
          .position(x: w * 0.72, y: h * 0.28)
        RoomObjectSprite(name: "mcm_hifi_console", color: Color.black.opacity(0.78), size: 44)
          .position(x: w * 0.73, y: h * 0.72)

        BulldogSprite(stage: .hatchling, behavior: .walk, height: 62)
          .frame(width: 70, height: 70)
          .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
          .position(x: w * 0.50, y: h * 0.58)
      }
      .padding(8)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 104)
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous),
      fill: theme.lcd,
      edgeOpacity: 0.36,
      fillTopOpacity: 0.07,
      fillBottomOpacity: 0.025,
      sheenOpacity: 0.36,
      sheenLineWidth: 0.9,
      contactShadowOpacity: 0,
      innerShadowOpacity: 0.20)
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous)
        .inset(by: 4)
        .stroke(theme.accent.opacity(0.22), lineWidth: 0.7)
    )
    .shadow(color: Color.black.opacity(0.42), radius: 5, x: 0, y: 2)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.36).delay(0.18), value: appeared)
  }

  private func railIcon(_ name: String) -> some View {
    DialIcon(name)
      .frame(width: Dial.Layout.StatusRail.iconSize, height: Dial.Layout.StatusRail.iconSize)
      .foregroundStyle(theme.textMuted)
      .frame(width: Dial.Layout.StatusRail.hitSize, height: Dial.Layout.StatusRail.hitSize)
      .contentShape(Rectangle())
  }
}

private struct DialChromeWordmark: View {
  var body: some View {
    Group {
      if let image = Self.image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .antialiased(true)
          .scaledToFit()
      } else {
        Text("DIAL")
          .font(.custom("GeistPixel-Square", size: 42))
          .tracking(2.0)
          .foregroundStyle(Dial.Palette.textPrimary)
          .lineLimit(1)
      }
    }
    .frame(width: 224, height: 49)
    .shadow(color: Color.black.opacity(0.50), radius: 1.4, x: 0, y: 1.0)
    .accessibilityLabel("Dial")
  }

  private static let image: NSImage? = {
    if let url = Bundle.main.url(forResource: "dial-wordmark-chrome", withExtension: "png", subdirectory: "Brand") {
      return NSImage(contentsOf: url)
    }
    if let url = Bundle.main.url(forResource: "dial-wordmark-chrome", withExtension: "png") {
      return NSImage(contentsOf: url)
    }
    return nil
  }()
}

private struct SetupAppear: ViewModifier {
  let delay: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  func body(content: Content) -> some View {
    content
      .opacity(appeared || reduceMotion ? 1 : 0)
      .offset(y: appeared || reduceMotion ? 0 : 8)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.32).delay(delay), value: appeared)
      .onAppear { appeared = true }
  }
}
