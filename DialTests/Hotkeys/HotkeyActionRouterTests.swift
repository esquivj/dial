import XCTest
@testable import Dial

@MainActor
final class HotkeyActionRouterTests: XCTestCase {
  private var menubar: MenubarStripViewModel!
  private var transport: FakeTransport!
  private var library: FakeLibrary!
  private var flashes: [HotkeyFlashContent] = []
  private var hudOpens = 0
  private var reconnects = 0
  private var clock = Date(timeIntervalSince1970: 1_000_000)

  override func setUp() async throws {
    menubar = MenubarStripViewModel()
    menubar.track = NowPlayingViewModel.Track(
      uri: "spotify:track:abc", name: "Song", artistName: "Artist", artistUri: nil,
      albumName: "Album", artUrl: nil)
    menubar.state = .paused
    transport = FakeTransport()
    library = FakeLibrary()
    flashes = []
    hudOpens = 0
    reconnects = 0
  }

  private func makeRouter() -> HotkeyActionRouter {
    HotkeyActionRouter(
      menubar: menubar,
      transport: transport,
      library: library,
      onReconnect: { [weak self] in await MainActor.run { self?.reconnects += 1 } },
      openHUD: { [weak self] in self?.hudOpens += 1 },
      flash: { [weak self] in self?.flashes.append($0) },
      now: { [weak self] in self?.clock ?? Date() })
  }

  // MARK: - Transport routing

  func test_playPauseWhilePausedPlaysAndFlashesPlay() async throws {
    let router = makeRouter()
    router.perform(.playPause)

    XCTAssertEqual(menubar.state, .playing)
    XCTAssertEqual(flashes, [.play])
    try await waitUntil { self.transport.calls == [.play] }
  }

  func test_playPauseWhilePlayingPauses() async throws {
    menubar.state = .playing
    makeRouter().perform(.playPause)

    XCTAssertEqual(menubar.state, .paused)
    XCTAssertEqual(flashes, [.pause])
    try await waitUntil { self.transport.calls == [.pause] }
  }

  func test_failedPlayRevertsStateAndFlashesNoPlayer() async throws {
    transport.failing = true
    makeRouter().perform(.playPause)

    try await waitUntil { self.flashes == [.play, .noPlayer] }
    XCTAssertEqual(menubar.state, .paused)
  }

  func test_nextAndPreviousSendTheirCommands() async throws {
    let router = makeRouter()
    router.perform(.next)
    try await waitUntil { self.transport.calls == [.next] }
    router.perform(.previous)
    try await waitUntil { self.transport.calls == [.next, .previous] }
    XCTAssertEqual(flashes, [.next, .previous])
  }

  func test_openHUDOpensWithoutAFlashOrCommand() {
    makeRouter().perform(.openHUD)
    XCTAssertEqual(hudOpens, 1)
    XCTAssertTrue(flashes.isEmpty)
    XCTAssertTrue(transport.calls.isEmpty)
  }

  // MARK: - Like

  func test_likeUsesLikedSongsLogicAndFlashesLiked() async throws {
    menubar.likedTrackState = .notLiked
    library.liked = false
    makeRouter().perform(.like)

    XCTAssertEqual(flashes, [.liked])
    XCTAssertEqual(menubar.likedTrackState, .liked)
    try await waitUntil { self.library.calls == [.like("spotify:track:abc"), .check("spotify:track:abc")] }
  }

  func test_hotkeyLikeReportsConfirmedChangeForLastFMLovedSync() async throws {
    var reported: [(String, Bool)] = []
    menubar.onUserLikedChange = { uri, liked in reported.append((uri, liked)) }
    menubar.likedTrackState = .notLiked
    library.liked = false
    makeRouter().perform(.like)

    try await waitUntil { reported.count == 1 }
    XCTAssertEqual(reported.first?.0, "spotify:track:abc")
    XCTAssertEqual(reported.first?.1, true)
  }

  func test_likeOnALikedTrackUnlikes() async throws {
    menubar.likedTrackState = .liked
    library.liked = true
    makeRouter().perform(.like)

    XCTAssertEqual(flashes, [.unliked])
    try await waitUntil { self.library.calls.first == .unlike("spotify:track:abc") }
  }

  func test_likeNeedingReconnectFlashesWithoutOpeningSignIn() async throws {
    menubar.likedTrackState = .needsReconnect
    makeRouter().perform(.like)

    XCTAssertEqual(flashes, [.reconnect])
    XCTAssertEqual(menubar.likedTrackState, .needsReconnect)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(reconnects, 0)
    XCTAssertTrue(library.calls.isEmpty)
  }

  func test_likeWithNothingLikeableFlashesNoTrack() {
    menubar.track = nil
    makeRouter().perform(.like)
    XCTAssertEqual(flashes, [.noTrack])
  }

  // MARK: - Volume

  func test_volumeStepsLandOnFivePercentMarks() {
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 47, up: true), 50)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 45, up: true), 50)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 47, up: false), 45)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 45, up: false), 40)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 98, up: true), 100)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 100, up: true), 100)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 2, up: false), 0)
    XCTAssertEqual(HotkeyActionRouter.steppedVolume(from: 0, up: false), 0)
  }

  func test_volumeUpReadsTheCurrentVolumeThenSetsTheNextStep() async {
    transport.volume = 47
    let router = makeRouter()
    router.perform(.volumeUp)
    await router.settle()

    XCTAssertEqual(transport.calls, [.readVolume, .setVolume(50)])
    XCTAssertEqual(flashes, [.volume(50)])
  }

  func test_quickPressesReuseTheTargetInsteadOfRereading() async {
    transport.volume = 60
    let router = makeRouter()
    router.perform(.volumeDown)
    await router.settle()
    clock = clock.addingTimeInterval(0.4)
    router.perform(.volumeDown)
    await router.settle()
    clock = clock.addingTimeInterval(0.4)
    router.perform(.volumeDown)
    await router.settle()

    XCTAssertEqual(transport.calls.filter { $0 == .readVolume }.count, 1)
    XCTAssertEqual(flashes, [.volume(55), .volume(50), .volume(45)])
    XCTAssertEqual(transport.calls.last, .setVolume(45))
  }

  func test_pressesDuringTheFirstReadAreAllApplied() async {
    transport.volume = 30
    let router = makeRouter()
    router.perform(.volumeUp)
    router.perform(.volumeUp)
    router.perform(.volumeUp)
    await router.settle()

    XCTAssertEqual(transport.calls.filter { $0 == .readVolume }.count, 1)
    XCTAssertEqual(flashes.last, .volume(45))
    XCTAssertEqual(transport.calls.last, .setVolume(45))
  }

  func test_staleTargetIsReadAgain() async {
    transport.volume = 50
    let router = makeRouter()
    router.perform(.volumeUp)
    await router.settle()

    transport.volume = 20  // moved in Spotify meanwhile
    clock = clock.addingTimeInterval(HotkeyActionRouter.volumeFreshness + 1)
    router.perform(.volumeUp)
    await router.settle()

    XCTAssertEqual(flashes, [.volume(55), .volume(25)])
  }

  func test_noActivePlayerFlashesNoPlayer() async {
    transport.volume = nil
    let router = makeRouter()
    router.perform(.volumeUp)
    await router.settle()

    XCTAssertEqual(flashes, [.noPlayer])
    XCTAssertFalse(transport.calls.contains { if case .setVolume = $0 { true } else { false } })
  }

  func test_failedVolumeWriteForgetsTheTarget() async {
    transport.volume = 50
    let router = makeRouter()
    router.perform(.volumeUp)
    await router.settle()
    transport.failing = true
    router.perform(.volumeUp)
    await router.settle()

    XCTAssertEqual(flashes, [.volume(55), .volume(60), .noPlayer])
    transport.failing = false
    router.perform(.volumeUp)
    await router.settle()
    XCTAssertEqual(transport.calls.filter { $0 == .readVolume }.count, 2)
  }

  // MARK: - Helpers

  private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

final class FakeTransport: PlaybackTransport {
  enum Call: Equatable { case play, pause, next, previous, readVolume, setVolume(Int) }

  var calls: [Call] = []
  var volume: Int? = 50
  var failing = false

  private func record(_ call: Call) async throws {
    await MainActor.run { calls.append(call) }
    if failing { throw SpotifyAPIError.httpStatus(404) }
  }

  func play() async throws { try await record(.play) }
  func pause() async throws { try await record(.pause) }
  func next() async throws { try await record(.next) }
  func prev() async throws { try await record(.previous) }
  func volumePercent() async throws -> Int? {
    try await record(.readVolume)
    return volume
  }
  func setVolume(percent: Int) async throws {
    try await record(.setVolume(percent))
    if !failing { volume = percent }
  }
}

final class FakeLibrary: LikedLibrary {
  enum Call: Equatable { case like(String), unlike(String), check(String) }

  var calls: [Call] = []
  var liked = false

  func likeTrack(uri: String) async throws {
    await MainActor.run { calls.append(.like(uri)); liked = true }
  }
  func unlikeTrack(uri: String) async throws {
    await MainActor.run { calls.append(.unlike(uri)); liked = false }
  }
  func isTrackLiked(uri: String) async throws -> Bool {
    await MainActor.run { calls.append(.check(uri)) }
    return liked
  }
}
