import XCTest
@testable import Dial

/// PLA-117: the menu bar shows a memory's reason in the artist slot for a
/// few seconds, then goes back to the artist.
@MainActor
final class MenubarMemoryReasonTests: XCTestCase {
  private func content(_ kind: BadgeMemoryKind) -> MemoryPopupContent {
    MemoryPopupContent(kind: kind, label: "", line: "line", trackName: "T", artistName: "A")
  }

  func test_memoriesShowWhenTheTrackStarts_firstListenNever() {
    XCTAssertTrue(MenubarMemoryReason.shows(content(.rediscovered), moment: .trackStarted))
    XCTAssertTrue(MenubarMemoryReason.shows(content(.deepCut), moment: .trackStarted))
    XCTAssertFalse(MenubarMemoryReason.shows(content(.firstListen), moment: .trackStarted))
  }

  func test_onlyMilestonesWaitForTheCountedPlay() {
    XCTAssertTrue(MenubarMemoryReason.shows(content(.play100), moment: .playCounted))
    XCTAssertFalse(MenubarMemoryReason.shows(content(.deepCut), moment: .playCounted))
  }

  func test_reasonClearsItselfAfterTheDuration() async throws {
    let vm = MenubarStripViewModel()
    vm.showMemoryReason("Last played Mar 2025", for: .milliseconds(50))
    XCTAssertEqual(vm.memoryReason, "Last played Mar 2025")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(vm.memoryReason)
  }

  func test_aNewReasonRestartsTheTimer() async throws {
    let vm = MenubarStripViewModel()
    vm.showMemoryReason("old", for: .milliseconds(50))
    vm.showMemoryReason("new", for: .seconds(60))
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(vm.memoryReason, "new", "the first timer must not clear the second reason")
    vm.clearMemoryReason()
    XCTAssertNil(vm.memoryReason)
  }
}
