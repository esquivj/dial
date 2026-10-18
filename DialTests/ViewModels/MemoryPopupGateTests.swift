import XCTest
@testable import Dial

final class MemoryPopupContentTests: XCTestCase {
  private let allCategories: Set<BadgeCategory> = [.discovery, .pattern, .milestone]

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }

  func test_rediscoveredSaysWhenTheTrackWasLastPlayed() throws {
    let march2023 = Int64(utc.date(from: DateComponents(year: 2023, month: 3, day: 14, hour: 12))!.timeIntervalSince1970)
    let content = try XCTUnwrap(MemoryPopupContent(
      insight: BadgeInsight(kind: .rediscovered, detail: "Last played 950 days ago"),
      trackName: "Nightcall",
      artistName: "Kavinsky",
      lastPlayedAt: march2023,
      enabledCategories: allCategories,
      calendar: utc))

    XCTAssertEqual(content.label, "REDISCOVERED")
    XCTAssertEqual(content.line, "Last played Mar 2023")
    XCTAssertEqual(content.trackName, "Nightcall")
  }

  func test_firstListenAndMilestonesProducePopups() {
    for (kind, line) in [
      (BadgeMemoryKind.firstListen, "New to your history"),
      (.play100, "100 lifetime plays"),
      (.newArtist, "First time hearing them"),
      (.deepCut, "Rare track, familiar artist"),
      (.anniversary, "Played on this day before"),
    ] {
      let content = MemoryPopupContent(
        insight: BadgeInsight(kind: kind, detail: "100 lifetime plays"),
        trackName: "Track", artistName: "Artist", lastPlayedAt: nil,
        enabledCategories: allCategories)
      XCTAssertEqual(content?.line, line, "\(kind)")
    }
  }

  func test_plainPlayHasNoPopup() {
    XCTAssertNil(MemoryPopupContent(
      insight: nil, trackName: "Track", artistName: "Artist", lastPlayedAt: nil,
      enabledCategories: allCategories))
  }

  func test_sessionPatternsDoNotPopUp() {
    for kind in [BadgeMemoryKind.onStreak, .repeatTrack, .albumMode] {
      XCTAssertNil(MemoryPopupContent(
        insight: BadgeInsight(kind: kind, detail: "x"),
        trackName: "Track", artistName: "Artist", lastPlayedAt: nil,
        enabledCategories: allCategories), "\(kind)")
    }
  }

  func test_disabledBadgeFamilyDoesNotPopUp() {
    XCTAssertNil(MemoryPopupContent(
      insight: BadgeInsight(kind: .play100, detail: "100 lifetime plays"),
      trackName: "Track", artistName: "Artist", lastPlayedAt: nil,
      enabledCategories: [.discovery, .pattern]))
  }

  func test_missingTrackNameDoesNotPopUp() {
    XCTAssertNil(MemoryPopupContent(
      insight: BadgeInsight(kind: .firstListen, detail: "x"),
      trackName: "", artistName: "Artist", lastPlayedAt: nil,
      enabledCategories: allCategories))
  }
}

final class MemoryPopupGateTests: XCTestCase {
  private let clear = MemoryPopupGate.Conditions(enabled: true, hudOpen: false, focusActive: false)
  private let rediscovered = MemoryPopupContent(
    kind: .rediscovered, label: "REDISCOVERED", line: "Last played Mar 2023", trackName: "A", artistName: "B")
  private let hundredth = MemoryPopupContent(
    kind: .play100, label: "100TH PLAY", line: "100 lifetime plays", trackName: "A", artistName: "B")

  func test_showsWhenTrackStartsWithAMemory() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    XCTAssertEqual(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: clear), rediscovered)
  }

  func test_neverShowsForPlainPlays() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    XCTAssertNil(gate.decide(uri: "t1", content: nil, moment: .trackStarted, conditions: clear))
    XCTAssertNil(gate.decide(uri: "t1", content: nil, moment: .playCounted, conditions: clear))
  }

  func test_atMostOnePopupPerTrack() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    XCTAssertNotNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: clear))
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: clear))
    XCTAssertNil(gate.decide(uri: "t1", content: hundredth, moment: .playCounted, conditions: clear))
  }

  func test_nextTrackGetsItsOwnChance() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    _ = gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: clear)
    gate.trackStarted(uri: "t2")
    XCTAssertNotNil(gate.decide(uri: "t2", content: rediscovered, moment: .trackStarted, conditions: clear))
  }

  func test_milestoneShowsWhenThePlayCounts() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    XCTAssertNil(gate.decide(uri: "t1", content: nil, moment: .trackStarted, conditions: clear))
    XCTAssertEqual(gate.decide(uri: "t1", content: hundredth, moment: .playCounted, conditions: clear), hundredth)
  }

  func test_discoveryDoesNotShowLateWhenThePlayCounts() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .playCounted, conditions: clear))
  }

  func test_skipsWhenToggleIsOff() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    var off = clear
    off.enabled = false
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: off))
  }

  func test_skipsWhileHUDIsOpenAndDoesNotShowLaterForThatTrack() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    var hudOpen = clear
    hudOpen.hudOpen = true
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: hudOpen))
    XCTAssertNil(gate.decide(uri: "t1", content: hundredth, moment: .playCounted, conditions: clear))
  }

  func test_skipsDuringFocus() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t1")
    var focus = clear
    focus.focusActive = true
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: focus))
  }

  func test_ignoresDecisionsForATrackThatIsNoLongerPlaying() {
    var gate = MemoryPopupGate()
    gate.trackStarted(uri: "t2")
    XCTAssertNil(gate.decide(uri: "t1", content: rediscovered, moment: .trackStarted, conditions: clear))
    gate.trackStarted(uri: nil)
    XCTAssertNil(gate.decide(uri: "t2", content: rediscovered, moment: .trackStarted, conditions: clear))
  }
}

@MainActor
final class MemoryPopupCoordinatorTests: XCTestCase {
  private final class FakePresenter: MemoryPopupPresenting {
    var isHUDOpen = false
    var shown: [MemoryPopupContent] = []
    func presentMemoryPopup(_ content: MemoryPopupContent, theme: DialTheme) { shown.append(content) }
  }

  private struct FakeFocus: FocusStatusProviding {
    var isFocusActive: Bool
  }

  private func makeCoordinator(insight: BadgeInsight?) throws -> (AppCoordinator, FakePresenter) {
    let dbq = try InMemoryDatabase.make()
    let tokenStore = InMemoryTokenStore()
    let auth = SpotifyAuthService(clientID: "memory-popup", tokenStore: tokenStore)
    let client = SpotifyClient(tokenStore: tokenStore, refresh: { throw SpotifyAuthError.missingStoredToken })
    let coord = AppCoordinator(
      dbq: dbq, client: client, auth: auth, tokenStore: tokenStore,
      defaults: UserDefaults(suiteName: "Dial.MemoryPopup.\(UUID().uuidString)")!)
    let presenter = FakePresenter()
    coord.memoryPopupPresenter = presenter
    coord.focusStatus = FakeFocus(isFocusActive: false)
    coord.nowPlaying.track = .init(
      uri: "spotify:track:1", name: "Nightcall", artistName: "Kavinsky",
      artistUri: nil, artistUris: [], albumName: "OutRun", artUrl: nil)
    var snapshot = AggregationsCache.Snapshot()
    snapshot.currentBadgeInsight = insight
    coord.aggCache.apply(snapshot)
    coord.resetMemoryPopup(forTrack: "spotify:track:1")
    return (coord, presenter)
  }

  func test_toggleIsOnByDefault() throws {
    let (coord, _) = try makeCoordinator(insight: nil)
    XCTAssertTrue(coord.settings.showMemoryPopups)
  }

  func test_presentsCurrentTrackMemoryOnce() throws {
    let (coord, presenter) = try makeCoordinator(insight: BadgeInsight(kind: .firstListen, detail: "No plays in your history"))
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)

    XCTAssertEqual(presenter.shown.map(\.label), ["FIRST LISTEN"])
    XCTAssertEqual(presenter.shown.first?.trackName, "Nightcall")
  }

  func test_doesNotPresentWhileHUDIsOpen() throws {
    let (coord, presenter) = try makeCoordinator(insight: BadgeInsight(kind: .firstListen, detail: "x"))
    presenter.isHUDOpen = true
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)
    XCTAssertTrue(presenter.shown.isEmpty)
  }

  func test_doesNotPresentDuringFocus() throws {
    let (coord, presenter) = try makeCoordinator(insight: BadgeInsight(kind: .firstListen, detail: "x"))
    coord.focusStatus = FakeFocus(isFocusActive: true)
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)
    XCTAssertTrue(presenter.shown.isEmpty)
  }

  func test_doesNotPresentWhenToggledOff() throws {
    let (coord, presenter) = try makeCoordinator(insight: BadgeInsight(kind: .firstListen, detail: "x"))
    coord.settings.showMemoryPopups = false
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)
    XCTAssertTrue(presenter.shown.isEmpty)
  }

  func test_doesNotPresentForPlainPlay() throws {
    let (coord, presenter) = try makeCoordinator(insight: nil)
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .trackStarted)
    coord.considerMemoryPopup(uri: "spotify:track:1", moment: .playCounted)
    XCTAssertTrue(presenter.shown.isEmpty)
  }
}
