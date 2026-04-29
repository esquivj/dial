import SwiftUI
import AppKit

struct ArtifactSprite: View {
  let kind: ArtifactKind
  var color: Color = Dial.Palette.accent
  var size: CGFloat = 24

  var body: some View {
    ResourceTemplateSprite(
      name: kind.rawValue,
      subdirectory: "Artifacts",
      color: color,
      size: size)
      .accessibilityLabel(kind.label)
  }
}

struct RoomObjectSprite: View {
  let name: String
  var color: Color = Color.black.opacity(0.82)
  var size: CGFloat

  var body: some View {
    ResourceTemplateSprite(
      name: name,
      subdirectory: "RoomObjects",
      color: color,
      size: size)
      .accessibilityHidden(true)
  }
}

private struct ResourceTemplateSprite: View {
  let name: String
  let subdirectory: String
  let color: Color
  let size: CGFloat

  var body: some View {
    if let image = Self.load(named: name, subdirectory: subdirectory) {
      Image(nsImage: image)
        .renderingMode(.template)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .foregroundStyle(color)
        .frame(width: size, height: size)
    } else {
      missingSprite
    }
  }

  private var missingSprite: some View {
    RoundedRectangle(cornerRadius: Dial.Radius.pixel)
      .stroke(color.opacity(0.75), lineWidth: 1)
      .frame(width: size, height: size)
      .overlay(
        Text("?")
          .font(Dial.Typography.monoTiny)
          .foregroundStyle(color)
      )
      .accessibilityHidden(true)
  }

  private static func load(named name: String, subdirectory: String) -> NSImage? {
    let cacheKey = "\(subdirectory)/\(name)"
    if let cached = cache[cacheKey] { return cached }
    let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
      ?? Bundle.main.url(forResource: name, withExtension: "png")
    guard let url, let img = NSImage(contentsOf: url) else { return nil }
    img.isTemplate = true
    cache[cacheKey] = img
    return img
  }

  private static var cache: [String: NSImage] = [:]
}
