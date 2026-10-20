// Dial/App/DesktopMemoryController.swift
import AppKit
import Observation
import SwiftUI

/// Keeps the desktop memory object (docs/design/desktop-memory.md) on the
/// desktop: a borderless, non-activating panel at the backstop window
/// level, above the desktop and its icons and below every app window.
///
/// It redraws only when the track, play state, memory, theme or settings
/// change. Click (or VoiceOver's press) opens the HUD, drag moves it and it
/// snaps to the nearest corner on release, right-click offers Open Dial and
/// Hide.
@MainActor
final class DesktopMemoryController {
  /// Everything the object depends on, read in one place so observation
  /// tracks exactly what `update()` uses.
  private struct Inputs {
    var enabled: Bool
    var state: MenubarDisplayState
    var track: NowPlayingViewModel.Track?
    var aggregates: DesktopMemoryContent.Aggregates?
    var enabledCategories: Set<BadgeCategory>
    var theme: DialTheme
    var corner: DesktopMemoryCorner
    var displayID: UInt32
  }

  private weak var coord: AppCoordinator?
  private let openHUD: () -> Void
  private let panel = DesktopMemoryPanel()
  private let hostView: DesktopMemoryHostView
  private let placement = DesktopMemoryPlacement()
  private var content: DesktopMemoryContent?
  private var theme = DialTheme.classic
  private var artworkURL: String?
  private var artwork: NSImage?
  private var artworkTask: Task<Void, Never>?
  /// Where the panel is headed. Saving the corner after a drag triggers an
  /// update; this keeps that update from cutting the snap animation short.
  private var targetFrame: CGRect?
  private var screenObserver: NSObjectProtocol?

  init(coord: AppCoordinator, openHUD: @escaping () -> Void) {
    self.coord = coord
    self.openHUD = openHUD
    hostView = DesktopMemoryHostView(frame: NSRect(origin: .zero, size: DesktopMemoryMetrics.windowSize))
    hostView.autoresizingMask = [.width, .height]
    panel.contentView = hostView
    hostView.onClick = { [weak self] in self?.openHUD() }
    hostView.onDragEnded = { [weak self] in self?.snapAfterDrag() }
    hostView.menuProvider = { [weak self] in self?.makeMenu() }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.place(animated: false) }
    }
    update()
    observe()
  }

  deinit {
    artworkTask?.cancel()
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
    }
  }

  // MARK: - Observation

  private func observe() {
    guard let coord else { return }
    withObservationTracking {
      _ = inputs(from: coord)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.update()
        self?.observe()
      }
    }
  }

  private func inputs(from coord: AppCoordinator) -> Inputs {
    let settings = coord.settings
    let track = coord.menubar.track
    // A new track's memory lands a moment after the track; until it does,
    // the aggregates still describe the previous track.
    let fresh = track != nil && coord.aggregatesTrackUri == track?.uri
    let aggregates = fresh
      ? DesktopMemoryContent.Aggregates(
        insight: coord.aggCache.currentBadgeInsight,
        playsYTD: coord.aggCache.playsYTD,
        lastPlayedAt: coord.aggCache.lastPlayedAt)
      : nil
    return Inputs(
      enabled: settings.showDesktopMemory,
      state: coord.menubar.state,
      track: track,
      aggregates: aggregates,
      enabledCategories: settings.enabledBadgeCategories,
      theme: coord.readoutTheme,
      corner: settings.desktopMemoryCorner,
      displayID: settings.desktopMemoryDisplayID)
  }

  private func update() {
    guard let coord else { return }
    let inputs = inputs(from: coord)
    guard inputs.enabled else {
      artworkTask?.cancel()
      artworkTask = nil
      artworkURL = nil
      panel.orderOut(nil)
      return
    }

    let next = DesktopMemoryContent(
      state: inputs.state,
      track: inputs.track,
      aggregates: inputs.aggregates,
      enabledCategories: inputs.enabledCategories,
      previous: content)
    content = next
    theme = inputs.theme
    loadArtwork(for: next.track?.artUrl)
    render()
    place(animated: false)
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  // MARK: - Drawing

  private func render() {
    guard let content else { return }
    hostView.setContent(
      DesktopMemoryView(content: content, artwork: artwork, onOpen: openHUD)
        .environment(\.dialTheme, theme)
        .preferredColorScheme(.dark))
  }

  private func loadArtwork(for url: String?) {
    guard url != artworkURL else { return }
    artworkURL = url
    artworkTask?.cancel()
    artworkTask = nil
    guard let url, let cache = coord?.artworkCache else {
      artwork = nil
      return
    }
    if let cached = cache.image(for: url) {
      artwork = cached
      return
    }
    artwork = nil
    artworkTask = Task { [weak self] in
      let image = await cache.load(url)
      guard !Task.isCancelled, let self, self.artworkURL == url else { return }
      self.artwork = image
      self.artworkTask = nil
      self.render()
    }
  }

  // MARK: - Placement

  private func place(animated: Bool) {
    guard let settings = coord?.settings,
          let screen = Self.screen(for: settings.desktopMemoryDisplayID)
    else { return }
    let frame = placement.frame(corner: settings.desktopMemoryCorner, in: screen.visibleFrame)
    guard frame != targetFrame else { return }
    move(to: frame, animated: animated)
  }

  private func snapAfterDrag() {
    guard let settings = coord?.settings else { return }
    let screens = NSScreen.screens
    guard let index = DesktopMemoryPlacement.displayIndex(
      for: panel.frame, among: screens.map(\.visibleFrame))
    else { return }
    let visible = screens[index].visibleFrame
    let corner = DesktopMemoryPlacement.nearestCorner(to: panel.frame, in: visible)
    move(to: placement.frame(corner: corner, in: visible), animated: true)
    settings.desktopMemoryCorner = corner
    // 0 follows whichever display is main; others are remembered by ID.
    settings.desktopMemoryDisplayID = index == 0 ? 0 : (screens[index].dialDisplayID ?? 0)
  }

  private func move(to frame: CGRect, animated: Bool) {
    targetFrame = frame
    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      panel.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(frame, display: true)
    }
  }

  /// The saved display, or the main display (the one with the menu bar)
  /// when it's 0 or no longer connected.
  private static func screen(for displayID: UInt32) -> NSScreen? {
    let screens = NSScreen.screens
    return screens.first { displayID != 0 && $0.dialDisplayID == displayID } ?? screens.first
  }

  // MARK: - Menu

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem(title: "Open Dial") { [weak self] in self?.openHUD() })
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem(title: "Hide Desktop Memory") { [weak self] in
      self?.coord?.settings.showDesktopMemory = false
    })
    return menu
  }
}

private final class DesktopMemoryPanel: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(origin: .zero, size: DesktopMemoryMetrics.windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true)
    isOpaque = false
    backgroundColor = .clear
    // The chassis draws its own contact shadow.
    hasShadow = false
    // Above the desktop and its icons, below every app window.
    level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
    // Every Space, still through Mission Control and Show Desktop, never
    // in the window cycle.
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    // Dragging is handled by the content view so it can snap on release.
    isMovable = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    isExcludedFromWindowsMenu = true
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI object and owns every mouse event itself: a click
/// opens the HUD, a drag moves the window, a right-click shows the menu.
/// Only the chassis takes the mouse, not the shadow margin around it.
/// VoiceOver's press skips this view and goes to the SwiftUI element,
/// which opens the HUD through its own action.
private final class DesktopMemoryHostView: NSView {
  private static let dragThreshold: CGFloat = 3

  var onClick: (() -> Void)?
  var onDragEnded: (() -> Void)?
  var menuProvider: (() -> NSMenu?)?
  private var host: NSHostingView<AnyView>?
  private var dragStart: (mouse: NSPoint, window: NSPoint)?
  private var dragged = false

  func setContent<V: View>(_ view: V) {
    if let host {
      host.rootView = AnyView(view)
      return
    }
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = bounds
    host.autoresizingMask = [.width, .height]
    addSubview(host)
    self.host = host
  }

  private var chassisRect: NSRect {
    bounds.insetBy(dx: DesktopMemoryMetrics.shadowMargin, dy: DesktopMemoryMetrics.shadowMargin)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // `point` is in the superview's coordinates.
    chassisRect.contains(convert(point, from: superview)) ? self : nil
  }

  /// VoiceOver finds what's under the pointer with an accessibility hit
  /// test. `hitTest` returns this view, which VoiceOver skips, so the test
  /// would land on the window; send it to the SwiftUI element instead.
  override func accessibilityHitTest(_ point: NSPoint) -> Any? {
    host?.accessibilityHitTest(point) ?? super.accessibilityHitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    dragStart = (NSEvent.mouseLocation, window.frame.origin)
    dragged = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window, let dragStart else { return }
    let mouse = NSEvent.mouseLocation
    let dx = mouse.x - dragStart.mouse.x
    let dy = mouse.y - dragStart.mouse.y
    if !dragged, (dx * dx + dy * dy).squareRoot() < Self.dragThreshold { return }
    dragged = true
    window.setFrameOrigin(NSPoint(x: dragStart.window.x + dx, y: dragStart.window.y + dy))
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      dragStart = nil
      dragged = false
    }
    if dragged {
      onDragEnded?()
    } else if chassisRect.contains(convert(event.locationInWindow, from: nil)) {
      onClick?()
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let menu = menuProvider?() else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  override func resetCursorRects() {
    addCursorRect(chassisRect, cursor: .pointingHand)
  }
}

/// A menu item that runs a closure, for menus owned by non-NSObject types.
private final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  @objc private func fire() { handler() }
}

private extension NSScreen {
  var dialDisplayID: UInt32? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
}
