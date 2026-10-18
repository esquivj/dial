// Dial/ViewModels/ReadoutStripSchedule.swift
import Foundation

/// Decides how the floating LCD strip under the menu bar item reacts to a
/// new readout. The memory pop-up and the hotkey flash share one panel, so
/// nothing ever stacks: a new readout either fades the strip in or, if the
/// strip is already up, swaps the text in place and restarts the hold.
/// Mashing a hotkey therefore keeps one steady strip on screen instead of
/// re-animating on every press.
struct ReadoutStripSchedule {
  enum Kind: Equatable { case memory, flash }

  enum Presentation: Equatable {
    /// The strip was hidden: fade (and, without Reduce Motion, slide) in.
    case appear
    /// The strip is up: change its contents and keep it there.
    case updateInPlace
  }

  private(set) var visibleKind: Kind?
  private(set) var hideAt: Date?

  func isVisible(at now: Date) -> Bool {
    guard visibleKind != nil, let hideAt else { return false }
    return now < hideAt
  }

  mutating func present(_ kind: Kind, hold: TimeInterval, at now: Date) -> Presentation {
    let presentation: Presentation = isVisible(at: now) ? .updateInPlace : .appear
    visibleKind = kind
    hideAt = now.addingTimeInterval(hold)
    return presentation
  }

  /// The strip started fading out or was closed.
  mutating func hidden() {
    visibleKind = nil
    hideAt = nil
  }
}
