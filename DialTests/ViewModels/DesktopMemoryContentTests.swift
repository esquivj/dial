import XCTest
@testable import Dial

final class DesktopMemoryContentTests: XCTestCase {
  private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }()

  /// 2023-03-15 12:00 UTC.
  private let march2023: Int64 = 1_678_881_600

  private let track = NowPlayingViewModel.Track(
    uri: "spotify:track:soulja",
    name: "Kiss Me Thru the Phone",
    artistName: "Soulja Boy",
    artistUri: nil,
    albumName: "iSouljaBoyTellem",
    artUrl: "https://i.scdn.co/image/soulja")

  private func make(
    state: MenubarDisplayState = .playing,
    track: NowPlayingViewModel.Track?,
    aggregates: DesktopMemoryContent.Aggregates?,
    categories: Set<BadgeCategory> = Set(BadgeCategory.allCases),
    previous: DesktopMemoryContent? = nil
  ) -> DesktopMemoryContent {
    DesktopMemoryContent(
      state: state,
      track: track,
      aggregates: aggregates,
      enabledCategories: categories,
      previous: previous,
      calendar: utc)
  }

  private func aggregates(_ kind: BadgeMemoryKind?, plays: Int = 12) -> DesktopMemoryContent.Aggregates {
    DesktopMemoryContent.Aggregates(
      insight: kind.map { BadgeInsight(kind: $0, detail: "detail") },
      playsYTD: plays,
      lastPlayedAt: march2023)
  }

  func test_aMemoryIsStampedLikeThePopUp() {
    let content = make(track: track, aggregates: aggregates(.rediscovered))

    XCTAssertEqual(content.playback, .playing)
    XCTAssertEqual(content.stamp, .memory(kind: .rediscovered, label: "REDISCOVERED", line: "Last played Mar 2023"))
    XCTAssertEqual(content.stampLabel, "REDISCOVERED")
    XCTAssertEqual(content.primaryLine, "Last played Mar 2023")
    XCTAssertEqual(content.secondaryLines, ["Kiss Me Thru the Phone · Soulja Boy", "Kiss Me Thru the Phone"])
    XCTAssertNil(content.playbackTag)
  }

  func test_sessionBadgesFallBackToYearToDatePlays() {
    let content = make(track: track, aggregates: aggregates(.onStreak, plays: 12))

    XCTAssertEqual(content.stamp, .yearToDate(plays: 12))
    XCTAssertEqual(content.stampLabel, "TRACK · YTD")
    XCTAssertEqual(content.primaryLine, "12 plays this year")
  }

  func test_aHiddenBadgeFamilyFallsBackToYearToDatePlays() {
    let content = make(
      track: track,
      aggregates: aggregates(.rediscovered, plays: 3),
      categories: [.pattern, .milestone])

    XCTAssertEqual(content.stamp, .yearToDate(plays: 3))
  }

  func test_yearToDateWording() {
    XCTAssertEqual(make(track: track, aggregates: aggregates(nil, plays: 0)).primaryLine, "First play this year")
    XCTAssertEqual(make(track: track, aggregates: aggregates(nil, plays: 1)).primaryLine, "1 play this year")
  }

  func test_aNewTrackWhoseMemoryHasntLoadedSaysOnlyNowPlaying() {
    let content = make(track: track, aggregates: nil)

    XCTAssertEqual(content.stamp, .nowPlaying)
    XCTAssertEqual(content.stampLabel, "NOW PLAYING")
    XCTAssertEqual(content.primaryLine, "Kiss Me Thru the Phone")
    XCTAssertEqual(content.secondaryLines, ["Soulja Boy"])
  }

  func test_pausedKeepsTheMemoryAndAddsATag() {
    let content = make(state: .paused, track: track, aggregates: aggregates(.firstListen))

    XCTAssertEqual(content.playback, .paused)
    XCTAssertEqual(content.playbackTag, "PAUSED")
    XCTAssertEqual(content.stampLabel, "FIRST LISTEN")
  }

  func test_aStoppedPlayerKeepsTheLastTrack() {
    let playing = make(track: track, aggregates: aggregates(.rediscovered))

    let stopped = make(state: .nothingPlaying, track: nil, aggregates: nil, previous: playing)

    XCTAssertEqual(stopped.playback, .notPlaying)
    XCTAssertEqual(stopped.stamp, .notPlaying)
    XCTAssertEqual(stopped.track, playing.track)
    XCTAssertEqual(stopped.primaryLine, "Kiss Me Thru the Phone")
    XCTAssertEqual(stopped.secondaryLines, ["Soulja Boy"])
  }

  func test_nothingPlayingBeforeAnyTrackShowsNoTrack() {
    let content = make(state: .nothingPlaying, track: nil, aggregates: nil)

    XCTAssertNil(content.track)
    XCTAssertEqual(content.stampLabel, "NOT PLAYING")
    XCTAssertNil(content.primaryLine)
    XCTAssertEqual(content.secondaryLines, [])
  }

  func test_aTrackWithoutAnArtistShowsTheTitleAlone() {
    let untitled = NowPlayingViewModel.Track(
      uri: "spotify:track:x", name: "Interlude", artistName: "", artistUri: nil, albumName: "", artUrl: nil)

    XCTAssertEqual(make(track: untitled, aggregates: aggregates(nil)).secondaryLines, ["Interlude"])
  }

  func test_voiceOverReadsTheMemoryThenTheTrack() {
    let content = make(state: .paused, track: track, aggregates: aggregates(.rediscovered))

    XCTAssertEqual(
      content.accessibilityLabel,
      "Rediscovered: Last played Mar 2023. Paused. Kiss Me Thru the Phone · Soulja Boy")
  }
}
