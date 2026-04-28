// Dial/DesignSystem/DialIcon.swift
import SwiftUI
import AppKit

/// Template icon loader for Dial's functional chrome.
///
/// The chrome uses selected Iconoir glyphs rendered to template PNGs. Pixel
/// art is intentionally reserved for the pet, badges, and LCD artifacts; the
/// transport/nav/settings controls need to read like a real macOS utility
/// embedded in a Y2K device.
///
/// **Naming.** PNG filenames mirror SF Symbol names (`shuffle`, `repeat.1`,
/// `flame.fill`, …) so the swap at call sites is `Image(systemName: "x")`
/// → `DialIcon("x")` — same string, different prefix.
///
/// **Tinting.** PNGs ship as solid black on transparent. `NSImage.isTemplate`
/// is set true on load, which makes SwiftUI treat the image's alpha as a
/// mask and fill the opaque pixels with the current `foregroundStyle`.
/// This is the same trick SF Symbols use internally; once the flag is on,
/// `.foregroundStyle(Dial.Palette.accent)` just works.
///
/// **Rendering.** These are not pixel-art assets, so they use SwiftUI's
/// normal interpolation instead of nearest-neighbor scaling.
struct DialIcon: View {
  let name: String

  init(_ name: String) {
    self.name = name
  }

  var body: some View {
    if let nsImage = Self.load(named: name) {
      Image(nsImage: nsImage)
        .resizable()
        .scaledToFit()
    } else {
      // Fallback: render a tinted "?" so missing assets are obvious in
      // dev rather than silently disappearing.
      Text("?")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.red)
    }
  }

  /// Load the named PNG from the bundled `Icons/` subdirectory and mark
  /// it as a template so SwiftUI tints it with the current foreground.
  /// Cached at the type level — these icons are shipped statically and
  /// repeated decode is wasted work in the menubar's hot path.
  private static func load(named name: String) -> NSImage? {
    if let cached = cache[name] { return cached }
    let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons")
      ?? Bundle.main.url(forResource: name, withExtension: "png")  // root fallback
    guard let url, let img = NSImage(contentsOf: url) else { return nil }
    img.isTemplate = true
    cache[name] = img
    return img
  }

  /// Process-wide image cache. NSImage instances are reusable and small;
  /// keeping them around avoids the file-read + alpha-mask pass on every
  /// dropdown re-open.
  private static var cache: [String: NSImage] = [:]
}

/// Fixed-size chrome icon wrapper. Kept as a separate type because transport
/// buttons and small action chips all want the same call-site shape.
struct DialThickIcon: View {
  let name: String
  var size: CGFloat = 14
  var weight: CGFloat = 0.5

  init(_ name: String, size: CGFloat = 14, weight: CGFloat = 0.5) {
    self.name = name
    self.size = size
    self.weight = weight
  }

  var body: some View {
    DialIcon(name)
      .frame(width: size, height: size)
    .frame(width: size, height: size)
  }
}
