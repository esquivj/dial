import Foundation

/// Runs blocking work on a serial queue and stops waiting for it after a
/// deadline (PLA-139). macOS's Apple Events permission check and Spotify
/// itself can stop answering; without a deadline that froze the whole poll
/// loop, Web API included.
///
/// One call at a time: while earlier work is still running, a new call
/// returns `.busy` at once instead of queueing behind it. When the stuck
/// work finally returns, calls run again.
final class BoundedBlockingCall: @unchecked Sendable {
  enum Outcome<T> {
    case value(T)
    /// The work didn't finish by the deadline. It keeps running; its result
    /// is dropped.
    case timedOut
    /// Earlier work is still running, so this call didn't start.
    case busy
  }

  let queue: DispatchQueue
  private let lock = NSLock()
  private var running = false

  init(queue: DispatchQueue) {
    self.queue = queue
  }

  func run<T>(timeout: TimeInterval, _ work: @escaping () -> T) async -> Outcome<T> {
    let started = lock.withLock {
      guard !running else { return false }
      running = true
      return true
    }
    guard started else { return .busy }

    return await withCheckedContinuation { (continuation: CheckedContinuation<Outcome<T>, Never>) in
      let once = ResumeOnce(continuation)
      queue.async {
        let value = work()
        self.lock.withLock { self.running = false }
        once.resume(.value(value))
      }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
        once.resume(.timedOut)
      }
    }
  }
}

private final class ResumeOnce<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Never>?

  init(_ continuation: CheckedContinuation<T, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: T) {
    lock.lock()
    let c = continuation
    continuation = nil
    lock.unlock()
    c?.resume(returning: value)
  }
}
