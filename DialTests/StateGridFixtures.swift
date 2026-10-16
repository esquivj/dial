import AppKit
import SwiftUI
@testable import Dial

/// One cell of the state grid (`scripts/dev.sh grid`). Not a regression
/// baseline: the grid exists so a human can eyeball every HUD and menu bar
/// state side by side before and after a polish change.
struct HUDGridState {
  let name: String
  let caption: String
  let section: String
  var themeID: DialThemeID = .classic
  var reduceMotion = false
  /// ImageRenderer draws ScrollView content blank; render these through a
  /// real NSHostingView in an offscreen window instead.
  var needsHostingView = false
  let configure: @MainActor (AppCoordinator, StateGridFixtures) -> Void
}

struct MenubarGridState {
  let name: String
  let caption: String
  let mode: MenuBarDisplayMode
  var themeID: DialThemeID = .classic
  var reduceMotion = false
  let configure: @MainActor (AppCoordinator, StateGridFixtures) -> Void
}

/// Shared fixture data for the grid. Artwork is a generated local PNG so
/// renders never touch the network.
struct StateGridFixtures {
  let artworkURL: String
  let now: Int64

  static let longTitle = "Everything In Its Right Place (Live at the Hollywood Bowl, 2001) [Remastered Extended Version]"
  static let longArtist = "Florence + The Machine, Kendrick Lamar & The Weeknd feat. Charlotte Gainsbourg"
  static let longAlbum = "The Very Long Deluxe Anniversary Edition: Collected Recordings 1998–2024 (Expanded)"

  func track(
    name: String = "Signal Drift",
    artist: String = "Dial Test",
    album: String = "Hardware Memory",
    withArt: Bool = true
  ) -> NowPlayingViewModel.Track {
    NowPlayingViewModel.Track(
      uri: "spotify:track:state-grid-\(abs(name.hashValue))",
      name: name,
      artistName: artist,
      artistUri: "spotify:artist:state-grid",
      artistUris: ["spotify:artist:state-grid"],
      albumName: album,
      artUrl: withArt ? artworkURL : nil)
  }

  @MainActor
  func signIn(_ coord: AppCoordinator, themeID: DialThemeID) {
    coord.settings.signedIn = true
    coord.settings.showReadoutsInHUD = true
    coord.settings.showBadgesInHUD = true
    coord.settings.showVisualizerInHUD = true
    coord.settings.showTransportInHUD = true
    coord.settings.showPetInHUD = true
    coord.settings.petEnabled = true
    coord.settings.animationLevel = .low
    coord.settings.hudColorMode = HUDColorMode(rawValue: themeID.rawValue) ?? .classic
    coord.dropdownScreen = .hud
  }

  @MainActor
  func play(
    _ coord: AppCoordinator,
    track: NowPlayingViewModel.Track,
    state: MenubarDisplayState = .playing,
    plays: Int = 27,
    rank: Int? = 7,
    lastPlayedDaysAgo: Int? = 3,
    badge: BadgeInsight? = BadgeInsight(kind: .deepCut, detail: "DEEP CUT", explanation: "A rare track in this listener's rotation.")
  ) {
    coord.nowPlaying.track = track
    coord.nowPlaying.playsYTD = plays
    coord.aggCache.rank7d = rank
    coord.aggCache.lastPlayedAt = lastPlayedDaysAgo.map { now - Int64($0) * 86_400 }
    coord.aggCache.firstListen = false
    coord.aggCache.currentBadgeInsight = badge
    coord.menubar.track = track
    coord.menubar.state = state
    coord.menubar.durationMs = 212_000
    coord.menubar.progressMs = 91_000
    coord.menubar.lastProgressUpdate = nil
    coord.menubar.likedTrackState = .notLiked
    coord.menubar.playsYTD = plays
    coord.pet.stage = .companion
    coord.pet.behavior = state == .playing ? .beatSync(bpm: 124) : .idle
    coord.pet.reactionText = "Listening."
    coord.visualizer.configure(style: .precise, density: .detailed, motion: .balanced, showPeakMarkers: true)
    coord.visualizer.setPreviewSpectrum(bands: Self.spectrum)
  }

  @MainActor
  func nothingPlaying(_ coord: AppCoordinator) {
    coord.nowPlaying.track = nil
    coord.menubar.track = nil
    coord.menubar.state = .nothingPlaying
    coord.menubar.durationMs = 0
    coord.menubar.progressMs = 0
    coord.pet.behavior = .idle
  }

  @MainActor
  func emptyArchive(_ coord: AppCoordinator) {
    coord.cachedHistorySnapshot = HistoryViewSnapshot(rows: [], totalPlays: 0)
    coord.cachedStatsSnapshotYTD = StatsViewSnapshot(
      totals: .init(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0),
      topTracks: [],
      topArtists: [],
      topGenres: [],
      weeklyMemory: nil,
      rhythmBuckets: [],
      badgeSummaries: [],
      recentBadges: [])
    coord.cachedPetSnapshot = PetViewSnapshot(
      todayListeningMs: 0,
      recentBadgeCounts: [:],
      unlockedTricks: [],
      artifacts: [],
      weeklyMemory: nil,
      weeklyMemoryLog: [],
      petState: nil)
    coord.pet.stage = .egg
    coord.pet.xp = 0
    coord.pet.streakDays = 0
  }

  static let spectrum: [Float] = (0..<48).map { index in
    let base: [Float] = [0.64, 0.58, 0.72, 0.48, 0.55, 0.50, 0.46, 0.42]
    let decay = max(0.16, 1.0 - Float(index) * 0.016)
    return min(0.92, max(0.10, base[index % base.count] * decay))
  }

  /// Writes a 600×600 abstract cover to a temp file and returns its file URL.
  static func makeArtworkFile() throws -> URL {
    let size = 600
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw NSError(domain: "StateGrid", code: 1) }
    let colors = [
      CGColor(red: 0.95, green: 0.42, blue: 0.20, alpha: 1),
      CGColor(red: 0.36, green: 0.10, blue: 0.45, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
    ctx.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.75, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: 170, y: 170, width: 260, height: 260))
    ctx.setFillColor(CGColor(red: 0.12, green: 0.05, blue: 0.16, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 270, y: 270, width: 60, height: 60))
    guard let image = ctx.makeImage() else { throw NSError(domain: "StateGrid", code: 2) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dial-state-grid-cover.png")
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
    return url
  }
}

extension StateGridFixtures {
  static var hudStates: [HUDGridState] {
    var states: [HUDGridState] = []

    for theme in DialThemeID.allCases {
      states.append(.init(
        name: "hud-playing-\(theme.rawValue)",
        caption: "Playing · \(theme.gridLabel)",
        section: "Themes · playing",
        themeID: theme,
        configure: { coord, f in
          f.signIn(coord, themeID: theme)
          f.play(coord, track: f.track())
        }))
    }

    states += [
      .init(
        name: "hud-paused-classic",
        caption: "Paused",
        section: "Playback states",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track(), state: .paused)
        }),
      .init(
        name: "hud-idle-classic",
        caption: "Nothing playing / Spotify closed",
        section: "Playback states",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.nothingPlaying(coord)
        }),
      .init(
        name: "hud-idle-ember",
        caption: "Nothing playing · Magenta",
        section: "Playback states",
        themeID: .ember,
        configure: { coord, f in
          f.signIn(coord, themeID: .ember)
          f.nothingPlaying(coord)
        }),
      .init(
        name: "hud-idle-no-pet",
        caption: "Nothing playing · pet off",
        section: "Playback states",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          coord.settings.petEnabled = false
          f.nothingPlaying(coord)
        }),

      .init(
        name: "hud-signed-out-classic",
        caption: "Signed out (ConnectSetupView)",
        section: "Signed out / offline",
        configure: { coord, _ in
          coord.settings.signedIn = false
          coord.settings.hudColorMode = .classic
        }),
      .init(
        name: "hud-signed-out-aqua",
        caption: "Signed out · Aqua",
        section: "Signed out / offline",
        themeID: .aqua,
        configure: { coord, _ in
          coord.settings.signedIn = false
          coord.settings.hudColorMode = .aqua
        }),
      .init(
        name: "hud-offline-reconnect",
        caption: "API error: likes need reconnect + visualizer offline",
        section: "Signed out / offline",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track())
          coord.menubar.likedTrackState = .needsReconnect
          coord.visualizer.setPreviewState(.error)
        }),
      .init(
        name: "hud-no-artwork",
        caption: "Artwork failed to load",
        section: "Signed out / offline",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track(withArt: false))
        }),

      .init(
        name: "hud-first-run-idle",
        caption: "First run: empty DB, no Screen Recording",
        section: "First run / empty archive",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.emptyArchive(coord)
          f.nothingPlaying(coord)
          coord.visualizer.setPreviewState(.denied)
        }),
      .init(
        name: "hud-first-run-playing",
        caption: "First run: first play, no history",
        section: "First run / empty archive",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.emptyArchive(coord)
          f.play(coord, track: f.track(), plays: 0, rank: nil, lastPlayedDaysAgo: nil,
                 badge: BadgeInsight(kind: .firstListen, detail: "FIRST LISTEN", explanation: "First time Dial has seen this track."))
          coord.aggCache.firstListen = true
          coord.pet.stage = .egg
          coord.visualizer.setPreviewState(.denied)
        }),
      .init(
        name: "history-empty",
        caption: "History · empty archive",
        section: "First run / empty archive",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.emptyArchive(coord)
          coord.dropdownScreen = .history
        }),
      .init(
        name: "stats-empty",
        caption: "Stats · empty archive",
        section: "First run / empty archive",
        needsHostingView: true,
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.emptyArchive(coord)
          coord.dropdownScreen = .stats
        }),
      .init(
        name: "pet-empty",
        caption: "Pet · egg, empty archive",
        section: "First run / empty archive",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.emptyArchive(coord)
          coord.dropdownScreen = .pet
        }),

      .init(
        name: "hud-long-classic",
        caption: "Long title / artist / album + big numbers",
        section: "Long text",
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track(name: longTitle, artist: longArtist, album: longAlbum),
                 plays: 12_345, rank: 128, lastPlayedDaysAgo: 400,
                 badge: BadgeInsight(kind: .anniversary, detail: "ANNIVERSARY", explanation: "One year since the first play."))
          coord.aggCache.albumPlaysYTD = 48_200
        }),
      .init(
        name: "hud-long-aqua",
        caption: "Long text · Aqua",
        section: "Long text",
        themeID: .aqua,
        configure: { coord, f in
          f.signIn(coord, themeID: .aqua)
          f.play(coord, track: f.track(name: longTitle, artist: longArtist, album: longAlbum),
                 plays: 12_345, rank: 128, lastPlayedDaysAgo: 400,
                 badge: BadgeInsight(kind: .rediscovered, detail: "REDISCOVERED", explanation: "Back after a long gap."))
        }),

      .init(
        name: "hud-reduce-motion-playing",
        caption: "Reduce Motion · playing",
        section: "Reduce Motion",
        reduceMotion: true,
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track())
        }),
      .init(
        name: "hud-reduce-motion-long",
        caption: "Reduce Motion · long text",
        section: "Reduce Motion",
        reduceMotion: true,
        configure: { coord, f in
          f.signIn(coord, themeID: .classic)
          f.play(coord, track: f.track(name: longTitle, artist: longArtist, album: longAlbum))
        }),
      .init(
        name: "hud-reduce-motion-signed-out",
        caption: "Reduce Motion · signed out",
        section: "Reduce Motion",
        reduceMotion: true,
        configure: { coord, _ in
          coord.settings.signedIn = false
          coord.settings.hudColorMode = .classic
        }),
    ]
    return states
  }

  static var menubarStates: [MenubarGridState] {
    [
      .init(name: "menubar-idle", caption: "Nothing playing", mode: .albumArtTrackArtist, configure: { coord, f in
        f.signIn(coord, themeID: .classic)
        f.nothingPlaying(coord)
      }),
      .init(name: "menubar-track-artist", caption: "Art + track • artist", mode: .albumArtTrackArtist, configure: { coord, f in
        f.signIn(coord, themeID: .classic)
        f.play(coord, track: f.track())
      }),
      .init(name: "menubar-paused", caption: "Paused", mode: .albumArtTrackArtist, configure: { coord, f in
        f.signIn(coord, themeID: .classic)
        f.play(coord, track: f.track(), state: .paused)
      }),
      .init(name: "menubar-long", caption: "Long track • artist", mode: .albumArtTrackArtist, configure: { coord, f in
        f.signIn(coord, themeID: .classic)
        f.play(coord, track: f.track(name: longTitle, artist: longArtist, album: longAlbum))
      }),
      .init(name: "menubar-long-reduce-motion", caption: "Long · Reduce Motion", mode: .albumArtTrackArtist, reduceMotion: true, configure: { coord, f in
        f.signIn(coord, themeID: .classic)
        f.play(coord, track: f.track(name: longTitle, artist: longArtist, album: longAlbum))
      }),
      .init(name: "menubar-title-plays", caption: "Title + plays · Magenta", mode: .titlePlayCount, themeID: .ember, configure: { coord, f in
        f.signIn(coord, themeID: .ember)
        f.play(coord, track: f.track(), plays: 1_234)
      }),
      .init(name: "menubar-pet-title", caption: "Pet + title · Slime", mode: .petTitle, themeID: .slime, configure: { coord, f in
        f.signIn(coord, themeID: .slime)
        f.play(coord, track: f.track())
      }),
      .init(name: "menubar-tiny-chaos", caption: "Tiny chaos · Aqua", mode: .tinyChaos, themeID: .aqua, configure: { coord, f in
        f.signIn(coord, themeID: .aqua)
        f.play(coord, track: f.track())
      }),
    ]
  }
}

extension DialThemeID {
  /// Display name, matching Settings (theme ids are not display names).
  var gridLabel: String {
    switch self {
    case .classic: "Smoke Gel (classic)"
    case .slime:   "Slime"
    case .aqua:    "Aqua"
    case .ember:   "Magenta (ember)"
    }
  }
}
