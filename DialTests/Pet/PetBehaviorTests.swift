// DialTests/Pet/PetBehaviorTests.swift
import XCTest
@testable import Dial

final class PetBehaviorTests: XCTestCase {
  func test_levelUpBeatsAll() {
    let r = PetBehaviorResolver.resolve(.init(playing: true, paused: false,
      firstListen: true, rediscovered: true, leveledUp: true, lastPlayAt: nil, now: 0, bpm: 100))
    XCTAssertEqual(r, .levelUp)
  }
  func test_firstListenOverRediscovered() {
    let r = PetBehaviorResolver.resolve(.init(playing: true, paused: false,
      firstListen: true, rediscovered: true, leveledUp: false, lastPlayAt: nil, now: 0, bpm: nil))
    XCTAssertEqual(r, .firstListen)
  }
  func test_pausedWhenNotPlaying() {
    let r = PetBehaviorResolver.resolve(.init(playing: false, paused: true,
      firstListen: false, rediscovered: false, leveledUp: false, lastPlayAt: nil, now: 0, bpm: nil))
    XCTAssertEqual(r, .paused)
  }
  func test_dormantAfter7Days() {
    let now: Int64 = 1_700_000_000
    let r = PetBehaviorResolver.resolve(.init(playing: false, paused: false,
      firstListen: false, rediscovered: false, leveledUp: false,
      lastPlayAt: now - 8 * 86_400, now: now, bpm: nil))
    XCTAssertEqual(r, .dormant)
  }
  func test_beatSyncWhenPlayingWithBPM() {
    let r = PetBehaviorResolver.resolve(.init(playing: true, paused: false,
      firstListen: false, rediscovered: false, leveledUp: false, lastPlayAt: nil, now: 0, bpm: 120))
    XCTAssertEqual(r, .beatSync(bpm: 120))
  }
  func test_idleWhenPlayingWithoutBPM() {
    let r = PetBehaviorResolver.resolve(.init(playing: true, paused: false,
      firstListen: false, rediscovered: false, leveledUp: false, lastPlayAt: nil, now: 0, bpm: nil))
    XCTAssertEqual(r, .idle)
  }
}
