import SwiftUI

struct LikedTrackButton: View {
  @Bindable var menubar: MenubarStripViewModel
  let client: SpotifyClient
  let onReconnect: () async throws -> Void

  var body: some View {
    Button {
      toggleLiked()
    } label: {
      DialThickIcon(likedSymbol, size: 14, weight: 0.45)
        .foregroundStyle(likedColor)
        .frame(width: 22, height: 22)
        .dialRaisedGel(
          shape: RoundedRectangle(cornerRadius: 4, style: .continuous),
          fill: buttonFill,
          edgeOpacity: borderOpacity,
          fillTopOpacity: 0.075,
          fillBottomOpacity: 0.02,
          sheenOpacity: 0.30,
          sheenLineWidth: 0.55,
          contactShadowOpacity: 0.20,
          contactShadowRadius: 1.5,
          contactShadowY: 0.75,
          innerShadowOpacity: 0.08)
        .padding(9)
        .contentShape(Rectangle())
        .padding(-9)
        .opacity(menubar.likedTrackState == .checking ? 0.45 : 1)
    }
    .buttonStyle(.pressable)
    .disabled(!canToggleLiked)
    .help(likedHelp)
    .accessibilityLabel(likedAccessibilityLabel)
  }

  private var canToggleLiked: Bool {
    menubar.hasLibraryTrack && menubar.likedTrackState != .checking
  }

  private var likedSymbol: String {
    switch menubar.likedTrackState {
    case .liked:
      return "heart.fill"
    case .needsReconnect:
      return "heart.slash"
    case .checking,
         .notLiked,
         .unknown:
      return "heart"
    }
  }

  private var likedColor: Color {
    switch menubar.likedTrackState {
    case .liked:          return Dial.Palette.accentAlt
    case .checking:       return Dial.Palette.accent
    case .needsReconnect: return Dial.Palette.accentAlt.opacity(0.55)
    case .notLiked,
         .unknown:        return Dial.Palette.textMuted
    }
  }

  private var buttonFill: Color {
    switch menubar.likedTrackState {
    case .liked:
      return Dial.Palette.accentAlt.opacity(0.035)
    case .checking:
      return Dial.Palette.accent.opacity(0.025)
    case .needsReconnect:
      return Dial.Palette.accentAlt.opacity(0.02)
    case .notLiked,
         .unknown:
      return Dial.Palette.surface.opacity(0.24)
    }
  }

  private var borderOpacity: Double {
    switch menubar.likedTrackState {
    case .liked:          return 0.34
    case .checking:       return 0.26
    case .needsReconnect: return 0.22
    case .notLiked,
         .unknown:        return 0.20
    }
  }

  private var likedHelp: String {
    switch menubar.likedTrackState {
    case .liked:          return "Remove from Liked Songs"
    case .notLiked:       return "Add to Liked Songs"
    case .checking:       return "Checking Liked Songs"
    case .needsReconnect: return "Reconnect Spotify to enable Liked Songs"
    case .unknown:        return menubar.hasLibraryTrack ? "Add to Liked Songs" : "No track to like"
    }
  }

  private var likedAccessibilityLabel: String {
    switch menubar.likedTrackState {
    case .liked:          return "Remove current track from Liked Songs"
    case .notLiked:       return "Add current track to Liked Songs"
    case .checking:       return "Checking whether current track is in Liked Songs"
    case .needsReconnect: return "Reconnect Spotify to enable Liked Songs"
    case .unknown:        return "Add current track to Liked Songs"
    }
  }

  private func toggleLiked() {
    guard let uri = menubar.track?.uri, canToggleLiked else { return }
    let previous = menubar.likedTrackState

    if previous == .needsReconnect {
      menubar.likedTrackState = .checking
      Task {
        do {
          try await onReconnect()
          let sameTrack = await MainActor.run { menubar.track?.uri == uri }
          guard sameTrack else { return }
          await writeLikedState(uri: uri, shouldLike: true, previous: .notLiked)
        } catch {
          await MainActor.run {
            guard menubar.track?.uri == uri else { return }
            menubar.likedTrackState = .needsReconnect
          }
        }
      }
      return
    }

    let shouldLike = previous != .liked
    menubar.likedTrackState = shouldLike ? .liked : .notLiked

    Task {
      await writeLikedState(uri: uri, shouldLike: shouldLike, previous: previous)
    }
  }

  private func writeLikedState(uri: String, shouldLike: Bool, previous: LikedTrackState) async {
    do {
      if shouldLike {
        try await client.saveToLibrary(uri: uri)
      } else {
        try await client.removeFromLibrary(uri: uri)
      }
      let confirmed = try await client.libraryContains(uri: uri)
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = confirmed ? .liked : .notLiked
      }
    } catch SpotifyAPIError.httpStatus(403) {
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = .needsReconnect
      }
    } catch {
      await MainActor.run {
        guard menubar.track?.uri == uri else { return }
        menubar.likedTrackState = previous
      }
    }
  }
}
