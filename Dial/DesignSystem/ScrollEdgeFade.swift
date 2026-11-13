import SwiftUI

/// PLA-108: a scrolling LCD viewport fades out at its bottom edge so it
/// reads as "more below" instead of clipping. Pair `dialScrollFade()` on the
/// ScrollView with `dialScrollFadeInset()` on its content, so the last row
/// clears the fade once you reach the end.
enum ScrollEdgeFade {
  static let height: CGFloat = 16
}

extension View {
  /// Masks the bottom `ScrollEdgeFade.height` points of a scroll viewport.
  func dialScrollFade(height: CGFloat = ScrollEdgeFade.height) -> some View {
    mask {
      VStack(spacing: 0) {
        Rectangle().fill(Color.black)
        LinearGradient(
          colors: [.black, .black.opacity(0)],
          startPoint: .top,
          endPoint: .bottom)
          .frame(height: height)
      }
    }
  }

  /// Bottom room inside the scroll content so the last row ends above the fade.
  func dialScrollFadeInset(height: CGFloat = ScrollEdgeFade.height) -> some View {
    padding(.bottom, height)
  }
}
