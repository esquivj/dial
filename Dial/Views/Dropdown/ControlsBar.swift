import SwiftUI

struct ControlsBar: View {
  @Bindable var menubar: MenubarStripViewModel
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
        Button {
          Task {
            if menubar.state == .playing {
              try? await client.pause()
            } else {
              try? await client.play()
            }
          }
        } label: {
          Image(systemName: menubar.state == .playing ? "pause.fill" : "play.fill")
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
        Rectangle().fill(Dial.Palette.muted.opacity(0.4)).frame(width: 1, height: 10)
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
    .background(Dial.Palette.subtle)
    .overlay(alignment: .top) {
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
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
