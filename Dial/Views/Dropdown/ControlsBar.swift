import SwiftUI

struct ControlsBar: View {
  let client: SpotifyClient

  var body: some View {
    HStack {
      HStack(spacing: 14) {
        Button { Task { try? await client.prev() } } label: {
          Image(systemName: "backward.fill")
        }.buttonStyle(.plain)
        Button { Task { try? await client.pause() } } label: {
          Image(systemName: "pause.fill")
        }.buttonStyle(.plain)
        Button { Task { try? await client.next() } } label: {
          Image(systemName: "forward.fill")
        }.buttonStyle(.plain)
      }
      .foregroundStyle(Dial.Palette.ivory)
      Spacer()
      HStack(spacing: 10) {
        Text("HISTORY")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.muted)
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 10)
        Text("STATS")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.muted)
      }
    }
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .background(Color(red: 0.055, green: 0.059, blue: 0.071))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
  }
}
