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
    ambientTrick: PetBehavior? = nil,
    lastPlayAt: Int64? = nil,
    now: Int64 = 0,
    bpm: Double? = nil
  ) -> PetContext {
    PetContext(
      playing: playing, paused: paused,
      firstListen: firstListen, rediscovered: rediscovered, eating: eating,
      leveledUp: leveledUp, ambientTrick: ambientTrick,
      lastPlayAt: lastPlayAt, now: now, bpm: bpm)
  }

  func test_levelUpBeatsAll() {
    let r = PetBehaviorResolver.resolve(ctx(
      playing: true, firstListen: true, rediscovered: true, eating: true,
      leveledUp: true, bpm: 100))
    XCTAssertEqual(r, .expressed(.levelUp, motion: .beatSync(bpm: 100)))
  }

  func test_firstListenOverRediscovered() {
    let r = PetBehaviorResolver.resolve(ctx(playing: true, firstListen: true, rediscovered: true))
    XCTAssertEqual(r, .expressed(.firstListen, motion: .walk))
  }

  func test_badgeExpressionKeepsBeatMotionWhenPlayingWithBPM() {
    let r = PetBehaviorResolver.resolve(ctx(playing: true, rediscovered: true, bpm: 126))
    XCTAssertEqual(r, .expressed(.rediscovered, motion: .beatSync(bpm: 126)))
  }

  func test_eatingBeatsPaused() {
    let r = PetBehaviorResolver.resolve(ctx(paused: true, eating: true))
    XCTAssertEqual(r, .eating)
  }

  func test_pausedWhenNotPlaying() {
    let r = PetBehaviorResolver.resolve(ctx(paused: true))
    XCTAssertEqual(r, .paused)
  }

  func test_ambientTrickComesAfterCountedPlayPulse() {
    let eating = PetBehaviorResolver.resolve(ctx(playing: true, eating: true, ambientTrick: .sparkStep))
    XCTAssertEqual(eating, .eating)

    let trick = PetBehaviorResolver.resolve(ctx(playing: true, ambientTrick: .sparkStep))
    XCTAssertEqual(trick, .sparkStep)
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

  func test_trickBehaviorsUseDedicatedSpriteLoops() {
    XCTAssertEqual(
      BulldogSprite.assets(for: .companion, behavior: .sparkStep),
      ["companion-spark-step-a", "companion-spark-step-b"])
    XCTAssertEqual(
      BulldogSprite.assets(for: .companion, behavior: .memorySpin),
      ["companion-memory-spin-a", "companion-memory-spin-b"])
    XCTAssertEqual(
      BulldogSprite.assets(for: .companion, behavior: .beatBounce),
      ["companion-beat-bounce-a", "companion-beat-bounce-b"])
    XCTAssertNotNil(BulldogSprite.frameInterval(for: .sparkStep))
    XCTAssertNotNil(BulldogSprite.frameInterval(for: .memorySpin))
    XCTAssertNotNil(BulldogSprite.frameInterval(for: .beatBounce))
  }

  func test_expressedBehaviorsUseMotionSpriteLoops() {
    XCTAssertEqual(
      BulldogSprite.assets(for: .companion, behavior: .expressed(.rediscovered, motion: .walk)),
      ["companion-walk-a", "companion-walk-b"])
    XCTAssertNotNil(BulldogSprite.frameInterval(for: .expressed(.firstListen, motion: .walk)))
    XCTAssertNil(BulldogSprite.frameInterval(for: .expressed(.rediscovered, motion: .beatSync(bpm: 118))))
  }
}
