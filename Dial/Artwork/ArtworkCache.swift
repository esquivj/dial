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
  private var images: [String: NSImage] = [:]
  private var tasks: [String: Task<NSImage?, Never>] = [:]
  private var failedKeys: Set<String> = []

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
      return image
    }
    if let task = tasks[key] {
      let perf = DialPerf.begin("artwork.inflight_wait")
      let image = await task.value
      perf.end()
      return image
    }

    failedKeys.remove(key)
    let task = Task { () -> NSImage? in
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        return NSImage(data: data)
      } catch {
        return nil
      }
    }
    tasks[key] = task

    let perf = DialPerf.begin("artwork.load")
    let image = await task.value
    perf.end()
    tasks[key] = nil
    if let image {
      images[key] = image
      failedKeys.remove(key)
    } else {
      failedKeys.insert(key)
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
}
