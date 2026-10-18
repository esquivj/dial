// Dial/App/DialFocusFilter.swift
import AppIntents
import Foundation

/// The Focus filter users add under System Settings › Focus › <Focus> ›
/// Focus filters. The system runs `perform()` when that Focus turns on
/// (with the toggle as configured) and again when it turns off (with the
/// toggle back at its unset default, `nil`). The parameter must stay
/// optional: with a non-optional one the system skips the "off" call.
struct DialFocusFilter: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Dial"
  static let description: IntentDescription? = "Hide memory pop-ups while this Focus is on."

  @Parameter(title: "Hide memory pop-ups")
  var hideMemoryPopups: Bool?

  init() {}

  init(hideMemoryPopups: Bool?) {
    self.hideMemoryPopups = hideMemoryPopups
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: hideMemoryPopups == true ? "Memory pop-ups hidden" : "Memory pop-ups shown")
  }

  static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [DialFocusFilter] {
    [DialFocusFilter(hideMemoryPopups: true)]
  }

  func perform() async throws -> some IntentResult {
    FocusFilterState().apply(hideMemoryPopups: hideMemoryPopups)
    return .result()
  }

  /// Catches up on a Focus change that happened while Dial wasn't running.
  /// No active filter (or any error) counts as "Focus off": a pop-up
  /// slipping through a Focus is better than pop-ups staying hidden for good.
  static func syncState(_ state: FocusFilterState = FocusFilterState()) async {
    let current = try? await DialFocusFilter.current
    state.apply(hideMemoryPopups: current?.hideMemoryPopups)
  }
}
