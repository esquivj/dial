// Dial/App/MemoryPopupController.swift
import AppKit
import SwiftUI

/// Shows the floating LCD strip under the status item: the memory pop-up
/// (`MemoryPopupView`, about 4 s) or a hotkey flash (`HotkeyFlashView`,
/// about 1 s). Both share this one panel, so they never stack; see
/// `ReadoutStripSchedule` for how a new readout replaces the current one.
///
/// The strip never takes focus and never activates Dial: it's a
/// borderless non-activating panel that can't become key. The only thing
/// it reacts to is a click, which opens the HUD. It slides down a few
/// points while fading in, holds, then fades out. With Reduce Motion on it
/// only fades.
final class MemoryPopupController {
  struct Timing {
    let fadeIn: TimeInterval
    let hold: TimeInterval
    let fadeOut: TimeInterval
    let slide: CGFloat

    static let memory = Timing(fadeIn: 0.22, hold: 4, fadeOut: 0.35, slide: 6)
    static let flash = Timing(fadeIn: 0.12, hold: 0.9, fadeOut: 0.25, slide: 4)
  }

  static let gapBelowMenuBar: CGFloat = 4

  var onClick: (() -> Void)?

  private let panel: MemoryPopupPanel
  private let clickView: MemoryPopupClickView
  private var hideTimer: Timer?
  private var schedule = ReadoutStripSchedule()
  /// Bumped on every show/dismiss so a finished fade-out from an older
  /// pop-up can't order out a newer one.
  private var generation = 0
  private var currentFadeOut: TimeInterval = Timing.memory.fadeOut

  var isVisible: Bool { panel.isVisible }

  init() {
    let size = MemoryPopupView.size
    panel = MemoryPopupPanel(size: size)
    clickView = MemoryPopupClickView(frame: NSRect(origin: .zero, size: size))
    clickView.autoresizingMask = [.width, .height]
    panel.contentView = clickView
    clickView.onClick = { [weak self] in
      self?.dismiss(animated: false)
      self?.onClick?()
    }
  }

  /// - Parameter anchor: the status item button's frame in screen coordinates.
  func show(_ content: MemoryPopupContent, theme: DialTheme, below anchor: NSRect, on screen: NSScreen?) {
    present(
      .memory,
      view: MemoryPopupView(content: content),
      size: MemoryPopupView.size,
      timing: .memory,
      theme: theme,
      below: anchor,
      on: screen)
  }

  func flash(_ content: HotkeyFlashContent, theme: DialTheme, below anchor: NSRect, on screen: NSScreen?) {
    present(
      .flash,
      view: HotkeyFlashView(content: content),
      size: HotkeyFlashView.size,
      timing: .flash,
      theme: theme,
      below: anchor,
      on: screen)
  }

  private func present<V: View>(
    _ kind: ReadoutStripSchedule.Kind,
    view: V,
    size: CGSize,
    timing: Timing,
    theme: DialTheme,
    below anchor: NSRect,
    on screen: NSScreen?
  ) {
    let presentation = schedule.present(kind, hold: timing.fadeIn + timing.hold, at: Date())
    generation += 1
    hideTimer?.invalidate()
    currentFadeOut = timing.fadeOut

    clickView.setContent(
      view
        .environment(\.dialTheme, theme)
        .preferredColorScheme(.dark))

    var x = anchor.midX - size.width / 2
    let y = anchor.minY - size.height - Self.gapBelowMenuBar
    if let visible = screen?.visibleFrame {
      x = max(visible.minX + 4, min(visible.maxX - size.width - 4, x))
    }
    let finalFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

    switch presentation {
    case .updateInPlace where panel.isVisible:
      panel.setFrame(finalFrame, display: true)
      panel.alphaValue = 1
    case .appear, .updateInPlace:
      let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      let startFrame = reduceMotion ? finalFrame : finalFrame.offsetBy(dx: 0, dy: timing.slide)
      panel.setFrame(startFrame, display: false)
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = timing.fadeIn
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
        if !reduceMotion {
          panel.animator().setFrame(finalFrame, display: true)
        }
      }
    }

    hideTimer = Timer.scheduledTimer(withTimeInterval: timing.fadeIn + timing.hold, repeats: false) { [weak self] _ in
      self?.dismiss(animated: true)
    }
  }

  func dismiss(animated: Bool) {
    hideTimer?.invalidate()
    hideTimer = nil
    schedule.hidden()
    guard panel.isVisible else { return }
    generation += 1
    let token = generation
    guard animated else {
      panel.orderOut(nil)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = currentFadeOut
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      guard let self, self.generation == token else { return }
      self.panel.orderOut(nil)
    }
  }
}

private final class MemoryPopupPanel: NSPanel {
  init(size: NSSize) {
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true)
    isOpaque = false
    backgroundColor = .clear
    // The chassis material paints its own edge and depth.
    hasShadow = false
    // Above regular windows, below the HUD panel (.popUpMenu).
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary, .transient]
    isMovable = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI strip but owns every mouse event itself, so a click
/// anywhere on the strip opens the HUD and nothing inside reacts to hover.
private final class MemoryPopupClickView: NSView {
  var onClick: (() -> Void)?
  private var host: NSHostingView<AnyView>?

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

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // `point` is in the superview's coordinates, like `frame`.
    frame.contains(point) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onClick?()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }
}
