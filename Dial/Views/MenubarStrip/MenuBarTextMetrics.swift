import AppKit
import SwiftUI

enum MenuBarTextMetrics {
  static let fontName = "GeistMono-Medium"
  static let fontSize: CGFloat = 12
  static let kerning: CGFloat = 0.18
  static let lineHeight: CGFloat = 20
  static let minimumWidth: CGFloat = 18
  static let brandFontSize: CGFloat = 13.5
  static let brandKerning: CGFloat = 1.0
  static let brandWidth: CGFloat = 43
  static let minimumSettingWidth: Double = 80
  static let maximumSettingWidth: Double = 190
  static let defaultMaxWidth: Double = 160

  static var font: Font {
    .custom(fontName, size: fontSize)
  }

  static func width(for text: String, max maxWidth: CGFloat) -> CGFloat {
    let clampedMax = CGFloat(clampedSettingWidth(Double(maxWidth)))
    return min(clampedMax, max(minimumWidth, naturalWidth(for: text)))
  }

  /// The width `text` needs to show in full, before the user's cap.
  static func naturalWidth(for text: String) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [
      .font: appKitFont,
      .kern: kerning,
    ]).width) + 2
  }

  static func clampedSettingWidth(_ value: Double) -> Double {
    min(maximumSettingWidth, max(minimumSettingWidth, value))
  }

  private static var appKitFont: NSFont {
    NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .medium)
  }
}
