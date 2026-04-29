// Dial/Views/PixelSprite/BulldogSprite.swift
import SwiftUI

/// Image-based pet renderer. Replaces `PixelSprite` for the new mint-teal
/// French bulldog character. Renders the right asset (or 2-frame loop)
/// for a given `(stage, behavior)`. Handles the BPM-driven bob internally
/// when the behavior is `.beatSync`.
///
/// Asset bundling: PNGs ship inside the `Pets/` folder reference declared
/// in `project.yml`, which means SwiftUI's plain `Image(name)` (only
/// searches Asset Catalogs + bundle root) won't find them. The nested
/// `BulldogSpriteImage` helper does an explicit `Bundle.main.url(...)`
/// lookup with `subdirectory: "Pets"`.
///
/// Pixel-art note: every render uses `.interpolation(.none)` so downscaling
/// to menubar size stays crisp instead of getting blurry from bilinear filtering.
struct BulldogSprite: View {
  let stage: PetStage
  let behavior: PetBehavior
  /// Sprite is rendered at this height; width derives from native aspect (~1:1.93 portrait).
  let height: CGFloat

  @State private var bob: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    spriteContent
      .overlay(alignment: .topTrailing) {
        reactionOverlay
      }
      .offset(y: bob)
      .onAppear { syncBob() }
      .onChange(of: bpmKey) { _, _ in syncBob() }
      .onChange(of: reduceMotion) { _, _ in syncBob() }
  }

  // MARK: - Static vs animated frames

  @ViewBuilder
  private var spriteContent: some View {
    let assets = Self.assets(for: stage, behavior: behavior)
    if reduceMotion {
      BulldogSpriteImage(assetName: assets[0], height: height)
    } else if assets.count > 1, let interval = Self.frameInterval(for: behavior) {
      TimelineView(.periodic(from: .now, by: interval)) { ctx in
        let frame = Int(ctx.date.timeIntervalSinceReferenceDate / interval) % assets.count
        BulldogSpriteImage(assetName: assets[frame], height: height)
      }
    } else {
      BulldogSpriteImage(assetName: assets[0], height: height)
    }
  }

  // MARK: - BPM bob

  /// Hashable handle for `onChange` so SwiftUI restarts the bob if the
  /// behavior or its embedded BPM changes.
  private var bpmKey: Double {
    if let bpm = Self.bpm(for: behavior) { return bpm }
    return 0
  }

  private func syncBob() {
    guard !reduceMotion, let bpm = Self.bpm(for: behavior) else {
      bob = 0
      return
    }
    let halfPeriod = max(60.0 / bpm / 2, 0.18)
    withAnimation(.easeInOut(duration: halfPeriod).repeatForever(autoreverses: true)) {
      bob = -2
    }
  }

  @ViewBuilder
  private var reactionOverlay: some View {
    switch Self.overlay(for: behavior) {
    case .some(.sparkles):
      SparklesOverlay(size: height * 0.26)
        .offset(x: height * 0.03, y: -height * 0.03)
    case .some(.thoughtDots):
      ThoughtDotsOverlay(size: height * 0.22)
        .offset(x: height * 0.02, y: height * 0.02)
    case .some(.feeding):
      FeedingOverlay(size: height * 0.24)
        .offset(x: height * 0.02, y: height * 0.05)
    case .some(.sleep):
      SleepOverlay(size: height * 0.22)
        .offset(x: height * 0.02, y: -height * 0.02)
    case .none:
      EmptyView()
    }
  }

  // MARK: - Asset map

  /// Resolve the asset name(s) for a given (stage, behavior). Returns one
  /// name for static poses, two for animated 2-frame loops.
  ///
  /// Stages other than `.companion` don't have behavior variants in the
  /// sheet — they fall back to the stage's only sprite for every behavior.
  static func assets(for stage: PetStage, behavior: PetBehavior) -> [String] {
    switch stage {
    case .egg:        return ["egg"]
    case .hatching:   return ["hatching"]
    case .hatchling:  return ["hatchling"]
    case .juvenile:   return ["juvenile"]
    case .elder:      return ["elder"]
    case .companion:
      switch behavior {
      // Idle is a long static hold with a single-frame blink at the end
      // (~200ms shut-eye every 2s). Implemented by padding the loop with
      // 9 copies of `companion-idle` followed by 1 copy of the blink frame
      // so the existing fixed-interval TimelineView ticker can express the
      // asymmetric rhythm without needing per-frame timings.
      case .idle:         return Array(repeating: "companion-idle", count: 9) + ["companion-idle-blink"]
      case .walk:         return ["companion-walk-a", "companion-walk-b"]
      case .beatSync:     return ["companion-beat-sync"]
      case let .expressed(_, motion):
        return assets(for: motion)
      case .sparkStep:    return ["companion-spark-step-a", "companion-spark-step-b"]
      case .memorySpin:   return ["companion-memory-spin-a", "companion-memory-spin-b"]
      case .beatBounce:   return ["companion-beat-bounce-a", "companion-beat-bounce-b"]
      case .firstListen:  return ["companion-first-listen"]
      case .rediscovered: return ["companion-rediscovered"]
      case .eating:       return ["companion-eating-a", "companion-eating-b"]
      case .paused:       return ["companion-paused"]
      case .dormant:      return ["companion-sleeping-a", "companion-sleeping-b"]
      case .levelUp:      return ["companion-level-up"]
      }
    }
  }

  /// Frame interval for the 2-frame loops. Chosen so total cycle matches
  /// the cadence we mocked in Paper:
  ///   idle     ~2000ms total → 200ms / frame × 10 frames (9 open + 1 blink)
  ///   walk     ~700ms total  → 350ms / frame
  ///   eating   ~600ms        → 300ms / frame
  ///   sleeping ~1500ms       → 750ms / frame
  static func frameInterval(for behavior: PetBehavior) -> Double? {
    switch behavior {
    case .idle:     return 0.20
    case .walk:     return 0.35
    case let .expressed(_, motion): return frameInterval(for: motion)
    case .eating:   return 0.30
    case .dormant:  return 0.75
    case .sparkStep: return 0.24
    case .memorySpin: return 0.30
    case .beatBounce: return 0.22
    default:        return nil
    }
  }

  private static func assets(for motion: PetMotion) -> [String] {
    switch motion {
    case .idle:
      return Array(repeating: "companion-idle", count: 9) + ["companion-idle-blink"]
    case .walk:
      return ["companion-walk-a", "companion-walk-b"]
    case .beatSync:
      return ["companion-beat-sync"]
    }
  }

  private static func frameInterval(for motion: PetMotion) -> Double? {
    switch motion {
    case .idle: return 0.20
    case .walk: return 0.35
    case .beatSync: return nil
    }
  }

  private static func bpm(for behavior: PetBehavior) -> Double? {
    switch behavior {
    case let .beatSync(bpm):
      return bpm
    case let .expressed(_, .beatSync(bpm)):
      return bpm
    default:
      return nil
    }
  }

  private enum OverlayKind {
    case sparkles
    case thoughtDots
    case feeding
    case sleep
  }

  private static func overlay(for behavior: PetBehavior) -> OverlayKind? {
    switch behavior {
    case .firstListen, .levelUp,
         .expressed(.firstListen, motion: _),
         .expressed(.levelUp, motion: _):
      return .sparkles
    case .rediscovered, .expressed(.rediscovered, motion: _):
      return .thoughtDots
    case .eating:
      return .feeding
    case .dormant:
      return .sleep
    default:
      return nil
    }
  }
}

private struct SparklesOverlay: View {
  let size: CGFloat

  var body: some View {
    VStack(spacing: max(1, size * 0.10)) {
      Text("+")
      Text("*")
    }
    .font(.system(size: max(7, size * 0.42), weight: .bold, design: .monospaced))
    .foregroundStyle(Color.black.opacity(0.82))
    .frame(width: size, height: size)
  }
}

private struct ThoughtDotsOverlay: View {
  let size: CGFloat

  var body: some View {
    HStack(spacing: max(1, size * 0.14)) {
      ForEach(0..<3, id: \.self) { idx in
        Circle()
          .fill(Color.black.opacity(0.82))
          .frame(width: size * CGFloat(0.14 + Double(idx) * 0.04),
                 height: size * CGFloat(0.14 + Double(idx) * 0.04))
      }
    }
    .frame(width: size, height: size)
  }
}

private struct FeedingOverlay: View {
  let size: CGFloat

  var body: some View {
    HStack(spacing: max(1, size * 0.10)) {
      Circle().frame(width: size * 0.18, height: size * 0.18)
      Circle().frame(width: size * 0.14, height: size * 0.14)
      Circle().frame(width: size * 0.11, height: size * 0.11)
    }
    .foregroundStyle(Color.black.opacity(0.82))
    .frame(width: size, height: size)
  }
}

private struct SleepOverlay: View {
  let size: CGFloat

  var body: some View {
    Text("Z")
      .font(.system(size: max(8, size * 0.62), weight: .bold, design: .monospaced))
      .foregroundStyle(Color.black.opacity(0.82))
      .frame(width: size, height: size)
  }
}

/// Subdirectory-aware loader for the `Pets/<name>.png` assets. Renders a
/// tinted "?" placeholder if the asset can't be resolved so missing files
/// don't ship as transparent voids.
private struct BulldogSpriteImage: View {
  let assetName: String
  let height: CGFloat

  var body: some View {
    if let nsImage = Self.load(named: assetName) {
      Image(nsImage: nsImage)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .frame(height: height)
    } else {
      RoundedRectangle(cornerRadius: Dial.Radius.pixel)
        .fill(Dial.Palette.accent.opacity(0.4))
        .frame(width: height * 0.5, height: height)
        .overlay(
          Text("?")
            .font(.system(size: max(height * 0.5, 8), weight: .bold))
            .foregroundStyle(Dial.Palette.accent)
        )
    }
  }

  private static func load(named name: String) -> NSImage? {
    if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Pets") {
      return NSImage(contentsOf: url)
    }
    // Fall back to root resources in case the bundling strategy ever changes.
    if let url = Bundle.main.url(forResource: name, withExtension: "png") {
      return NSImage(contentsOf: url)
    }
    return nil
  }
}
