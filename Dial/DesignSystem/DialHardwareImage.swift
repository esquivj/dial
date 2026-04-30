import AppKit
import SwiftUI

struct DialHardwareImage: View {
  let name: String
  var interpolation: Image.Interpolation = .high

  var body: some View {
    if let image = Self.load(named: name) {
      Image(nsImage: image)
        .interpolation(interpolation)
        .resizable()
    } else {
      Color.clear
    }
  }

  private static func load(named name: String) -> NSImage? {
    if let cached = cache[name] { return cached }
    let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Hardware")
      ?? Bundle.main.url(forResource: name, withExtension: "png")
    guard let url, let image = NSImage(contentsOf: url) else { return nil }
    cache[name] = image
    return image
  }

  private static var cache: [String: NSImage] = [:]
}
