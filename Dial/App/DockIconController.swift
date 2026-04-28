import AppKit
import Observation

@MainActor
final class DockIconController {
  private static let iconCanvasSize: CGFloat = 1024
  private static let iconArtworkInset: CGFloat = 88
  private static let iconCornerRadius: CGFloat = 198

  private weak var coord: AppCoordinator?
  private let fallbackIcon: NSImage
  private var artworkTask: Task<Void, Never>?
  private var currentArtworkKey: String?

  init(coord: AppCoordinator) {
    self.coord = coord
    self.fallbackIcon = NSApp.applicationIconImage ?? Self.makeFallbackIcon()
    observe()
  }

  deinit {
    artworkTask?.cancel()
  }

  private func observe() {
    guard let coord else { return }
    withObservationTracking {
      _ = coord.settings.showDockArtwork
      _ = coord.menubar.state
      _ = coord.menubar.track?.uri
      _ = coord.menubar.track?.artUrl
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.update()
        self?.observe()
      }
    }
    update()
  }

  private func update() {
    guard let coord else { return }

    guard coord.settings.showDockArtwork else {
      artworkTask?.cancel()
      currentArtworkKey = nil
      NSApp.applicationIconImage = fallbackIcon
      setDockVisible(false)
      return
    }

    setDockVisible(true)

    guard
      coord.menubar.state != .nothingPlaying,
      let track = coord.menubar.track,
      let artUrl = track.artUrl
    else {
      artworkTask?.cancel()
      currentArtworkKey = nil
      NSApp.applicationIconImage = fallbackIcon
      return
    }

    let key = "\(track.uri)|\(artUrl)"
    guard key != currentArtworkKey else { return }
    currentArtworkKey = key
    artworkTask?.cancel()
    artworkTask = Task { [weak self] in
      let source = await self?.coord?.artworkCache.load(artUrl)
      guard !Task.isCancelled else { return }
      let icon = source.map(Self.makeArtworkIcon(from:)) ?? self?.fallbackIcon
      await MainActor.run {
        guard self?.currentArtworkKey == key else { return }
        NSApp.applicationIconImage = icon
      }
    }
  }

  private func setDockVisible(_ visible: Bool) {
    let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
    guard NSApp.activationPolicy() != policy else { return }
    NSApp.setActivationPolicy(policy)
  }

  private static func makeArtworkIcon(from source: NSImage) -> NSImage {
    let canvas = NSSize(width: iconCanvasSize, height: iconCanvasSize)
    let image = NSImage(size: canvas)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    let rect = iconArtworkRect
    let path = NSBezierPath(roundedRect: rect, xRadius: iconCornerRadius, yRadius: iconCornerRadius)

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    NSColor.black.withAlphaComponent(0.22).setFill()
    path.fill()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: rect, from: sourceCropRect(source), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.16).setStroke()
    path.lineWidth = 2
    path.stroke()

    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private static func makeFallbackIcon() -> NSImage {
    let canvas = NSSize(width: iconCanvasSize, height: iconCanvasSize)
    let image = NSImage(size: canvas)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    let rect = iconArtworkRect
    let path = NSBezierPath(roundedRect: rect, xRadius: iconCornerRadius, yRadius: iconCornerRadius)
    NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.07, alpha: 1).setFill()
    path.fill()

    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 330, weight: .bold))
    {
      note.isTemplate = true
      NSColor.white.withAlphaComponent(0.92).set()
      note.draw(in: NSRect(x: 342, y: 318, width: 340, height: 388))
    }

    NSColor.white.withAlphaComponent(0.18).setStroke()
    path.lineWidth = 2
    path.stroke()

    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private static var iconArtworkRect: NSRect {
    let size = iconCanvasSize - (iconArtworkInset * 2)
    return NSRect(x: iconArtworkInset, y: iconArtworkInset, width: size, height: size)
  }

  private static func sourceCropRect(_ source: NSImage) -> NSRect {
    let size = source.size
    guard size.width > 0, size.height > 0 else { return .zero }
    let side = min(size.width, size.height)
    return NSRect(
      x: (size.width - side) / 2,
      y: (size.height - side) / 2,
      width: side,
      height: side)
  }
}
