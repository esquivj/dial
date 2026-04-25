// Dial/Views/PixelSprite/BeatSyncSprite.swift
import SwiftUI

/// Renders the same sprite as `PixelSprite` but bobs vertically at the track's BPM cadence.
struct BeatSyncSprite: View {
  let grid: PetSprites.Grid
  let pixelSize: CGFloat
  let bpm: Double?

  @State private var bob: CGFloat = 0

  var body: some View {
    PixelSprite(grid: grid, pixelSize: pixelSize)
      .offset(y: bob)
      .onAppear { animate() }
      .onChange(of: bpm ?? 0) { _, _ in animate() }
  }

  private func animate() {
    // Half period = full bob in one direction; default to 90 BPM if no BPM is known.
    let half = max(60.0 / (bpm ?? 90) / 2, 0.18)
    withAnimation(.easeInOut(duration: half).repeatForever(autoreverses: true)) {
      bob = -2 * pixelSize
    }
  }
}
