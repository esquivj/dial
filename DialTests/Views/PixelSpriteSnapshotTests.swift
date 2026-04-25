// DialTests/Views/PixelSpriteSnapshotTests.swift
import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import Dial

final class PixelSpriteSnapshotTests: XCTestCase {
  func test_companionIdle_snapshot() {
    let view = PixelSprite(grid: PetSprites.grid(for: .companion, behavior: .idle), pixelSize: 8)
      .padding(12)
      .background(Dial.Palette.ground)
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: CGSize(width: 136, height: 136))
    assertSnapshot(of: host, as: .image)
  }

  func test_companionBeatSync_snapshot() {
    let view = PixelSprite(
      grid: PetSprites.grid(for: .companion, behavior: .beatSync(bpm: 120)),
      pixelSize: 8
    )
    .padding(12)
    .background(Dial.Palette.ground)
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: CGSize(width: 136, height: 136))
    assertSnapshot(of: host, as: .image)
  }
}
