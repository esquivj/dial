import AppKit
import SwiftUI

enum MenuBarTextMetrics {
  static let fontName = "IBMPlexSans-Medium"
  static let fontSize: CGFloat = 13
  static let kerning: CGFloat = 0.25
  static let lineHeight: CGFloat = 22
  static let minimumWidth: CGFloat = 18
  static let defaultMaxWidth: Double = 260

  static var font: Font {
    .custom(fontName, size: fontSize)
  }

  static func width(for text: String, max maxWidth: CGFloat) -> CGFloat {
    let rawWidth = ceil((text as NSString).size(withAttributes: [
      .font: appKitFont,
      .kern: kerning,
    ]).width)
    return min(maxWidth, max(minimumWidth, rawWidth + 2))
  }

  private static var appKitFont: NSFont {
    NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .medium)
  }
}
