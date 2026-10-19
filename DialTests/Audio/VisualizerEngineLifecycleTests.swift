// DialTests/Audio/VisualizerEngineLifecycleTests.swift
import XCTest
@testable import Dial

/// Counts start/stop calls instead of touching ScreenCaptureKit.
private final class FakeCapture: AudioCapturing, @unchecked Sendable {
  var onSamples: (@Sendable ([Float]) -> Void)?
  var shouldProcessSamples: (@Sendable () -> Bool)?
  var onStop: (@Sendable (Error) -> Void)?
  var startCount = 0
  var stopCount = 0
  var startError: Error?

  func start() async throws {
    startCount += 1
    if let startError { throw startError }
  }

  func stop() async {
    stopCount += 1
  }
}

@MainActor
final class VisualizerEngineLifecycleTests: XCTestCase {
  private func settle(_ seconds: Double = 0.25) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  func test_stream_stops_after_dropdown_closes_and_restarts_on_reopen() async {
    let capture = FakeCapture()
    let engine = VisualizerEngine(capture: capture, idleStopDelay: .milliseconds(50))

    engine.attach()
    await engine.start()
    XCTAssertEqual(capture.startCount, 1)
    XCTAssertTrue(engine.isCaptureLive)

    engine.detach()
    await settle()
    XCTAssertEqual(capture.stopCount, 1)
    XCTAssertFalse(engine.isCaptureLive)
    // The header keeps saying LIVE while the stream is parked.
    XCTAssertEqual(engine.state, .running)

    engine.attach()
    await engine.start()
    await settle(0.05)
    XCTAssertEqual(capture.startCount, 2)
    XCTAssertTrue(engine.isCaptureLive)
  }

  func test_quick_reopen_keeps_stream_running() async {
    let capture = FakeCapture()
    let engine = VisualizerEngine(capture: capture, idleStopDelay: .milliseconds(150))

    engine.attach()
    await engine.start()
    engine.detach()
    await settle(0.05)
    engine.attach()
    await engine.start()
    await settle()

    XCTAssertEqual(capture.startCount, 1)
    XCTAssertEqual(capture.stopCount, 0)
    XCTAssertTrue(engine.isCaptureLive)
  }

  func test_restart_failure_surfaces_permission_state() async {
    let capture = FakeCapture()
    let engine = VisualizerEngine(capture: capture, idleStopDelay: .milliseconds(50))

    engine.attach()
    await engine.start()
    engine.detach()
    await settle()
    XCTAssertFalse(engine.isCaptureLive)

    capture.startError = NSError(domain: "com.apple.TCC", code: 1)
    engine.attach()
    await engine.start()
    XCTAssertEqual(engine.state, .denied)
    XCTAssertFalse(engine.isCaptureLive)
  }

  func test_explicit_stop_still_goes_idle() async {
    let capture = FakeCapture()
    let engine = VisualizerEngine(capture: capture, idleStopDelay: .milliseconds(50))

    await engine.start()
    await engine.stop()
    XCTAssertEqual(engine.state, .idle)
    XCTAssertEqual(capture.stopCount, 1)
    XCTAssertFalse(engine.isCaptureLive)
  }
}
