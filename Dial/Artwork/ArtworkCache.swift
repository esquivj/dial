import AppKit
import Foundation
import Observation

@Observable
final class ArtworkCache {
  private var images: [String: NSImage] = [:]
  private var tasks: [String: Task<NSImage?, Never>] = [:]

  func image(for urlString: String?) -> NSImage? {
    guard let key = normalizedKey(urlString) else { return nil }
    return images[key]
  }

  @discardableResult
  func load(_ urlString: String?) async -> NSImage? {
    guard let key = normalizedKey(urlString), let url = URL(string: key) else { return nil }
    if let image = images[key] { return image }
    if let task = tasks[key] { return await task.value }

    let task = Task { () -> NSImage? in
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        return NSImage(data: data)
      } catch {
        return nil
      }
    }
    tasks[key] = task

    let image = await task.value
    tasks[key] = nil
    if let image {
      images[key] = image
    }
    return image
  }

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
