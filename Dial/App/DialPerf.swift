import Foundation
import os

/// Thin signpost wrapper for the few latency paths we actually care about.
/// Inspect in Instruments > Points of Interest, filtering subsystem `com.dial.Dial`.
enum DialPerf {
  fileprivate static let signposter = OSSignposter(
    subsystem: "com.dial.Dial",
    category: "Performance")

  static func begin(_ name: StaticString) -> DialPerfInterval {
    let id = signposter.makeSignpostID()
    let state = signposter.beginInterval(name, id: id)
    return DialPerfInterval(name: name, state: state)
  }

  static func event(_ name: StaticString) {
    signposter.emitEvent(name, id: signposter.makeSignpostID())
  }
}

struct DialPerfInterval {
  fileprivate let name: StaticString
  fileprivate let state: OSSignpostIntervalState

  func end() {
    DialPerf.signposter.endInterval(name, state)
  }
}
