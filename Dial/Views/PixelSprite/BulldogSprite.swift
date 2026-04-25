// Dial/Views/PixelSprite/BulldogSprite.swift
import SwiftUI

/// Image-based pet renderer. Replaces `PixelSprite` for the new mint-teal
/// French bulldog character. Renders the right asset (or 2-frame loop)
/// for a given `(stage, behavior)`. Handles the BPM-driven bob internally
/// when the behavior is `.beatSync`, so callers don't need a separate
/// `BeatSyncSprite` wrapper anymore.
///
/// Asset bundling: PNGs live at `Dial/Resources/Pets/<name>.png` and are
/// declared in `project.yml` so they ship in the app bundle. Lookup is
/// `Image("companion-idle")`.
///
/// Pixel-art note: every render uses `.interpolation(.none)` so downscaling
/// to menubar size stays crisp instead of getting blurry from bilinear filtering.
struct BulldogSprite: View {
  let stage: PetStage
  let behavior: PetBehavior
  /// Sprite is rendered at this height; width derives from native aspect (~1:1.93 portrait).
  let height: CGFloat

  @State private var bob: CGFloat = 0

  var body: some View {
    spriteContent
      .offset(y: bob)
      .onAppear { syncBob() }
      .onChange(of: bpmKey) { _, _ in syncBob() }
  }

  // MARK: - Static vs animated frames

  @ViewBuilder
  private var spriteContent: some View {
    let assets = Self.assets(for: stage, behavior: behavior)
    if assets.count > 1, let interval = Self.frameInterval(for: behavior) {
      TimelineView(.periodic(from: .now, by: interval)) { ctx in
        let frame = Int(ctx.date.timeIntervalSinceReferenceDate / interval) % assets.count
        sprite(named: assets[frame])
      }
    } else {
      sprite(named: assets[0])
    }
  }

  private func sprite(named name: String) -> some View {
    Image(name)
      .interpolation(.none)
      .resizable()
      .scaledToFit()
      .frame(height: height)
  }

  // MARK: - BPM bob

  /// Hashable handle for `onChange` so SwiftUI restarts the bob if the
  /// behavior or its embedded BPM changes.
  private var bpmKey: Double {
    if case .beatSync(let bpm) = behavior { return bpm }
    return 0
  }

  private func syncBob() {
    guard case .beatSync(let bpm) = behavior else {
      bob = 0
      return
    }
    let halfPeriod = max(60.0 / bpm / 2, 0.18)
    withAnimation(.easeInOut(duration: halfPeriod).repeatForever(autoreverses: true)) {
      bob = -2
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
      case .idle:         return ["companion-idle"]
      case .walk:         return ["companion-walk-a", "companion-walk-b"]
      case .beatSync:     return ["companion-beat-sync"]
      case .firstListen:  return ["companion-first-listen"]
      case .rediscovered: return ["companion-rediscovered"]
      case .eating:       return ["companion-eating-a", "companion-eating-b"]
      case .paused:       return ["companion-paused"]
      case .dormant:      return ["companion-sleeping-a", "companion-sleeping-b"]
      case .levelUp:      return ["companion-idle"]   // glow effect layered at view level
      }
    }
  }

  /// Frame interval for the 2-frame loops. Chosen so total cycle matches
  /// the cadence we mocked in Paper:
  ///   walk     ~700ms total → 350ms / frame
  ///   eating   ~600ms       → 300ms / frame
  ///   sleeping ~1500ms      → 750ms / frame
  static func frameInterval(for behavior: PetBehavior) -> Double? {
    switch behavior {
    case .walk:     return 0.35
    case .eating:   return 0.30
    case .dormant:  return 0.75
    default:        return nil
    }
  }
}
