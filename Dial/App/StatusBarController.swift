// Dial/App/StatusBarController.swift
import AppKit
import SwiftUI

/// Owns the `NSStatusItem` (the menubar strip) and the `NSPopover` (the
/// dropdown). The status item's button hosts a SwiftUI `MenubarStripView`;
/// the popover hosts the SwiftUI `DropdownView`. Both surfaces read from
/// the shared `AppCoordinator` so they animate in lockstep.
///
/// Click handling:
///   * left-click       → toggle the popover (HUD)
///   * right-click      → show the context menu
///   * ctrl + left-click → show the context menu (macOS convention parity)
///
/// Owning the right-click menu ourselves replaces whatever default macOS
/// would otherwise leak into the menubar (e.g. the recording-indicator
/// menu when ScreenCaptureKit is active) with a coherent, branded surface.
final class StatusBarController {
  private let item: NSStatusItem
  private let popover: NSPopover
  private weak var coord: AppCoordinator?

  init(coord: AppCoordinator) {
    self.coord = coord
    self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.popover = NSPopover()
    self.popover.behavior = .transient
    self.popover.contentSize = NSSize(width: 320, height: 360)
    self.popover.contentViewController = NSHostingController(
      rootView: DropdownView(coord: coord))

    if let button = item.button {
      let host = NSHostingView(rootView: MenubarStripView(vm: coord.menubar, pet: coord.pet))
      host.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(host)
      NSLayoutConstraint.activate([
        host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        host.topAnchor.constraint(equalTo: button.topAnchor),
        host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
      ])
      button.action = #selector(handleClick(_:))
      button.target = self
      // Receive both mouse-up types so we can branch on event in handleClick.
      // Without this, NSStatusBarButton only forwards left-click.
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
  }

  // MARK: - Click routing

  @objc private func handleClick(_ sender: AnyObject) {
    guard let event = NSApp.currentEvent else {
      togglePopover()
      return
    }
    let isContextual = event.type == .rightMouseUp
      || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
    if isContextual {
      showContextMenu()
    } else {
      togglePopover()
    }
  }

  private func togglePopover() {
    guard let button = item.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }

  private func showPopover() {
    guard let button = item.button, !popover.isShown else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  // MARK: - Context menu

  private func showContextMenu() {
    guard let button = item.button else { return }
    // Close the popover first so the menu doesn't appear behind it.
    if popover.isShown { popover.performClose(nil) }
    let menu = makeContextMenu()
    // Anchor the menu under the button's bottom edge — matches how built-in
    // menubar items drop down.
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: button.bounds.maxY + 4),
      in: button)
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()

    // Disabled header — version label, doubles as a "this is Dial" anchor
    // for users who have a lot of menubar items.
    let version =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    let header = NSMenuItem(title: "Dial \(version)", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)

    menu.addItem(.separator())

    let settings = NSMenuItem(
      title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)

    let history = NSMenuItem(
      title: "Open History", action: #selector(openHistory), keyEquivalent: "")
    history.target = self
    menu.addItem(history)

    let stats = NSMenuItem(title: "Open Stats", action: #selector(openStats), keyEquivalent: "")
    stats.target = self
    menu.addItem(stats)

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit Dial", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    return menu
  }

  // MARK: - Menu actions

  @objc private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    // macOS 14+: Settings selector is `showSettingsWindow:`. On older macOS
    // it's `showPreferencesWindow:`. Try the modern one first.
    let primary = Selector(("showSettingsWindow:"))
    let fallback = Selector(("showPreferencesWindow:"))
    if NSApp.responds(to: primary) {
      NSApp.sendAction(primary, to: nil, from: nil)
    } else {
      NSApp.sendAction(fallback, to: nil, from: nil)
    }
  }

  @objc private func openHistory() {
    coord?.dropdownScreen = .history
    showPopover()
  }

  @objc private func openStats() {
    coord?.dropdownScreen = .stats
    showPopover()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }
}
