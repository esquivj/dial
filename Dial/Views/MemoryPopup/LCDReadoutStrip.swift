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
    LCDReadoutWell(cornerRadius: Dial.Radius.panel - LCDReadoutStripMetrics.bezelInset / 2) {
      content
    }
    .padding(LCDReadoutStripMetrics.bezelInset)
    .frame(width: size.width, height: size.height)
    .dialChassisPlastic(shape: bezel)
  }
}

/// The recessed LCD inside a readout, without the bezel around it. The
/// readout strip wraps it in its own bezel; the desktop memory object sets
/// it into its chassis under the album art.
struct LCDReadoutWell<Content: View>: View {
  let cornerRadius: CGFloat
  @ViewBuilder let content: Content

  init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    content
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .overlay { LCDScanlines(opacity: 0.08) }
      .modifier(RecessedScreen(depth: 0.45, height: 8))
      .lcdPanel(cornerRadius: cornerRadius)
  }
}

enum LCDReadoutStripMetrics {
  static let bezelInset: CGFloat = 4
}
