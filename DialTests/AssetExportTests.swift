import AppKit
import GRDB
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Dial

@MainActor
final class AssetExportTests: XCTestCase {
  func test_exportXReadyAssets() async throws {
    let triggerURL = URL(fileURLWithPath: "/tmp/dial-export-x-assets")
    guard ProcessInfo.processInfo.environment["DIAL_EXPORT_X_ASSETS"] == "1"
      || FileManager.default.fileExists(atPath: triggerURL.path)
    else {
      throw XCTSkip("Set DIAL_EXPORT_X_ASSETS=1 or create /tmp/dial-export-x-assets to export marketing assets.")
    }

    let outputURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DIAL_X_ASSET_DIR"]
      ?? "/path/to/dial/MarketingAssets/XReady")
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try writePhilosophy(to: outputURL.appendingPathComponent("dial-x-asset-direction.md"))

    let context = try await makeContext()
    let hud = DropdownView(coord: context.coord, visibility: context.visibility)
      .preferredColorScheme(.dark)
    let trackCard = ShowcaseTrackCard(context: context)
      .preferredColorScheme(.dark)
    let petSticker = ShowcasePetSticker(pet: context.coord.pet)
      .preferredColorScheme(.dark)

    try export(hud, size: CGSize(width: DropdownLayout.width, height: DropdownLayout.height),
               to: outputURL.appendingPathComponent("dial-hud-transparent.png"))
    try export(trackCard, size: CGSize(width: 342, height: 142),
               to: outputURL.appendingPathComponent("dial-track-card-transparent.png"))
    try export(petSticker, size: CGSize(width: 180, height: 180),
               to: outputURL.appendingPathComponent("dial-pet-sticker-transparent.png"))

    try export(ShowcaseXHero(context: context, transparent: false), size: CGSize(width: 1600, height: 900),
               to: outputURL.appendingPathComponent("dial-x-hero-1600x900.png"))
    try export(ShowcaseXHero(context: context, transparent: true), size: CGSize(width: 1600, height: 900),
               to: outputURL.appendingPathComponent("dial-x-hero-transparent-1600x900.png"))
    try export(ShowcaseXSquare(context: context), size: CGSize(width: 1200, height: 1200),
               to: outputURL.appendingPathComponent("dial-x-square-1200.png"))
  }

  private func makeContext() async throws -> ShowcaseContext {
    let dbURL = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support/Dial/dial.sqlite")
    let dbq = try DatabaseQueue(path: dbURL.path)
    let tokenStore = ExportTokenStore()
    let auth = SpotifyAuthService(clientID: "asset-export", tokenStore: tokenStore)
    let client = SpotifyClient(tokenStore: tokenStore, refresh: { try tokenStore.requireToken() })
    let coord = AppCoordinator(dbq: dbq, client: client, auth: auth, tokenStore: tokenStore)
    let track = try fetchShowcaseTrack(dbq: dbq)

    coord.settings.signedIn = true
    coord.settings.showReadoutsInHUD = true
    coord.settings.showBadgesInHUD = true
    coord.settings.showVisualizerInHUD = true
    coord.settings.showTransportInHUD = true
    coord.settings.showPetInHUD = true
    coord.settings.animationLevel = .low
    coord.dropdownScreen = .hud

    coord.nowPlaying.track = track.viewModel
    coord.menubar.track = track.viewModel
    coord.menubar.state = .playing
    coord.menubar.durationMs = track.durationMs
    coord.menubar.progressMs = min(max(80_000, track.durationMs / 2), max(0, track.durationMs - 15_000))
    coord.menubar.lastProgressUpdate = nil
    coord.menubar.likedTrackState = .notLiked
    coord.pet.stage = .companion
    coord.pet.behavior = .beatSync(bpm: 122)
    coord.pet.reactionText = "Listening."

    coord.aggCache.refresh(trackUri: track.viewModel.uri, artistUri: track.viewModel.artistUri, currentPlayAt: nil)
    if coord.aggCache.currentBadgeInsight == nil {
      coord.aggCache.currentBadgeInsight = BadgeInsight(
        kind: .deepCut,
        detail: "Personal catalog signal",
        explanation: "Showcase state for asset export.")
    }
    coord.nowPlaying.playsYTD = max(coord.aggCache.playsYTD, 5)
    coord.menubar.playsYTD = coord.nowPlaying.playsYTD

    let bands: [Float] = [
      0.88, 0.95, 0.91, 0.78, 0.72, 0.83, 0.68, 0.58,
      0.55, 0.62, 0.48, 0.45, 0.52, 0.44, 0.50, 0.46,
      0.42, 0.47, 0.41, 0.44, 0.40, 0.39, 0.42, 0.38,
      0.36, 0.34, 0.31, 0.35, 0.33, 0.30, 0.32, 0.29,
      0.27, 0.28, 0.26, 0.24, 0.25, 0.23, 0.22, 0.21,
      0.20, 0.22, 0.19, 0.18, 0.20, 0.17, 0.16, 0.18,
    ]
    coord.visualizer.configure(style: .precise, density: .detailed, motion: .balanced, showPeakMarkers: true)
    coord.visualizer.setPreviewSpectrum(bands: bands)

    if let artURL = track.viewModel.artUrl {
      _ = await coord.artworkCache.load(artURL)
    }

    let visibility = DropdownVisibility()
    visibility.isVisible = true
    return ShowcaseContext(coord: coord, visibility: visibility)
  }

  private func fetchShowcaseTrack(dbq: DatabaseQueue) throws -> ExportTrack {
    try dbq.read { db in
      let row = try Row.fetchOne(db, sql: """
        SELECT p.track_uri AS uri,
               COALESCE(t.name, p.track_uri) AS name,
               COALESCE(
                 CASE WHEN json_valid(t.artists_json) = 1 THEN json_extract(t.artists_json, '$[0].name') END,
                 'Unknown Artist'
               ) AS artist_name,
               CASE WHEN json_valid(t.artists_json) = 1 THEN json_extract(t.artists_json, '$[0].uri') END AS artist_uri,
               COALESCE(t.album_name, '') AS album_name,
               t.album_art_url AS album_art_url,
               COALESCE(t.duration_ms, 210000) AS duration_ms
        FROM plays p
        LEFT JOIN tracks t ON t.uri = p.track_uri
        WHERE t.album_art_url IS NOT NULL
          AND t.album_art_url != ''
          AND t.name IS NOT NULL
        ORDER BY p.played_at DESC, p.id DESC
        LIMIT 1
        """)

      guard let row else {
        return ExportTrack(
          viewModel: .init(
            uri: "spotify:track:asset-preview",
            name: "Private Frequency",
            artistName: "Dial",
            artistUri: nil,
            albumName: "Listening Memory",
            artUrl: nil),
          durationMs: 211_000)
      }

      return ExportTrack(
        viewModel: .init(
          uri: row["uri"],
          name: row["name"],
          artistName: row["artist_name"],
          artistUri: row["artist_uri"],
          albumName: row["album_name"],
          artUrl: row["album_art_url"]),
        durationMs: row["duration_ms"])
    }
  }

  private func export<V: View>(_ view: V, size: CGSize, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 2
    renderer.isOpaque = false
    guard let cgImage = renderer.cgImage else {
      throw NSError(domain: "Dial.AssetExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(url.lastPathComponent)"])
    }
    try writePNG(cgImage, to: url)
  }

  private func writePNG(_ cgImage: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    ) else {
      throw NSError(domain: "Dial.AssetExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create \(url.path)"])
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "Dial.AssetExport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not write \(url.path)"])
    }
  }

  private func writePhilosophy(to url: URL) throws {
    let text = """
    # Pocket Shrine

    Dial assets should feel like a tiny private music device photographed for the internet: plastic, LCD glow, pixel companion, and listening memory as the emotional center. The work is not a SaaS promo. It is a personal object made presentable.

    The visual system is built from real interface components first. Screenshots should keep their transparent corners and physical silhouette, then social compositions can wrap them in dark negative space, cyan readouts, and restrained magenta accents.

    Typography stays sparse: DIAL, PRIVATE MUSIC MEMORY, NOW PLAYING, LISTENING HISTORY. No paragraph marketing copy. The app itself carries the idea.

    Craft rule: every exported image should look hand-placed, crisp at 2x, and immediately usable on X without a cleanup pass.
    """
    try text.write(to: url, atomically: true, encoding: .utf8)
  }
}

private struct ShowcaseContext {
  let coord: AppCoordinator
  let visibility: DropdownVisibility
}

private struct ExportTrack {
  let viewModel: NowPlayingViewModel.Track
  let durationMs: Int
}

private final class ExportTokenStore: TokenStore {
  private var token = SpotifyToken(accessToken: "asset-token", refreshToken: "asset-refresh", expiresAt: 4_102_444_800)

  func save(_ token: SpotifyToken) throws { self.token = token }
  func load() throws -> SpotifyToken? { token }
  func clear() throws {}
  func requireToken() throws -> SpotifyToken { token }
}

private struct ShowcaseTrackCard: View {
  let context: ShowcaseContext

  var body: some View {
    TrackHero(
      vm: context.coord.nowPlaying,
      pet: context.coord.pet,
      menubar: context.coord.menubar,
      settings: context.coord.settings,
      artworkCache: context.coord.artworkCache,
      client: context.coord.client,
      onReconnect: {},
      badgeInsight: context.coord.aggCache.currentBadgeInsight,
      showPet: true,
      onOpenPet: {},
      onOpenHistory: {},
      onOpenBadge: {}
    )
    .overlay(LCDScanlines())
    .lcdPanel()
  }
}

private struct ShowcasePetSticker: View {
  let pet: PetViewModel

  var body: some View {
    BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 92)
      .frame(width: 112, height: 112)
      .frame(width: 144, height: 144)
      .dialRaisedGel(
        shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
        fill: Dial.Palette.lcd,
        edgeOpacity: 0.34,
        fillTopOpacity: 0.07,
        fillBottomOpacity: 0.025,
        sheenOpacity: 0.42,
        sheenLineWidth: 1.1,
        contactShadowOpacity: 0.28,
        contactShadowRadius: 8,
        contactShadowY: 5,
        innerShadowOpacity: 0.20)
      .padding(18)
  }
}

private struct ShowcaseXHero: View {
  let context: ShowcaseContext
  let transparent: Bool

  var body: some View {
    ZStack {
      if !transparent {
        background
      }

      HStack(alignment: .center, spacing: 86) {
        VStack(alignment: .leading, spacing: 28) {
          Text("DIAL")
            .font(.custom("GeistPixel-Square", size: 108))
            .tracking(8)
            .foregroundStyle(Dial.Palette.textPrimary)
          Text("PRIVATE MUSIC MEMORY DEVICE")
            .font(.custom("GeistPixel-Square", size: 24))
            .tracking(5)
            .foregroundStyle(Dial.Palette.accent)
          Text("SPOTIFY HISTORY -> PET -> ROOM -> ARTIFACTS")
            .font(.custom("GeistMono-Regular", size: 17))
            .tracking(2.4)
            .foregroundStyle(Dial.Palette.textMuted)
            .padding(.top, 14)

          HStack(spacing: 12) {
            BadgePixelIcon(kind: .deepCut, color: Dial.Palette.accentAlt, size: 18)
            Text("ALWAYS-ON WRAPPED")
              .font(.custom("GeistPixel-Square", size: 18))
              .tracking(3)
              .foregroundStyle(Dial.Palette.accentAlt)
          }
          .padding(.top, 24)
        }
        .frame(width: 610, alignment: .leading)

        DropdownView(coord: context.coord, visibility: context.visibility)
          .scaleEffect(1.32)
          .frame(width: DropdownLayout.width * 1.32, height: DropdownLayout.height * 1.32)
          .shadow(color: Color.black.opacity(transparent ? 0 : 0.46), radius: 34, x: 0, y: 24)
      }
      .padding(.horizontal, 96)
    }
  }

  private var background: some View {
    ZStack {
      Dial.Palette.ground
      LinearGradient(
        colors: [
          Dial.Palette.ground,
          Color(red: 0.02, green: 0.05, blue: 0.07),
          Color.black,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
      LCDScanlines(pitch: 4, opacity: 0.08)
      DustTexture().opacity(0.55)
    }
    .ignoresSafeArea()
  }
}

private struct ShowcaseXSquare: View {
  let context: ShowcaseContext

  var body: some View {
    ZStack {
      Dial.Palette.ground
      DustTexture().opacity(0.45)
      VStack(spacing: 30) {
        Text("DIAL")
          .font(.custom("GeistPixel-Square", size: 86))
          .tracking(8)
          .foregroundStyle(Dial.Palette.textPrimary)

        Text("PRIVATE MUSIC MEMORY DEVICE")
          .font(.custom("GeistPixel-Square", size: 18))
          .tracking(3.6)
          .foregroundStyle(Dial.Palette.accent)
          .padding(.bottom, 10)

        DropdownView(coord: context.coord, visibility: context.visibility)
          .scaleEffect(1.18)
          .frame(width: DropdownLayout.width * 1.18, height: DropdownLayout.height * 1.18)
          .shadow(color: Color.black.opacity(0.44), radius: 30, x: 0, y: 20)

        HStack(spacing: 36) {
          ShowcasePetSticker(pet: context.coord.pet)
            .frame(width: 142, height: 142)
          VStack(alignment: .leading, spacing: 12) {
            Text("A TINY Y2K HUD")
              .font(.custom("GeistPixel-Square", size: 21))
              .tracking(3.2)
              .foregroundStyle(Dial.Palette.accent)
            Text("WHERE LISTENING HISTORY BECOMES A COMPANION")
              .font(.custom("GeistMono-Regular", size: 13))
              .tracking(1.8)
              .foregroundStyle(Dial.Palette.textMuted)
          }
        }
        .padding(.top, 4)
      }
      .padding(72)
    }
  }
}
