import SwiftUI

struct ControlsBar: View {
  let client: SpotifyClient

  var body: some View {
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
      Spacer()
    }
    .foregroundStyle(Dial.Palette.ivory)
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .background(Color(red: 0.055, green: 0.059, blue: 0.071))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
  }
}
