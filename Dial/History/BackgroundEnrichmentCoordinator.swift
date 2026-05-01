// Dial/History/BackgroundEnrichmentCoordinator.swift
import Foundation
import GRDB
import Observation
import os.log

private let enrichmentLog = Logger(subsystem: "com.dial.Dial", category: "BackgroundEnrichment")

enum BackgroundEnrichmentPhase: Equatable {
  case off
  case waiting
  case tracks
  case artists
  case tags
  case caughtUp
  case failed

  var label: String {
    switch self {
    case .off:      "off"
    case .waiting:  "waiting"
    case .tracks:   "tracks"
    case .artists:  "artists"
    case .tags:     "tags"
    case .caughtUp: "caught up"
    case .failed:   "paused"
    }
  }
}

@Observable
final class BackgroundEnrichmentCoordinator {
  private let dbq: DatabaseQueue
  private let client: SpotifyClient
  private let settings: SettingsViewModel
  private var task: Task<Void, Never>?

  var phase: BackgroundEnrichmentPhase = .off
  var message = "Off"
  var lastError: String?
  var updatedAt: Date?

  var label: String {
    switch phase {
    case .failed:
      return lastError.map { "paused · \($0)" } ?? "paused"
    default:
      return "\(phase.label) · \(message)"
    }
  }

  init(dbq: DatabaseQueue, client: SpotifyClient, settings: SettingsViewModel) {
    self.dbq = dbq
    self.client = client
    self.settings = settings
  }

  func sync() {
    guard settings.backgroundEnrichmentEnabled, settings.signedIn else {
      stop()
      return
    }
    start(initialDelay: 15)
  }

  func restartNow() {
    stop(updateStatus: false)
    guard settings.backgroundEnrichmentEnabled, settings.signedIn else {
      update(.off, message: "Off", error: nil)
      return
    }
    start(initialDelay: 0)
  }

  func stop(updateStatus: Bool = true) {
    task?.cancel()
    task = nil
    if updateStatus {
      update(.off, message: "Off", error: nil)
    }
  }

  private func start(initialDelay: TimeInterval) {
    guard task == nil else { return }
    let dbq = self.dbq
    let client = self.client
    let settings = self.settings
    task = Task(priority: .background) { [weak self] in
      if initialDelay > 0 {
        self?.update(.waiting, message: "starts in \(Int(initialDelay))s", error: nil)
        try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
      }

      let metadata = MetadataEnricher(dbq: dbq, client: client)
      while !Task.isCancelled {
        guard settings.backgroundEnrichmentEnabled, settings.signedIn else { break }
        do {
          let activeCooldown = await SpotifyRateLimitGate.shared.cooldownRemaining()
          if activeCooldown > 0 {
            self?.update(
              .waiting,
              message: "Spotify cooldown \(Self.shortCooldown(activeCooldown))",
              error: nil)
            try await Task.sleep(nanoseconds: Self.nanoseconds(activeCooldown))
            continue
          }

          let before = try StatsQueries(dbq: dbq).enrichmentProgress()
          var attempted = 0

          if before.trackArtistResolved < before.total || before.enriched < before.total {
            let remaining = max(0, before.total - before.trackArtistResolved)
            self?.update(.tracks, message: "\(remaining.formatted()) IDs left", error: nil)
            attempted += try await metadata.enrichMissing(rateLimitPerSec: 0.20, limit: 80)
            try Task.checkCancellation()
            if try Self.hasRecentSpotifyRateLimit(dbq) {
              self?.update(.waiting, message: "Spotify cooldown", error: nil)
              let cooldown = await SpotifyRateLimitGate.shared.cooldownRemaining()
              try await Task.sleep(nanoseconds: Self.nanoseconds(cooldown > 0 ? cooldown : 15 * 60))
              continue
            }
          }

          let afterTracks = try StatsQueries(dbq: dbq).enrichmentProgress()
          if afterTracks.artistEnriched < afterTracks.artistTotal {
            let remaining = max(0, afterTracks.artistTotal - afterTracks.artistEnriched)
            self?.update(.artists, message: "\(remaining.formatted()) left", error: nil)
            attempted += try await metadata.enrichMissingArtists(rateLimitPerSec: 0.25, limit: 40)
            try Task.checkCancellation()
            if try Self.hasRecentSpotifyRateLimit(dbq) {
              self?.update(.waiting, message: "Spotify cooldown", error: nil)
              let cooldown = await SpotifyRateLimitGate.shared.cooldownRemaining()
              try await Task.sleep(nanoseconds: Self.nanoseconds(cooldown > 0 ? cooldown : 15 * 60))
              continue
            }
          }

          let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
          let afterArtists = try StatsQueries(dbq: dbq).enrichmentProgress()
          if settings.lastFMTagEnrichmentEnabled, !key.isEmpty, afterArtists.tagArtistChecked < afterArtists.tagArtistTotal {
            let remaining = max(0, afterArtists.tagArtistTotal - afterArtists.tagArtistChecked)
            self?.update(.tags, message: "\(remaining.formatted()) left", error: nil)
            let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
            attempted += try await tagger.enrichMissingArtists(rateLimitPerSec: 0.75, limit: 80)
            try Task.checkCancellation()
          }

          let after = try StatsQueries(dbq: dbq).enrichmentProgress()
          if attempted == 0 {
            if Self.enrichmentIsCaughtUp(after, includeTags: settings.lastFMTagEnrichmentEnabled && !key.isEmpty) {
              self?.update(.caughtUp, message: "maintenance scan", error: nil)
              attempted += try await metadata.enrichMissing(rateLimitPerSec: 0.20, limit: 24)
              try Task.checkCancellation()
              attempted += try await metadata.enrichMissingArtists(rateLimitPerSec: 0.25, limit: 24)
              try Task.checkCancellation()
              if settings.lastFMTagEnrichmentEnabled, !key.isEmpty {
                let tagger = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
                attempted += try await tagger.enrichMissingArtists(rateLimitPerSec: 0.75, limit: 30)
                try Task.checkCancellation()
              }
              if attempted == 0 {
                self?.update(.caughtUp, message: "library warm", error: nil)
                try await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
              } else {
                self?.update(.waiting, message: "refreshed stale metadata", error: nil)
                try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
              }
            } else {
              self?.update(.waiting, message: "retry window", error: nil)
              try await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
          } else {
            self?.update(.waiting, message: "continuing", error: nil)
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
          }
        } catch is CancellationError {
          break
        } catch {
          self?.update(.failed, message: "retrying later", error: String(describing: error))
          enrichmentLog.error("background enrichment paused: \(String(describing: error), privacy: .public)")
          try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
        }
      }
      self?.finishTask()
    }
  }

  private func update(_ phase: BackgroundEnrichmentPhase, message: String, error: String?) {
    self.phase = phase
    self.message = message
    self.lastError = error
    self.updatedAt = Date()
  }

  private func finishTask() {
    task = nil
    if !settings.backgroundEnrichmentEnabled || !settings.signedIn {
      update(.off, message: "Off", error: nil)
    }
  }

  private static func enrichmentIsCaughtUp(_ progress: StatsQueries.EnrichmentProgress, includeTags: Bool) -> Bool {
    progress.total > 0
      && progress.trackArtistResolved >= progress.total
      && progress.artistEnriched >= progress.artistTotal
      && (!includeTags || progress.tagArtistChecked >= progress.tagArtistTotal)
  }

  private static func hasRecentSpotifyRateLimit(_ dbq: DatabaseQueue, within seconds: Int64 = 15 * 60) throws -> Bool {
    let cutoff = Int64(Date().timeIntervalSince1970) - seconds
    return try dbq.read { db in
      try Int.fetchOne(db, sql: """
        SELECT 1
        FROM metadata_enrichment_state
        WHERE provider = 'spotify'
          AND status = 'limited'
          AND fetched_at >= ?
        LIMIT 1
      """, arguments: [cutoff]) != nil
    }
  }

  private static func shortCooldown(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(Int(ceil(seconds)))s" }
    if seconds < 3600 { return "\(Int(ceil(seconds / 60)))m" }
    return "\(Int(ceil(seconds / 3600)))h"
  }

  private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64(max(0, seconds) * 1_000_000_000)
  }
}
