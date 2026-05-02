import AppKit
import Foundation
import Observation

enum ArtworkCacheState: Equatable {
  case empty
  case loading
  case loaded
  case failed
}

@Observable
final class ArtworkCache {
  typealias ImageLoader = @Sendable (URL) async -> NSImage?

  @ObservationIgnored private let maxImages: Int
  @ObservationIgnored private let maxFailedKeys: Int
  @ObservationIgnored private let imageLoader: ImageLoader
  @ObservationIgnored private var imageOrder: [String] = []
  @ObservationIgnored private var failedOrder: [String] = []

  private var images: [String: NSImage] = [:]
  private var tasks: [String: Task<NSImage?, Never>] = [:]
  private var failedKeys: Set<String> = []

  init(
    maxImages: Int = 128,
    maxFailedKeys: Int = 128,
    imageLoader: @escaping ImageLoader = ArtworkCache.defaultImageLoader
  ) {
    self.maxImages = max(1, maxImages)
    self.maxFailedKeys = max(1, maxFailedKeys)
    self.imageLoader = imageLoader
  }

  @MainActor
  func image(for urlString: String?) -> NSImage? {
    guard let key = normalizedKey(urlString) else { return nil }
    return images[key]
  }

  @MainActor
  func state(for urlString: String?) -> ArtworkCacheState {
    guard let key = normalizedKey(urlString) else { return .empty }
    if images[key] != nil { return .loaded }
    if tasks[key] != nil { return .loading }
    if failedKeys.contains(key) { return .failed }
    return .empty
  }

  @discardableResult
  @MainActor
  func load(_ urlString: String?) async -> NSImage? {
    guard let key = normalizedKey(urlString), let url = URL(string: key) else { return nil }
    if let image = images[key] {
      DialPerf.event("artwork.cache_hit")
      markImageUsed(key)
      return image
    }
    if let task = tasks[key] {
      let perf = DialPerf.begin("artwork.inflight_wait")
      let image = await task.value
      perf.end()
      return image
    }

    clearFailure(key)
    let imageLoader = imageLoader
    let task = Task.detached(priority: .utility) { () -> NSImage? in
      await imageLoader(url)
    }
    tasks[key] = task

    let perf = DialPerf.begin("artwork.load")
    let image = await task.value
    perf.end()
    tasks[key] = nil
    if let image {
      cache(image, for: key)
      clearFailure(key)
    } else {
      markFailed(key)
    }
    return image
  }

  @MainActor
  func prefetch(_ urlString: String?) {
    guard let key = normalizedKey(urlString), images[key] == nil, tasks[key] == nil else { return }
    Task { [weak self] in
      _ = await self?.load(key)
    }
  }

  private func normalizedKey(_ urlString: String?) -> String? {
    guard let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  private static let defaultImageLoader: ImageLoader = { url in
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard !Task.isCancelled else { return nil }
      return NSImage(data: data)
    } catch {
      return nil
    }
  }

  @MainActor
  private func cache(_ image: NSImage, for key: String) {
    images[key] = image
    markImageUsed(key)
    while images.count > maxImages, let oldest = imageOrder.first {
      imageOrder.removeFirst()
      images.removeValue(forKey: oldest)
    }
  }

  @MainActor
  private func markImageUsed(_ key: String) {
    imageOrder.removeAll { $0 == key }
    imageOrder.append(key)
  }

  @MainActor
  private func markFailed(_ key: String) {
    failedKeys.insert(key)
    failedOrder.removeAll { $0 == key }
    failedOrder.append(key)
    while failedKeys.count > maxFailedKeys, let oldest = failedOrder.first {
      failedOrder.removeFirst()
      failedKeys.remove(oldest)
    }
  }

  @MainActor
  private func clearFailure(_ key: String) {
    failedKeys.remove(key)
    failedOrder.removeAll { $0 == key }
  }
}
