// Dial/App/StatusBarController.swift
import AppKit
import SwiftUI

/// Owns the `NSStatusItem` (the menubar strip) and the `NSPopover` (the
/// dropdown). The status item's button hosts a SwiftUI `MenubarStripView`;
/// the popover hosts the SwiftUI `DropdownView`. Both surfaces read from
/// the shared `AppCoordinator` so they animate in lockstep.
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
      button.action = #selector(togglePopover)
      button.target = self
    }
  }

  @objc private func togglePopover() {
    guard let button = item.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
}
