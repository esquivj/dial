import SwiftUI

struct ControlsBar: View {
  let client: SpotifyClient
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void

  var body: some View {
    HStack {
      HStack(spacing: 14) {
        Button { Task { try? await client.prev() } } label: {
          Image(systemName: "backward.fill")
        }
        .buttonStyle(HoverableTransportButtonStyle())
        .modifier(HoverDimModifier())
        Button { Task { try? await client.pause() } } label: {
          Image(systemName: "pause.fill")
        }
        .buttonStyle(HoverableTransportButtonStyle())
        .modifier(HoverDimModifier())
        Button { Task { try? await client.next() } } label: {
          Image(systemName: "forward.fill")
        }
        .buttonStyle(HoverableTransportButtonStyle())
        .modifier(HoverDimModifier())
      }
      .foregroundStyle(Dial.Palette.ivory)
      Spacer()
      HStack(spacing: 10) {
        Button(action: onOpenHistory) {
          Text("HISTORY")
            .font(Dial.Typography.monoLabel)
            .tracking(1.4)
            .foregroundStyle(Dial.Palette.muted)
        }
        .buttonStyle(.plain)
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 10)
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
    .background(Color(red: 0.055, green: 0.059, blue: 0.071))
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
    }
  }
}

private struct HoverableTransportButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.55 : 1)
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct HoverDimModifier: ViewModifier {
  @State private var hover = false
  func body(content: Content) -> some View {
    content
      .opacity(hover ? 1 : 0.78)
      .onHover { hover = $0 }
  }
}
