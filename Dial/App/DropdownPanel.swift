// Dial/App/DropdownPanel.swift
import AppKit
import SwiftUI

/// Custom borderless `NSPanel` that hosts the dropdown SwiftUI view.
/// Replaces `NSPopover` so we can fully control the window shape and
/// chrome — specifically:
///
///   * **No system menubar-arrow tip.** `NSPopover` always renders one;
///     a panel just renders whatever we paint inside it.
///   * **Custom corner radii / shadow / glow.** The SwiftUI content
///     paints its own rounded device body, outer halo, etc. The panel
///     is transparent + shadowless so the system doesn't double up.
///   * **Future shape flexibility.** A bigger device outline, a hanging
///     loop, asymmetric corners — all become tractable now that the
///     window background is `.clear` and our SwiftUI content owns the
///     visible surface.
///
/// `.nonactivatingPanel` lets the panel receive key events (e.g. the
/// escape-to-dismiss handler) without making Dial the active app — the
/// menubar should never steal focus from the user's foreground window.
///
/// Lifecycle (show/hide, click-outside dismiss, ESC dismiss) is managed
/// externally by `StatusBarController` via `NSEvent` monitors.
final class DropdownPanel: NSPanel {
  init<Content: View>(rootView: Content, size: NSSize) {
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    // Transparent window background — our SwiftUI content paints the
    // entire visible surface (device body + chrome). Pixels outside the
    // SwiftUI clip mask are see-through, but since the SwiftUI content
    // fills the panel's content area exactly, there's no "outside" to
    // see — the panel's bounds are the device bounds.
    self.isOpaque = false
    self.backgroundColor = .clear

    // No system shadow — our SwiftUI content paints its own outer mint
    // halo + bevel. A system shadow would follow the rectangular
    // bounding box (hard corners) and double up with our soft glow.
    self.hasShadow = false

    // Float above the user's foreground app's regular windows, below
    // modal dialogs / Spotlight / system overlays. `.popUpMenu` is the
    // canonical level for menubar-attached overlays.
    self.level = .popUpMenu

    // Visible on every space + full-screen app, never appears in window
    // cycle (cmd-`) or Mission Control thumbnails. `.stationary` keeps
    // the panel from following the user when they switch spaces — it
    // stays put under the menubar where it was opened.
    self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]

    // Lock the panel in place — it's a menubar dropdown, not a floating
    // tool palette the user can drag around.
    self.isMovableByWindowBackground = false
    self.isMovable = false

    // We manage dismiss manually via NSEvent monitors. Without this,
    // the panel might auto-hide in ways that race with our monitors.
    self.hidesOnDeactivate = false

    // SwiftUI hosting view, pinned to the panel's content area so the
    // SwiftUI .frame(width:height:) on DropdownView matches the panel
    // size exactly (no flicker on first layout).
    let host = NSHostingView(rootView: rootView)
    host.translatesAutoresizingMaskIntoConstraints = false
    let cv = NSView()
    cv.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
      host.topAnchor.constraint(equalTo: cv.topAnchor),
      host.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
    ])
    self.contentView = cv
  }

  // Allow the panel to receive keyboard focus (for the escape-to-dismiss
  // monitor) while still being non-activating — clicks don't focus the
  // app, but typing reaches our content.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
