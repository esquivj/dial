// DialTests/Pet/PetBehaviorTests.swift
import XCTest
@testable import Dial

final class PetBehaviorTests: XCTestCase {
  /// Convenience builder so tests don't have to spell out every PetContext field.
  private func ctx(
    playing: Bool = false,
    paused: Bool = false,
    firstListen: Bool = false,
    rediscovered: Bool = false,
    eating: Bool = false,
    leveledUp: Bool = false,
    lastPlayAt: Int64? = nil,
    now: Int64 = 0,
    bpm: Double? = nil
  ) -> PetContext {
    PetContext(
      playing: playing, paused: paused,
      firstListen: firstListen, rediscovered: rediscovered, eating: eating,
      leveledUp: leveledUp, lastPlayAt: lastPlayAt, now: now, bpm: bpm)
  }

  func test_levelUpBeatsAll() {
    let r = PetBehaviorResolver.resolve(ctx(
      playing: true, firstListen: true, rediscovered: true, eating: true,
      leveledUp: true, bpm: 100))
    XCTAssertEqual(r, .levelUp)
  }

  func test_firstListenOverRediscovered() {
    let r = PetBehaviorResolver.resolve(ctx(playing: true, firstListen: true, rediscovered: true))
    XCTAssertEqual(r, .firstListen)
  }

  func test_eatingBeatsPaused() {
    let r = PetBehaviorResolver.resolve(ctx(paused: true, eating: true))
    XCTAssertEqual(r, .eating)
  }

  func test_pausedWhenNotPlaying() {
    let r = PetBehaviorResolver.resolve(ctx(paused: true))
    XCTAssertEqual(r, .paused)
  }

  func test_dormantAfter7Days() {
    let now: Int64 = 1_700_000_000
    let r = PetBehaviorResolver.resolve(ctx(lastPlayAt: now - 8 * 86_400, now: now))
    XCTAssertEqual(r, .dormant)
  }

  func test_beatSyncWhenPlayingWithBPM() {
    let r = PetBehaviorResolver.resolve(ctx(playing: true, bpm: 120))
    XCTAssertEqual(r, .beatSync(bpm: 120))
  }

  func test_walkWhenPlayingWithoutBPM() {
    // Was `.idle` before walk was introduced; new default while music plays
    // without a BPM is the walk-cycle loop.
    let r = PetBehaviorResolver.resolve(ctx(playing: true))
    XCTAssertEqual(r, .walk)
  }

  func test_idleWhenNothingPlayingAndNotDormant() {
    let r = PetBehaviorResolver.resolve(ctx())
    XCTAssertEqual(r, .idle)
  }
}
