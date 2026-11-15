import XCTest
@testable import Dial

/// PLA-139: a read of the Spotify app that never answers must not hold up
/// the poll loop, and must not stack more reads behind it.
final class BoundedBlockingCallTests: XCTestCase {
  private func makeCall() -> BoundedBlockingCall {
    BoundedBlockingCall(queue: DispatchQueue(label: "test.bounded-blocking-call"))
  }

  func test_workThatAnswersReturnsItsValue() async {
    let call = makeCall()
    guard case .value(let v) = await call.run(timeout: 1, { 42 }) else {
      return XCTFail("expected a value")
    }
    XCTAssertEqual(v, 42)
  }

  func test_workThatNeverAnswersTimesOut_andLaterCallsDontQueueBehindIt() async {
    let call = makeCall()
    let stuck = DispatchSemaphore(value: 0)
    defer { stuck.signal() }

    let start = Date()
    guard case .timedOut = await call.run(timeout: 0.2, { stuck.wait(); return 1 }) else {
      return XCTFail("expected a timeout")
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)

    let again = Date()
    guard case .busy = await call.run(timeout: 5, { 2 }) else {
      return XCTFail("a second call must not wait behind the stuck one")
    }
    XCTAssertLessThan(Date().timeIntervalSince(again), 0.1)
  }

  func test_callsRunAgainOnceTheStuckWorkReturns() async throws {
    let call = makeCall()
    let stuck = DispatchSemaphore(value: 0)
    guard case .timedOut = await call.run(timeout: 0.1, { stuck.wait(); return 1 }) else {
      return XCTFail("expected a timeout")
    }
    stuck.signal()
    try await Task.sleep(for: .milliseconds(200))
    guard case .value(let v) = await call.run(timeout: 1, { 3 }) else {
      return XCTFail("expected the call to run again")
    }
    XCTAssertEqual(v, 3)
  }
}
