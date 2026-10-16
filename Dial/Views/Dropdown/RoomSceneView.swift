import SwiftUI

struct RoomSceneView: View {
  let pet: PetViewModel
  let behavior: PetBehavior
  var featuredObjectName: String? = nil
  let notesActive: Bool
  let actionPulse: Bool
  @Environment(\.dialTheme) private var theme

  private var roomInk: Color { Color.black.opacity(0.82) }
  private var roomSoftInk: Color { Color.black.opacity(0.30) }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .fill(theme.lcd)

      LCDScanlines(pitch: 3, opacity: 0.08, color: .black)
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))

      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height

        roomLayer(width: w, height: h)

        BulldogSprite(stage: pet.stage, behavior: behavior, height: 66, matteColor: theme.lcd)
          .frame(width: 78, height: 78)
          .scaleEffect(
            x: actionPulse ? 1.035 : 1,
            y: actionPulse ? 0.965 : 1,
            anchor: .bottom)
          .offset(y: actionPulse ? 2 : 0)
          .position(x: w * 0.52, y: h * 0.65)
      }
      .padding(6)
    }
    .frame(maxWidth: .infinity)
    .frame(height: Dial.Layout.PetScreen.roomSceneHeight)
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

  private func roomLayer(width w: CGFloat, height h: CGFloat) -> some View {
    ZStack {
      roomBackdrop(width: w, height: h)
      RoomPixelWindow(ink: roomInk, softInk: roomSoftInk)
        .frame(width: 112, height: 46)
        .position(x: w * 0.25, y: h * 0.31)
      roomObject("rug", size: 74, x: w * 0.52, y: h * 0.87)
      roomObject(featuredRoomObject, size: featuredRoomObjectSize, x: w * 0.82, y: h * 0.79)
      HifiMusicNotes(active: notesActive, emphasis: actionPulse, ink: roomInk)
        .frame(width: 72, height: 44)
        .position(x: w * 0.75, y: h * 0.52)
    }
  }

  private var featuredRoomObject: String {
    guard let featuredObjectName else { return "mcm_hifi_console" }
    switch featuredObjectName {
    case "window", "rug":
      return "mcm_hifi_console"
    default:
      return featuredObjectName
    }
  }

  private var featuredRoomObjectSize: CGFloat {
    switch featuredRoomObject {
    case "desk_lamp", "cone_floor_lamp":
      return 62
    case "speaker", "stereo", "record_cube":
      return 54
    case "plant":
      return 50
    default:
      return 58
    }
  }

  private func roomBackdrop(width: CGFloat, height: CGFloat) -> some View {
    Path { path in
      path.move(to: CGPoint(x: width * 0.08, y: height * 0.76))
      path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.76))
      path.move(to: CGPoint(x: width * 0.34, y: height * 0.78))
      path.addLine(to: CGPoint(x: width * 0.23, y: height * 0.95))
      path.move(to: CGPoint(x: width * 0.70, y: height * 0.78))
      path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.95))
    }
    .stroke(Color.black.opacity(0.16), lineWidth: 1)
    .allowsHitTesting(false)
  }
}

private struct HifiMusicNotes: View {
  let active: Bool
  let emphasis: Bool
  let ink: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dialFrozenDate) private var frozenDate

  var body: some View {
    Group {
      if active {
        if reduceMotion {
          note(index: 0, progress: 0.58, emphasis: false)
        } else {
          TimelineView(.animation(minimumInterval: 1 / 10)) { timeline in
            let time = (frozenDate ?? timeline.date).timeIntervalSinceReferenceDate
            let noteCount = emphasis ? 3 : 2
            let cycle = emphasis ? 1.55 : 2.8
            let spacing = emphasis ? 0.24 : 0.43
            ZStack {
              ForEach(0..<noteCount, id: \.self) { index in
                let progress = (time / cycle + Double(index) * spacing)
                  .truncatingRemainder(dividingBy: 1)
                note(index: index, progress: progress, emphasis: emphasis)
              }
            }
          }
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func note(index: Int, progress: Double, emphasis: Bool) -> some View {
    let xOffsets: [CGFloat] = [10, 3, 15]
    let yOffsets: [CGFloat] = [0, 6, 11]
    let sizes: [CGFloat] = [7, 6, 5]
    let progressValue = CGFloat(progress)
    let rise = progressValue * (emphasis ? 26 : 22)
    let drift = progressValue * (emphasis ? 40 : 34)
    let fade = sin(progress * .pi)
    let opacity = max(0, min(1, fade)) * (emphasis ? 0.66 : 0.48)

    return PixelMusicNote(size: sizes[index], ink: ink.opacity(opacity))
      .position(
        x: 55 - drift + xOffsets[index],
        y: 34 - rise + yOffsets[index])
  }
}

private struct PixelMusicNote: View {
  let size: CGFloat
  let ink: Color

  private let pixels: [(x: Int, y: Int)] = [
    (4, 0), (5, 0),
    (5, 1), (5, 2), (5, 3), (5, 4), (5, 5),
    (4, 5), (3, 5),
    (1, 5), (2, 5),
    (0, 6), (1, 6), (2, 6),
    (0, 7), (1, 7), (2, 7),
  ]

  var body: some View {
    let unit = max(1, floor(size / 6))
    ZStack {
      ForEach(Array(pixels.enumerated()), id: \.offset) { _, pixel in
        Rectangle()
          .fill(ink)
          .frame(width: unit, height: unit)
          .position(
            x: CGFloat(pixel.x) * unit + unit / 2,
            y: CGFloat(pixel.y) * unit + unit / 2)
      }
    }
    .frame(width: unit * 6, height: unit * 8)
  }
}

private struct RoomPixelWindow: View {
  let ink: Color
  let softInk: Color

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      let frame: CGFloat = 4
      let paneGap: CGFloat = 4

      ZStack {
        Rectangle()
          .fill(softInk.opacity(0.22))
          .frame(width: w, height: h)
          .overlay(
            Rectangle()
              .stroke(ink.opacity(0.82), lineWidth: frame)
          )

        HStack(spacing: paneGap) {
          windowPane
          windowPane
        }
        .padding(frame + paneGap)

        Rectangle()
          .fill(ink.opacity(0.82))
          .frame(width: frame, height: h - frame)

        Rectangle()
          .fill(ink.opacity(0.62))
          .frame(width: w + 8, height: 2)
          .position(x: w * 0.5, y: h + 3)
      }
    }
    .accessibilityHidden(true)
  }

  private var windowPane: some View {
    ZStack {
      Rectangle()
        .stroke(ink.opacity(0.75), lineWidth: 2)
      Rectangle()
        .fill(ink.opacity(0.36))
        .frame(width: 2)
      Rectangle()
        .fill(ink.opacity(0.26))
        .frame(height: 2)
    }
  }
}
