import XCTest
@testable import Dial

final class BuildInfoTests: XCTestCase {
  private let utc = TimeZone(identifier: "UTC")!
  private let enUS = Locale(identifier: "en_US")

  func test_stampedBuildShowsCommitAndDate() {
    let info = BuildInfo(infoDictionary: [
      "CFBundleShortVersionString": "0.1.0",
      "DialGitCommit": "d2997dc",
      "DialGitDirty": false,
      "DialBuildDate": "2026-11-11T20:30:00Z",
    ])

    XCTAssertEqual(info.commit, "d2997dc")
    XCTAssertFalse(info.dirty)
    XCTAssertEqual(info.summary(timeZone: utc, locale: enUS), "Dial 0.1.0 · d2997dc · built Nov 11, 2026")
  }

  func test_dirtyBuildSaysModified() {
    let info = BuildInfo(infoDictionary: [
      "CFBundleShortVersionString": "0.1.0",
      "DialGitCommit": "d2997dc",
      "DialGitDirty": true,
      "DialBuildDate": "2026-11-11T20:30:00Z",
    ])

    XCTAssertEqual(info.summary(timeZone: utc, locale: enUS), "Dial 0.1.0 · d2997dc (modified) · built Nov 11, 2026")
  }

  func test_unstampedOrUnknownBuildSaysUnknown() {
    let unstamped = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.1.0"])
    XCTAssertNil(unstamped.commit)
    XCTAssertNil(unstamped.builtAt)
    XCTAssertEqual(unstamped.summary(), "Dial 0.1.0 · unknown build")

    let outsideGit = BuildInfo(infoDictionary: [
      "CFBundleShortVersionString": "0.1.0",
      "DialGitCommit": "unknown",
      "DialBuildDate": "2026-11-11T20:30:00Z",
    ])
    XCTAssertNil(outsideGit.commit)
    XCTAssertEqual(outsideGit.summary(timeZone: utc, locale: enUS), "Dial 0.1.0 · unknown build · built Nov 11, 2026")
  }

  /// The test host is the real app, so its Info.plist carries the stamp the
  /// post-build script wrote.
  func test_currentBuildIsStamped() {
    XCTAssertNotNil(BuildInfo.current.commit, "scripts/stamp-build-info.sh didn't stamp this build")
    XCTAssertNotNil(BuildInfo.current.builtAt)
  }
}
