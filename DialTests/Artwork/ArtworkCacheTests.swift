import AppKit
import XCTest
@testable import Dial

@MainActor
final class ArtworkCacheTests: XCTestCase {
  func test_loadCapsCachedImages() async {
    let cache = ArtworkCache(maxImages: 2) { _ in
      NSImage(size: NSSize(width: 1, height: 1))
    }

    _ = await cache.load("https://example.com/one.png")
    _ = await cache.load("https://example.com/two.png")
    _ = await cache.load("https://example.com/three.png")

    XCTAssertEqual(cache.state(for: "https://example.com/one.png"), .empty)
    XCTAssertEqual(cache.state(for: "https://example.com/two.png"), .loaded)
    XCTAssertEqual(cache.state(for: "https://example.com/three.png"), .loaded)
  }

  func test_loadCapsFailedKeys() async {
    let cache = ArtworkCache(maxImages: 2, maxFailedKeys: 2) { _ in nil }

    _ = await cache.load("https://example.com/one.png")
    _ = await cache.load("https://example.com/two.png")
    _ = await cache.load("https://example.com/three.png")

    XCTAssertEqual(cache.state(for: "https://example.com/one.png"), .empty)
    XCTAssertEqual(cache.state(for: "https://example.com/two.png"), .failed)
    XCTAssertEqual(cache.state(for: "https://example.com/three.png"), .failed)
  }

  func test_concurrentLoadsShareInflightTask() async {
    let counter = ArtworkLoadCounter()
    let cache = ArtworkCache { _ in
      try? await Task.sleep(nanoseconds: 20_000_000)
      await counter.increment()
      return NSImage(size: NSSize(width: 1, height: 1))
    }

    async let first = cache.load("https://example.com/cover.png")
    async let second = cache.load("https://example.com/cover.png")
    let images = await (first, second)

    XCTAssertNotNil(images.0)
    XCTAssertNotNil(images.1)
    let loadCount = await counter.value()
    XCTAssertEqual(loadCount, 1)
  }
}

private actor ArtworkLoadCounter {
  private var count = 0

  func increment() {
    count += 1
  }

  func value() -> Int {
    count
  }
}
