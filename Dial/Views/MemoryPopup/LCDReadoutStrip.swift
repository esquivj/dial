import SwiftUI

/// The small piece of Dial hardware the floating readouts share: one
/// smoked-plastic bezel around one recessed LCD. The memory pop-up and the
/// hotkey flash both draw their text inside it, so they always read as the
/// same object.
struct LCDReadoutStrip<Content: View>: View {
  let size: CGSize
  @ViewBuilder let content: Content

  init(size: CGSize, @ViewBuilder content: () -> Content) {
    self.size = size
    self.content = content()
  }

  var body: some View {
    let bezel = RoundedRectangle(cornerRadius: Dial.Radius.lcd, style: .continuous)
    content
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .overlay { LCDScanlines(opacity: 0.08) }
      .modifier(RecessedScreen(depth: 0.45, height: 8))
      .lcdPanel(cornerRadius: Dial.Radius.panel - LCDReadoutStripMetrics.bezelInset / 2)
      .padding(LCDReadoutStripMetrics.bezelInset)
      .frame(width: size.width, height: size.height)
      .dialChassisPlastic(shape: bezel)
  }
}

enum LCDReadoutStripMetrics {
  static let bezelInset: CGFloat = 4
}
