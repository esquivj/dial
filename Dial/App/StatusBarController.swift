// Dial/App/StatusBarController.swift
import AppKit
import Observation
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
  private let panelVisibility = DropdownVisibility()
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
    self.item.autosaveName = "DialStatusItem"
    self.item.isVisible = true
    // Panel size tracks DropdownView exactly so the transparent NSPanel
    // does not leave an invisible click area around the device shell.
    self.panel = DropdownPanel(
      rootView: DropdownView(coord: coord, visibility: panelVisibility),
      size: NSSize(width: DropdownLayout.width, height: DropdownLayout.height))

    if let button = item.button {
      // MenubarStripView no longer takes a pet — the bulldog moved out of
      // the menubar (where it was unreadably small) into the dropdown's
      // StatusRail and its own dedicated PetView screen.
      let host = NSHostingView(rootView: MenubarStripView(
        vm: coord.menubar,
        settings: coord.settings,
        pet: coord.pet,
        nowPlaying: coord.nowPlaying,
        artworkCache: coord.artworkCache))
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

    observeStatusItemLength()
  }

  // MARK: - Click routing

  private func observeStatusItemLength() {
    guard let coord else { return }
    withObservationTracking {
      _ = coord.settings.menuBarDisplayMode
      _ = coord.settings.menuBarTitleWidth
      _ = coord.settings.hudColorMode
      _ = coord.settings.showAlbumArtInMenuBar
      _ = coord.settings.petEnabled
      _ = coord.nowPlaying.soundTheme
      _ = coord.menubar.state
      _ = coord.menubar.track?.name
      _ = coord.menubar.track?.artistName
      _ = coord.menubar.track?.artUrl
      _ = coord.menubar.playsYTD
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.updateStatusItemLength()
        self?.observeStatusItemLength()
      }
    }
    updateStatusItemLength()
  }

  private func updateStatusItemLength() {
    guard let coord else {
      item.length = 34
      return
    }

    let titleWidth = CGFloat(MenuBarTextMetrics.clampedSettingWidth(coord.settings.menuBarTitleWidth))
    let horizontalPadding: CGFloat = 8
    let iconSlot: CGFloat = 22
    let iconGap: CGFloat = 5

    let width: CGFloat = {
      if coord.menubar.state == .nothingPlaying {
        return horizontalPadding + iconSlot + iconGap + MenuBarTextMetrics.brandWidth
      }
      switch coord.settings.menuBarDisplayMode {
      case .albumArtTitle, .petTitle:
        return horizontalPadding + iconSlot + iconGap + currentTitleTextWidth(max: titleWidth)
      case .albumArtTrackArtist:
        return horizontalPadding + iconSlot + iconGap + currentTrackArtistTextWidth(max: titleWidth)
      case .titlePlayCount:
        let playCountWidth: CGFloat = coord.menubar.state == .playing ? 34 : 0
        return horizontalPadding + currentTitleTextWidth(max: titleWidth) + playCountWidth
      case .petOnly, .iconOnly:
        return horizontalPadding + iconSlot
      case .tinyChaos:
        return horizontalPadding + iconSlot + 4 + iconSlot + 4 + 24
      }
    }()

    item.length = max(30, min(320, width))
  }

  private func currentTitleTextWidth(max maxWidth: CGFloat) -> CGFloat {
    guard let coord else { return 0 }
    if coord.menubar.state == .nothingPlaying {
      return MenuBarTextMetrics.brandWidth
    }
    let text: String = {
      switch coord.menubar.state {
      case .playing:        return coord.menubar.track?.name ?? ""
      case .paused:         return coord.menubar.track?.name ?? "DIAL"
      case .nothingPlaying: return "DIAL"
      }
    }()
    return clampedMenuBarTextWidth(text, max: maxWidth)
  }

  private func currentTrackArtistTextWidth(max maxWidth: CGFloat) -> CGFloat {
    guard let coord else { return 0 }
    if coord.menubar.state == .nothingPlaying {
      return MenuBarTextMetrics.brandWidth
    }
    let text: String = {
      switch coord.menubar.state {
      case .playing:
        let title = coord.menubar.track?.name ?? ""
        let artist = coord.menubar.track?.artistName ?? ""
        return artist.isEmpty ? title : "\(title) • \(artist)"
      case .paused:
        let title = coord.menubar.track?.name ?? ""
        let artist = coord.menubar.track?.artistName ?? ""
        let trackArtist = artist.isEmpty ? title : "\(title) • \(artist)"
        return trackArtist.isEmpty ? "DIAL" : trackArtist
      case .nothingPlaying:
        return "DIAL"
      }
    }()
    return clampedMenuBarTextWidth(text, max: maxWidth)
  }

  private func clampedMenuBarTextWidth(_ text: String, max maxWidth: CGFloat) -> CGFloat {
    MenuBarTextMetrics.width(for: text, max: maxWidth)
  }

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
      showPanel(screen: coord?.settings.defaultDropdownScreen.screen ?? .hud)
    }
  }

  /// Show the panel positioned directly under the status item button,
  /// clamped to screen bounds so it doesn't overflow when the menubar
  /// item is near the right edge of the display.
  private func showPanel(screen: DropdownScreen? = nil) {
    if let screen {
      coord?.dropdownScreen = screen
    }
    guard let button = item.button, let buttonWindow = button.window else { return }
    panelVisibility.isVisible = true

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
    panelVisibility.isVisible = false
    panel.orderOut(nil)
    stopDismissMonitors()
  }

  // MARK: - Dismiss monitors

  private func startDismissMonitors() {
    // Global: any click outside our app dismisses the panel. NSPopover
    // got this for free via `.transient`; with NSPanel we wire it up
    // manually. Non-activating panels can still surface panel clicks to
    // global monitors, so ignore points that are inside Dial's own frame.
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      guard let self else { return }
      let point = NSEvent.mouseLocation
      if self.screenPointIsInsidePanel(point) || self.screenPointIsOnStatusItem(point) {
        return
      }
      self.hidePanel()
    }

    // Local: clicks inside our app but outside the panel dismiss it.
    // The SwiftUI shell fills the NSPanel now, so anything inside the
    // panel bounds should pass through to SwiftUI.
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
    screenPointIsOnStatusItem(NSEvent.mouseLocation)
  }

  private func screenPointIsOnStatusItem(_ point: NSPoint) -> Bool {
    guard
      let button = item.button,
      let buttonWindow = button.window
    else { return false }
    let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    return frame.contains(point)
  }

  private func screenPointIsInsidePanel(_ point: NSPoint) -> Bool {
    panel.isVisible && panel.frame.contains(point)
  }

  /// Whether the event's location falls inside the visible device area.
  /// The shell fills the panel, so the full panel bounds count as inside.
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

  @MainActor @objc private func openSettings() {
    guard let coord else { return }
    SettingsWindowPresenter.shared.show(coord: coord)
  }

  @objc private func openHistory() {
    if !panel.isVisible { showPanel(screen: .history) }
    else { coord?.dropdownScreen = .history }
  }

  @objc private func openStats() {
    if !panel.isVisible { showPanel(screen: .stats) }
    else { coord?.dropdownScreen = .stats }
  }

  @objc private func openPet() {
    if !panel.isVisible { showPanel(screen: .pet) }
    else { coord?.dropdownScreen = .pet }
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
