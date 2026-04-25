// Dial/App/WindowsManager.swift
import AppKit
import SwiftUI
import GRDB

/// Owns the History and Stats `NSWindow` instances. We can't use SwiftUI's
/// `@Environment(\.openWindow)` from inside the dropdown because the dropdown
/// is hosted in an `NSPopover` (AppKit), which sits outside the SwiftUI
/// scene hierarchy where `Window(...)` scenes are registered.
@MainActor
final class WindowsManager {
  private let dbq: DatabaseQueue
  private var historyWindow: NSWindow?
  private var statsWindow: NSWindow?

  init(dbq: DatabaseQueue) { self.dbq = dbq }

  func openHistory() {
    if historyWindow == nil {
      historyWindow = makeWindow(title: "History", content: HistoryWindow(dbq: dbq))
    }
    show(historyWindow)
  }

  func openStats() {
    if statsWindow == nil {
      statsWindow = makeWindow(title: "Stats", content: StatsWindow(dbq: dbq))
    }
    show(statsWindow)
  }

  // MARK: -

  private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: content)
    window.center()
    return window
  }

  private func show(_ window: NSWindow?) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
