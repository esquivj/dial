import SwiftUI

/// Modal shown on first launch (until a Spotify token exists in the keychain).
/// `onConnect` is called when the user taps the connect button — DialApp wires
/// it to `SpotifyAuthService.signIn()` and dismisses the window on success.
struct OnboardingView: View {
  let onConnect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Welcome to Dial")
        .font(.title)
        .foregroundStyle(Dial.Palette.ivory)
      Text("""
      Dial is a menubar companion for Spotify. It shows what you're playing, what it is to *you*, \
      and tends a tiny pixel pet that grows as you listen.
      """)
      .font(Dial.Typography.sansBody)
      .foregroundStyle(Dial.Palette.muted)

      Button("Connect Spotify") { onConnect() }
        .controlSize(.large)

      Text("""
      Want richer badges day one? Request your Spotify Extended Streaming History — \
      it arrives in 5–30 days. Drop the folder on Settings when it does.
      """)
      .font(Dial.Typography.sansCaption)
      .foregroundStyle(Dial.Palette.muted)
    }
    .padding(24)
    .frame(width: 440, height: 300)
    .background(Dial.Palette.ground)
  }
}
