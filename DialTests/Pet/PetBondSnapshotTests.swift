import XCTest
@testable import Dial

final class PetBondSnapshotTests: XCTestCase {
  func test_currentBadgePrioritizesMemoryAction() {
    let snapshot = PetBondSnapshot.make(.init(
      xp: 1_000,
      streakDays: 1,
      playsYTDForCurrentTrack: 1,
      playbackState: .playing,
      todayListeningMs: 12 * 60_000,
      recentBadgeCounts: [:],
      currentBadge: .init(kind: .rediscovered, detail: "An old favorite came back."),
      currentTrackName: "Track",
      unlockedTricks: []))

    XCTAssertEqual(snapshot.primaryAction, .rememberThis)
    XCTAssertEqual(snapshot.moodLabel, "Rediscovered")
  }

  func test_energyDipsWhenPlaybackIsPaused() {
    let playing = PetBondSnapshot.make(.init(
      xp: 0,
      streakDays: 0,
      playsYTDForCurrentTrack: 0,
      playbackState: .playing,
      todayListeningMs: 60 * 60_000,
      recentBadgeCounts: [:],
      currentBadge: nil,
      currentTrackName: nil,
      unlockedTricks: []))
    let paused = PetBondSnapshot.make(.init(
      xp: 0,
      streakDays: 0,
      playsYTDForCurrentTrack: 0,
      playbackState: .paused,
      todayListeningMs: 60 * 60_000,
      recentBadgeCounts: [:],
      currentBadge: nil,
      currentTrackName: nil,
      unlockedTricks: []))

    XCTAssertGreaterThan(playing.energyScore, paused.energyScore)
  }

  func test_recentDiscoveryUnlocksTeachTrickAction() {
    let snapshot = PetBondSnapshot.make(.init(
      xp: 500,
      streakDays: 1,
      playsYTDForCurrentTrack: 0,
      playbackState: .paused,
      todayListeningMs: 30 * 60_000,
      recentBadgeCounts: [.discovery: 6],
      currentBadge: nil,
      currentTrackName: nil,
      unlockedTricks: []))

    XCTAssertEqual(snapshot.primaryAction, .teachTrick(.sparkStep))
    XCTAssertEqual(snapshot.moodLabel, "Curious")
  }

  func test_unlockedTrickCanBecomePrimaryActionWhilePlaying() {
    let snapshot = PetBondSnapshot.make(.init(
      xp: 10_000,
      streakDays: 4,
      playsYTDForCurrentTrack: 2,
      playbackState: .playing,
      todayListeningMs: 45 * 60_000,
      recentBadgeCounts: [:],
      currentBadge: nil,
      currentTrackName: nil,
      unlockedTricks: [.sparkStep]))

    XCTAssertEqual(snapshot.primaryAction, .showTrick(.sparkStep))
  }
}
