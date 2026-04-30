import SwiftUI

/// Modal shown on first launch (until a Spotify token exists in the keychain).
/// `onConnect` is called when the user taps the connect button — DialApp wires
/// it to `SpotifyAuthService.signIn()` and dismisses the window on success.
struct OnboardingView: View {
  let onConnect: () -> Void
  private let theme = DialTheme.classic

  var body: some View {
    HStack(spacing: 22) {
      devicePreview

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Dial")
            .font(.custom("GeistPixel-Square", size: 32))
            .foregroundStyle(theme.accent)
          Text("Now playing, remembered.")
            .font(Dial.Typography.sansBody)
            .foregroundStyle(theme.textPrimary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
        }

        Text("Connect Spotify and Dial turns first listens, rediscoveries, streaks, and milestones into badges, a pet, and artifacts.")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        Button("Connect Spotify") { onConnect() }
          .controlSize(.large)
          .tint(theme.accent)

        Text("For richer badges, import your Spotify Extended Streaming History later from Settings.")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textMuted.opacity(0.78))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(24)
    .frame(width: 500, height: 300)
    .tint(theme.accent)
    .background(theme.ground)
  }

  private var devicePreview: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Circle()
          .fill(theme.accent)
          .frame(width: 6, height: 6)
          .shadow(color: theme.accent.opacity(0.55), radius: 3)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(theme.accent)
      }

      RoundedRectangle(cornerRadius: Dial.Radius.media)
        .fill(theme.surface)
        .frame(width: 72, height: 72)
        .dialMediaFrame(shape: RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous))

      HStack(spacing: 6) {
        BadgePixelIcon(kind: .rediscovered, color: theme.accent, size: 14)
        Text("REDISCOVERED")
          .font(Dial.Typography.monoLabel)
          .tracking(1.2)
          .foregroundStyle(theme.accent)
      }
      .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
      .dialPrintedChip(
        shape: RoundedRectangle(cornerRadius: Dial.Radius.printed, style: .continuous),
        color: theme.accent)

      BulldogSprite(stage: .hatchling, behavior: .walk, height: 39)
        .frame(width: 52, height: 52)
        .dialRaisedGel(
          shape: RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous),
          fill: theme.lcd,
          edgeOpacity: 0.34,
          fillTopOpacity: 0.07,
          fillBottomOpacity: 0.025,
          sheenOpacity: 0.42,
          contactShadowOpacity: 0,
          innerShadowOpacity: 0.20)
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.tiny)
            .inset(by: 3)
            .stroke(theme.accent.opacity(0.24), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
    }
    .padding(14)
    .frame(width: 150, height: 226, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: Dial.Radius.device)
        .fill(theme.ground)
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.device)
            .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
        )
    )
  }
}
