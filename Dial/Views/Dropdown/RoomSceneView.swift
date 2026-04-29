import SwiftUI

struct RoomSceneView: View {
  let pet: PetViewModel
  let behavior: PetBehavior
  let artifacts: [Artifact]
  let actionPulse: Bool
  @Environment(\.dialTheme) private var theme

  private var artifactKinds: [ArtifactKind] {
    Array(artifacts.map(\.kind).prefix(2))
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .fill(theme.lcd)

      LCDScanlines(pitch: 3, opacity: 0.08, color: .black)
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))

      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height

        roomBackdrop(width: w, height: h)
        roomShelf(width: w, height: h)
        roomObject("atomic_wall_clock", size: 24, x: w * 0.25, y: h * 0.27)
        roomObject("record_cube", size: 25, x: w * 0.73, y: h * 0.30)
        roomObject("rug", size: 68, x: w * 0.50, y: h * 0.83)
        roomObject("cone_floor_lamp", size: 48, x: w * 0.12, y: h * 0.62)
        roomObject("low_lounge_chair", size: 40, x: w * 0.26, y: h * 0.76)
        roomObject("mcm_hifi_console", size: 52, x: w * 0.80, y: h * 0.77)

        ForEach(Array(artifactKinds.enumerated()), id: \.element) { index, kind in
          ArtifactSprite(kind: kind, color: Color.black.opacity(0.82), size: 15)
            .position(artifactPosition(index: index, width: w, height: h))
        }

        BulldogSprite(stage: pet.stage, behavior: behavior, height: 66)
          .frame(width: 78, height: 78)
          .scaleEffect(actionPulse ? 1.045 : 1)
          .position(x: w * 0.50, y: h * 0.62)
      }
      .padding(6)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 104)
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous),
      fill: theme.lcd,
      edgeOpacity: 0.36,
      fillTopOpacity: 0.07,
      fillBottomOpacity: 0.025,
      sheenOpacity: 0.36,
      sheenLineWidth: 0.9,
      contactShadowOpacity: 0,
      innerShadowOpacity: 0.20)
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous)
        .inset(by: 4)
        .stroke(theme.accent.opacity(0.22), lineWidth: 0.7)
    )
    .shadow(color: Color.black.opacity(0.42), radius: 5, x: 0, y: 2)
  }

  private func roomObject(_ name: String, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
    RoomObjectSprite(name: name, size: size)
      .position(x: x, y: y)
  }

  private func roomBackdrop(width: CGFloat, height: CGFloat) -> some View {
    Path { path in
      path.move(to: CGPoint(x: width * 0.08, y: height * 0.76))
      path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.76))
      path.move(to: CGPoint(x: width * 0.36, y: height * 0.79))
      path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.95))
      path.move(to: CGPoint(x: width * 0.64, y: height * 0.79))
      path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.95))
    }
    .stroke(Color.black.opacity(0.16), lineWidth: 1)
    .allowsHitTesting(false)
  }

  private func roomShelf(width: CGFloat, height: CGFloat) -> some View {
    ZStack {
      Rectangle()
        .fill(Color.black.opacity(0.58))
        .frame(width: width * 0.24, height: 2)
        .position(x: width * 0.81, y: height * 0.42)
      Rectangle()
        .fill(Color.black.opacity(0.42))
        .frame(width: 2, height: 7)
        .position(x: width * 0.71, y: height * 0.46)
      Rectangle()
        .fill(Color.black.opacity(0.42))
        .frame(width: 2, height: 7)
        .position(x: width * 0.91, y: height * 0.46)
    }
    .allowsHitTesting(false)
  }

  private func artifactPosition(index: Int, width: CGFloat, height: CGFloat) -> CGPoint {
    let points = [
      CGPoint(x: width * 0.82, y: height * 0.32),
      CGPoint(x: width * 0.89, y: height * 0.32),
    ]
    return points[min(index, points.count - 1)]
  }
}
