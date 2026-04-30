import XCTest
@testable import Dial

final class MenubarStripViewModelTests: XCTestCase {
  func test_staleRemoteShuffleDoesNotUndoRecentOptimisticToggle() {
    let vm = MenubarStripViewModel()
    let now = Date(timeIntervalSince1970: 100)

    vm.setOptimisticShuffle(true, at: now)
    vm.applyRemoteModes(shuffle: false, repeatMode: .off, at: now.addingTimeInterval(1))

    XCTAssertTrue(vm.shuffle)
  }

  func test_remoteShuffleConfirmationClearsOptimisticGuard() {
    let vm = MenubarStripViewModel()
    let now = Date(timeIntervalSince1970: 100)

    vm.setOptimisticShuffle(true, at: now)
    vm.applyRemoteModes(shuffle: true, repeatMode: .off, at: now.addingTimeInterval(1))
    vm.applyRemoteModes(shuffle: false, repeatMode: .off, at: now.addingTimeInterval(2))

    XCTAssertFalse(vm.shuffle)
  }

  func test_staleRemoteRepeatDoesNotUndoRecentOptimisticToggle() {
    let vm = MenubarStripViewModel()
    let now = Date(timeIntervalSince1970: 100)

    vm.setOptimisticRepeatMode(.context, at: now)
    vm.applyRemoteModes(shuffle: false, repeatMode: .off, at: now.addingTimeInterval(1))

    XCTAssertEqual(vm.repeatMode, .context)
  }

  func test_remoteRepeatWinsAfterOptimisticGuardExpires() {
    let vm = MenubarStripViewModel()
    let now = Date(timeIntervalSince1970: 100)

    vm.setOptimisticRepeatMode(.track, at: now)
    vm.applyRemoteModes(shuffle: false, repeatMode: .off, at: now.addingTimeInterval(6))

    XCTAssertEqual(vm.repeatMode, .off)
  }
}
