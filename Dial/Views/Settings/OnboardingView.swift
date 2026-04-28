import SwiftUI

/// Modal shown on first launch (until a Spotify token exists in the keychain).
/// `onConnect` is called when the user taps the connect button — DialApp wires
/// it to `SpotifyAuthService.signIn()` and dismisses the window on success.
struct OnboardingView: View {
  let onConnect: () -> Void

  var body: some View {
    HStack(spacing: 22) {
      devicePreview

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Dial")
            .font(.custom("IBMPlexMono-Medium", size: 32))
            .foregroundStyle(Dial.Palette.accent)
          Text("A personal Spotify HUD for the songs that mean something to you.")
            .font(Dial.Typography.sansBody)
            .foregroundStyle(Dial.Palette.textPrimary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
        }

        Text("Badges mark first listens, rediscoveries, streaks, and milestones. The pixel companion grows as your listening history fills in.")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textMuted)
          .fixedSize(horizontal: false, vertical: true)

        Button("Connect Spotify") { onConnect() }
          .controlSize(.large)
          .tint(Dial.Palette.accent)

        Text("For richer badges, import your Spotify Extended Streaming History later from Settings.")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.78))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(24)
    .frame(width: 500, height: 300)
    .background(Dial.Palette.ground)
  }

  private var devicePreview: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Circle()
          .fill(Dial.Palette.accent)
          .frame(width: 6, height: 6)
          .shadow(color: Dial.Palette.accent.opacity(0.55), radius: 3)
        Text("NOW PLAYING")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.accent)
      }

      RoundedRectangle(cornerRadius: 6)
        .fill(Dial.Palette.surface)
        .frame(width: 72, height: 72)
        .dialMediaFrame(shape: RoundedRectangle(cornerRadius: 6, style: .continuous))

      HStack(spacing: 6) {
        BadgePixelIcon(kind: .rediscovered, color: Dial.Palette.accent, size: 14)
        Text("REDISCOVERED")
          .font(Dial.Typography.monoLabel)
          .tracking(1.2)
          .foregroundStyle(Dial.Palette.accent)
      }
      .padding(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 8))
      .dialPrintedChip(
        shape: RoundedRectangle(cornerRadius: 3, style: .continuous),
        color: Dial.Palette.accent)

      BulldogSprite(stage: .hatchling, behavior: .walk, height: 39)
        .frame(width: 52, height: 52)
        .dialRaisedGel(
          shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
          fill: Dial.Palette.lcd,
          edgeOpacity: 0.34,
          fillTopOpacity: 0.07,
          fillBottomOpacity: 0.025,
          sheenOpacity: 0.42,
          contactShadowOpacity: 0,
          innerShadowOpacity: 0.20)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .inset(by: 3)
            .stroke(Dial.Palette.accent.opacity(0.24), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
    }
    .padding(14)
    .frame(width: 150, height: 226, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 26)
        .fill(Dial.Palette.ground)
        .overlay(
          RoundedRectangle(cornerRadius: 26)
            .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
        )
    )
  }
}
