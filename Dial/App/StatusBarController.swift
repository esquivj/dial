// Dial/App/StatusBarController.swift
import AppKit
import SwiftUI

/// Owns the `NSStatusItem` (the menubar strip) and the `DropdownPanel`
/// (the dropdown). The status item's button hosts a SwiftUI
/// `MenubarStripView`; the panel hosts the SwiftUI `DropdownView`. Both
/// surfaces read from the shared `AppCoordinator` so they animate in
/// lockstep.
///
/// **Why a custom panel, not NSPopover.** NSPopover forces a system-drawn
/// menubar-arrow tip and constrains us to a rectangular content area
/// with system-managed corners and shadow. A borderless NSPanel lets
/// our SwiftUI content paint the entire visible surface (rounded device
/// body, mint stroke, gel chrome, soft halo) without the system fighting
/// us. See `DropdownPanel.swift` for the panel itself.
///
/// **Dismiss handling.** Without NSPopover's `.transient` behavior we
/// have to dismiss the panel manually:
///   * Global click monitor — clicks outside our app
///   * Local click monitor — clicks inside our app but outside the panel
///     (with a carve-out for status item clicks, which are toggled by
///     `handleClick` instead)
///   * Escape key monitor — keyDown 53
/// Monitors are torn down when the panel hides so we don't pay global
/// event traffic when nothing is visible.
///
/// Click handling on the status item:
///   * left-click       → toggle the panel (HUD)
///   * right-click      → show the context menu
///   * ctrl + left-click → show the context menu (macOS convention parity)
///
/// Owning the right-click menu ourselves replaces whatever default macOS
/// would otherwise leak into the menubar (e.g. the recording-indicator
/// menu when ScreenCaptureKit is active) with a coherent, branded surface.
final class StatusBarController {
  private let item: NSStatusItem
  private let panel: DropdownPanel
  private weak var coord: AppCoordinator?

  /// Click + key dismiss monitors. Allocated lazily when the panel
  /// shows; torn down when it hides. Kept as `Any?` because that's the
  /// type NSEvent.addMonitor returns.
  private var globalClickMonitor: Any?
  private var localClickMonitor: Any?
  private var escapeKeyMonitor: Any?

  init(coord: AppCoordinator) {
    self.coord = coord
    self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // Panel size 360×380 — matches the compact body. 380pt gives the
    // status bar breathing room from the top corner curves while
    // keeping the LCD panel content tight (no empty Spacer below
    // the spectrum).
    self.panel = DropdownPanel(
      rootView: DropdownView(coord: coord),
      size: NSSize(width: 360, height: 380))

    if let button = item.button {
      // MenubarStripView no longer takes a pet — the bulldog moved out of
      // the menubar (where it was unreadably small) into the dropdown's
      // StatusRail and its own dedicated PetView screen.
      let host = NSHostingView(rootView: MenubarStripView(vm: coord.menubar))
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
      togglePanel()
      return
    }
    let isContextual = event.type == .rightMouseUp
      || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
    if isContextual {
      showContextMenu()
    } else {
      togglePanel()
    }
  }

  // MARK: - Panel show / hide

  private func togglePanel() {
    if panel.isVisible {
      hidePanel()
    } else {
      showPanel()
    }
  }

  /// Show the panel positioned directly under the status item button,
  /// clamped to screen bounds so it doesn't overflow when the menubar
  /// item is near the right edge of the display.
  private func showPanel() {
    guard let button = item.button, let buttonWindow = button.window else { return }

    let buttonFrameInWindow = button.convert(button.bounds, to: nil)
    let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

    let panelSize = panel.frame.size
    // Center horizontally on the status item, with a 4pt gap below the
    // menubar so the panel doesn't crowd the system menubar's bottom edge.
    var x = buttonFrameOnScreen.midX - panelSize.width / 2
    let y = buttonFrameOnScreen.minY - panelSize.height - 4

    // Clamp horizontally to the visible screen so the panel never
    // extends off the side of the display. 4pt margin from the edge.
    if let screen = buttonWindow.screen {
      let visible = screen.visibleFrame
      x = max(visible.minX + 4, min(visible.maxX - panelSize.width - 4, x))
    }

    panel.setFrameOrigin(NSPoint(x: x, y: y))
    panel.orderFrontRegardless()
    panel.makeKey()

    startDismissMonitors()
  }

  private func hidePanel() {
    panel.orderOut(nil)
    stopDismissMonitors()
  }

  // MARK: - Dismiss monitors

  private func startDismissMonitors() {
    // Global: any click outside our app dismisses the panel. NSPopover
    // got this for free via `.transient`; with NSPanel we wire it up
    // manually.
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      self?.hidePanel()
    }

    // Local: clicks inside our app but outside the device body. The
    // panel is 380×420 but the device body is 320×360 centered, leaving
    // a 30pt transparent margin on every side. Clicks IN that margin
    // (but still within the panel window) should dismiss — the user is
    // clicking "outside the device," they just happen to be inside the
    // panel's transparent area. Without this carve-out, clicking near
    // the device wouldn't dismiss because the global monitor only fires
    // for events outside our app.
    //
    // Other carve-outs:
    //   * Clicks on the device body itself pass through to SwiftUI
    //   * Clicks on the status item button don't dismiss — handleClick
    //     toggles the panel; if we hid here it would flicker.
    localClickMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      if event.window === self.panel {
        // Click is inside our panel — was it on the device body or
        // in the transparent margin?
        if self.eventIsInsideDeviceBody(event) {
          return event   // pass through to SwiftUI
        } else {
          self.hidePanel()
          return nil     // consume — don't leak to anything behind
        }
      }
      if self.eventIsOnStatusItem(event) { return event }
      self.hidePanel()
      return event
    }

    // Escape key: dismiss + consume so the keypress doesn't leak to
    // anything behind us. Returning `nil` from a local monitor swallows
    // the event.
    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(
      matching: .keyDown
    ) { [weak self] event in
      if event.keyCode == 53 {  // Escape
        self?.hidePanel()
        return nil
      }
      return event
    }
  }

  private func stopDismissMonitors() {
    if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
    if let m = localClickMonitor  { NSEvent.removeMonitor(m); localClickMonitor  = nil }
    if let m = escapeKeyMonitor   { NSEvent.removeMonitor(m); escapeKeyMonitor   = nil }
  }

  /// Whether the given event's mouse location falls within the status
  /// item button's screen-space frame. Used to skip dismiss-on-click for
  /// status item clicks (those go through `handleClick` instead).
  private func eventIsOnStatusItem(_ event: NSEvent) -> Bool {
    guard
      let button = item.button,
      let buttonWindow = button.window
    else { return false }
    let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    return frame.contains(NSEvent.mouseLocation)
  }

  /// Whether the event's location falls inside the visible device area.
  /// Panel is 420 wide but only the central 360pt is the actual device
  /// body — the 30pt left/right margins host decorative chassis buttons.
  /// Clicks on those margins (whether on a side button or in empty
  /// chassis space) should NOT dismiss — the side buttons read as
  /// hardware controls, dismiss-on-click would feel buggy. So we treat
  /// the entire panel area (body + chassis margins) as "inside" and
  /// rely on the global monitor for actual outside-the-app dismiss.
  private func eventIsInsideDeviceBody(_ event: NSEvent) -> Bool {
    let panelSize = panel.frame.size
    let bodyFrame = NSRect(origin: .zero, size: panelSize)
    return bodyFrame.contains(event.locationInWindow)
  }

  // MARK: - Context menu

  private func showContextMenu() {
    guard let button = item.button else { return }
    // Close the panel first so the menu doesn't appear behind it.
    if panel.isVisible { hidePanel() }
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

    let pet = NSMenuItem(title: "Open Pet", action: #selector(openPet), keyEquivalent: "")
    pet.target = self
    menu.addItem(pet)

    menu.addItem(.separator())

    let restart = NSMenuItem(
      title: "Restart Current Track", action: #selector(restartTrack), keyEquivalent: "")
    restart.target = self
    menu.addItem(restart)

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
    if !panel.isVisible { showPanel() }
  }

  @objc private func openStats() {
    coord?.dropdownScreen = .stats
    if !panel.isVisible { showPanel() }
  }

  @objc private func openPet() {
    coord?.dropdownScreen = .pet
    if !panel.isVisible { showPanel() }
  }

  /// Seek the current track back to 0:00. Best-effort — if no track is
  /// playing or Spotify rejects (no active device), we silently no-op.
  @objc private func restartTrack() {
    guard let client = coord?.client else { return }
    Task { try? await client.seek(positionMs: 0) }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }
}
