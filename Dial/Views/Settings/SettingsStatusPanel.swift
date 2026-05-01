// Dial/Views/Settings/SettingsStatusPanel.swift
import SwiftUI
import Foundation

// MARK: - Diagnostics

private extension StatsQueries.EnrichmentProgress {
  static let empty = Self(
    total: 0,
    enriched: 0,
    trackArtistResolved: 0,
    artistTotal: 0,
    artistEnriched: 0,
    tagArtistTotal: 0,
    tagArtistChecked: 0,
    tagArtistTagged: 0)
}

struct SettingsStatusPanel: View {
  let coord: AppCoordinator
  @State private var enrichment: StatsQueries.EnrichmentProgress = .empty
  @State private var enrichmentError: String?
  @State private var lastRefresh: Date?
  @State private var showThemeInspector = false

  var body: some View {
    SettingsSection("STATUS") {
      TimelineView(.periodic(from: .now, by: 5)) { ctx in
        VStack(alignment: .leading, spacing: 8) {
          statusRow("Last sync", value: lastSyncLabel(now: ctx.date))
          statusRow("Library scan", value: coord.backgroundEnrichmentLabel)
          statusRow("Audio meter", value: visualizerLabel)
          statusRow("Track data", value: enrichmentError ?? enrichmentLabel(enrichment))
          statusRow("Tags", value: enrichmentError == nil ? tagLabel(enrichment) : "-")
          if let lastRefresh {
            statusRow("Last check", value: lastSyncLabel(last: lastRefresh, now: ctx.date))
          }

          Divider()
            .overlay(SettingsPalette.rule)
            .padding(.vertical, 2)

          DisclosureGroup(isExpanded: $showThemeInspector) {
            VStack(alignment: .leading, spacing: 7) {
              statusRow("Theme", value: themeLabel)
              statusRow("Source", value: themeSourceLabel)
              statusRow("Confidence", value: themeConfidenceLabel)
              Text(themeReasonLabel)
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            .padding(.top, 6)
          } label: {
            SettingsDisclosureLabel(
              title: "Theme inspector",
              detail: "Shows why the current cartridge color was selected.")
          }
          .tint(SettingsPalette.accent)
        }
      }
    }
    .task { await refreshEnrichmentLoop() }
  }

  private func statusRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(SettingsType.caption)
        .foregroundStyle(SettingsPalette.muted)
      Spacer()
      Text(value)
        .font(SettingsType.mono)
        .contentTransition(.numericText())
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func lastSyncLabel(now: Date) -> String {
    guard let last = coord.lastSuccessfulPoll else { return "never" }
    return lastSyncLabel(last: last, now: now)
  }

  private func lastSyncLabel(last: Date, now: Date) -> String {
    let elapsed = now.timeIntervalSince(last)
    if elapsed < 5 { return "just now" }
    if elapsed < 60 { return "\(Int(elapsed)) sec ago" }
    if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
    return "\(Int(elapsed / 3600))h ago"
  }

  private var visualizerLabel: String {
    switch coord.visualizer.state {
    case .idle:    return "idle"
    case .running: return "live"
    case .denied:  return "permission denied"
    case .error:   return "offline"
    }
  }

  private var themeLabel: String {
    coord.nowPlaying.soundTheme.label
  }

  private var themeSourceLabel: String {
    coord.nowPlaying.soundThemeDecision?.source.label ?? "none"
  }

  private var themeConfidenceLabel: String {
    guard let confidence = coord.nowPlaying.soundThemeDecision?.confidence else { return "-" }
    return "\(Int((confidence * 100).rounded()))%"
  }

  private var themeReasonLabel: String {
    coord.nowPlaying.soundThemeDecision?.reason ?? "No current sound decision."
  }

  private func refreshEnrichmentLoop() async {
    await refreshEnrichment()
    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: 15_000_000_000)
      } catch {
        return
      }
      await refreshEnrichment()
    }
  }

  private func refreshEnrichment() async {
    let dbq = coord.dbq
    do {
      let snapshot = try await Task.detached(priority: .utility) {
        try StatsQueries(dbq: dbq).enrichmentProgress()
      }.value
      guard !Task.isCancelled else { return }
      await MainActor.run {
        enrichment = snapshot
        enrichmentError = nil
        lastRefresh = Date()
      }
    } catch is CancellationError {
      return
    } catch {
      await MainActor.run {
        enrichmentError = "unavailable"
        lastRefresh = Date()
      }
    }
  }

  private func enrichmentLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.total == 0 { return "-" }
    let artDone = enrichment.enriched.formatted(.number.notation(.compactName))
    let idDone = enrichment.trackArtistResolved.formatted(.number.notation(.compactName))
    let total = enrichment.total.formatted(.number.notation(.compactName))
    let artistDone = enrichment.artistEnriched.formatted(.number.notation(.compactName))
    let artistTotal = enrichment.artistTotal.formatted(.number.notation(.compactName))
    return "\(idDone) / \(total) matched · \(artDone) covers · \(artistDone) / \(artistTotal) Spotify profiles"
  }

  private func tagLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.tagArtistTotal == 0 { return "-" }
    let checked = enrichment.tagArtistChecked.formatted(.number.notation(.compactName))
    let tagged = enrichment.tagArtistTagged.formatted(.number.notation(.compactName))
    let total = enrichment.tagArtistTotal.formatted(.number.notation(.compactName))
    return "Last.fm \(checked) / \(total) checked · \(tagged) tagged"
  }
}
