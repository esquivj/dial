import AppKit
import Observation

@MainActor
final class DockIconController {
  private static let iconCanvasSize: CGFloat = 1024
  private static let iconArtworkInset: CGFloat = 88
  private static let iconCornerRadius: CGFloat = 198

  private weak var coord: AppCoordinator?
  private let systemFallbackIcon: NSImage
  private let idleDockIcon: NSImage
  private var artworkTask: Task<Void, Never>?
  private var currentArtworkKey: String?

  init(coord: AppCoordinator) {
    self.coord = coord
    self.systemFallbackIcon = NSApp.applicationIconImage ?? Self.makeFallbackIcon()
    self.idleDockIcon = Self.makeIdleDockIcon()
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
      NSApp.applicationIconImage = systemFallbackIcon
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
      NSApp.applicationIconImage = idleDockIcon
      return
    }

    let key = "\(track.uri)|\(artUrl)"
    guard key != currentArtworkKey else { return }
    currentArtworkKey = key
    artworkTask?.cancel()
    artworkTask = Task { [weak self] in
      let source = await self?.coord?.artworkCache.load(artUrl)
      guard !Task.isCancelled else { return }
      let icon = source.map(Self.makeArtworkIcon(from:)) ?? self?.idleDockIcon
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

  private static func makeIdleDockIcon() -> NSImage {
    if let brandIcon = loadBrandDockIcon() {
      return brandIcon
    }

    return makeFallbackIcon()
  }

  private static func loadBrandDockIcon() -> NSImage? {
    let image = Bundle.main.url(forResource: "dial-app-icon", withExtension: "png", subdirectory: "Brand")
      .flatMap(NSImage.init(contentsOf:))
      ?? Bundle.main.url(forResource: "dial-app-icon", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
    image?.size = NSSize(width: iconCanvasSize, height: iconCanvasSize)
    image?.isTemplate = false
    return image
  }

  private static func makeFallbackIcon() -> NSImage {
    if let brandIcon = loadBrandDockIcon() {
      return brandIcon
    }

    let canvas = NSSize(width: iconCanvasSize, height: iconCanvasSize)
    let image = NSImage(size: canvas)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    let rect = iconArtworkRect
    let path = NSBezierPath(roundedRect: rect, xRadius: iconCornerRadius, yRadius: iconCornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.set()
    NSColor(calibratedRed: 0.018, green: 0.037, blue: 0.050, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = rect.insetBy(dx: 148, dy: 148)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 112, yRadius: 112)
    NSColor(calibratedRed: 0.71, green: 0.73, blue: 0.57, alpha: 1).setFill()
    screenPath.fill()

    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    NSColor.black.withAlphaComponent(0.08).setStroke()
    for y in stride(from: screen.minY + 18, through: screen.maxY - 18, by: 18) {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: screen.minX, y: y))
      line.line(to: NSPoint(x: screen.maxX, y: y))
      line.lineWidth = 2
      line.stroke()
    }

    if let pet = Bundle.main.url(forResource: "companion-idle", withExtension: "png", subdirectory: "Pets")
      .flatMap(NSImage.init(contentsOf:))
    {
      NSGraphicsContext.current?.imageInterpolation = .none
      pet.draw(in: NSRect(x: screen.midX - 236, y: screen.midY - 256, width: 472, height: 472),
               from: NSRect(origin: .zero, size: pet.size),
               operation: .sourceOver,
               fraction: 1)
    } else if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 330, weight: .bold))
    {
      note.isTemplate = true
      NSColor.black.withAlphaComponent(0.72).set()
      note.draw(in: NSRect(x: screen.midX - 156, y: screen.midY - 188, width: 312, height: 360))
    }
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.18).setStroke()
    screenPath.lineWidth = 3
    screenPath.stroke()

    NSColor.white.withAlphaComponent(0.14).setStroke()
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
