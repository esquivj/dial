// Dial/Views/Dropdown/CoalescedSnapshotLoader.swift
import Foundation

@MainActor
final class CoalescedSnapshotLoader<Snapshot> {
  private var task: Task<Void, Never>?
  private let signpostName: StaticString
  private let delayNanos: UInt64

  init(_ signpostName: StaticString = "snapshot.load", delayMilliseconds: UInt64 = 90) {
    self.signpostName = signpostName
    self.delayNanos = delayMilliseconds * 1_000_000
  }

  func schedule(
    _ load: @escaping () async -> Snapshot,
    apply: @escaping (Snapshot) -> Void
  ) {
    task?.cancel()
    task = Task { @MainActor in
      if delayNanos > 0 {
        try? await Task.sleep(nanoseconds: delayNanos)
      }
      guard !Task.isCancelled else { return }
      let perf = DialPerf.begin(signpostName)
      let snapshot = await load()
      perf.end()
      guard !Task.isCancelled else { return }
      apply(snapshot)
      task = nil
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}
