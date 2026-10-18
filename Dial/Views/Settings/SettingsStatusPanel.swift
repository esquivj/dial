// Dial/Views/Settings/SettingsStatusPanel.swift
import SwiftUI
import Foundation

// MARK: - Diagnostics

private extension StatsQueries.EnrichmentProgress {
  static let empty = Self(
    total: 0,
    enriched: 0,
    trackArtistResolved: 0,
    trackArtistDirect: 0,
    trackArtistAliased: 0,
    artistIdentityAliases: 0,
    artistTotal: 0,
    artistEnriched: 0,
    tagArtistTotal: 0,
    tagArtistChecked: 0,
    tagArtistTagged: 0)
}

private extension StatsQueries.EnrichmentQueueHealth {
  static let empty = Self(
    metadataFailed: 0,
    metadataLimited: 0,
    metadataPartial: 0,
    metadataRetryReady: 0,
    tagFailed: 0,
    tagLimited: 0,
    tagEmpty: 0,
    tagRetryReady: 0,
    staleTrackMetadata: 0,
    staleArtistMetadata: 0)
}

struct SettingsStatusPanel: View {
  let coord: AppCoordinator
  @State private var enrichment: StatsQueries.EnrichmentProgress = .empty
  @State private var queueHealth: StatsQueries.EnrichmentQueueHealth = .empty
  @State private var recentSync: StatsQueries.RecentPlaySyncHealth?
  @State private var enrichmentError: String?
  @State private var lastRefresh: Date?
  @State private var showThemeInspector = false

  var body: some View {
    SettingsSection("STATUS") {
      TimelineView(.periodic(from: .now, by: 5)) { ctx in
        VStack(alignment: .leading, spacing: 8) {
          statusRow("Last sync", value: lastSyncLabel(now: ctx.date))
          statusRow("Recent catch-up", value: recentSyncLabel(now: ctx.date))
          statusRow("Library scan", value: coord.backgroundEnrichmentLabel)
          statusRow("Audio meter", value: visualizerLabel)
          statusRow("Track data", value: enrichmentError ?? enrichmentLabel(enrichment))
          statusRow("Tags", value: enrichmentError == nil ? tagLabel(enrichment) : "-")
          if let lastRefresh {
            statusRow("Last check", value: lastSyncLabel(last: lastRefresh, now: ctx.date))
          }
          if coord.playbackSource == .webAPI(.accessDenied) {
            spotifyAppAccessNote
          }

          Divider()
            .overlay(SettingsPalette.rule)
            .padding(.vertical, 2)

          dataHealthGrid(now: ctx.date)

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

  /// Shown only while macOS blocks Dial from reading the Spotify app.
  private var spotifyAppAccessNote: some View {
    Text(Self.spotifyAppAccessNoteText)
      .font(SettingsType.caption)
      .foregroundStyle(SettingsPalette.muted)
      .tint(SettingsPalette.accent)
      .fixedSize(horizontal: false, vertical: true)
  }

  static let spotifyAppAccessNoteText: AttributedString = {
    let markdown = "Dial can't read the Spotify app, so updates are slower. "
      + "Turn on Spotify under Dial in [Privacy & Security › Automation]"
      + "(x-apple.systempreferences:com.apple.preference.security?Privacy_Automation)."
    return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
  }()

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

  private func dataHealthGrid(now: Date) -> some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
      ],
      alignment: .leading,
      spacing: 8
    ) {
      healthCell(identityHealth)
      healthCell(themeHealth)
      healthCell(recentHealth(now: now))
      healthCell(retryHealth)
      healthCell(staleHealth)
      healthCell(tagHealth)
    }
  }

  private func healthCell(_ health: HealthItem) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Circle()
        .fill(health.tone.color)
        .frame(width: 6, height: 6)
        .shadow(color: health.tone.color.opacity(0.35), radius: 2)
      VStack(alignment: .leading, spacing: 2) {
        Text(health.label)
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.muted)
          .lineLimit(1)
        Text(health.value)
          .font(SettingsType.mono)
          .foregroundStyle(SettingsPalette.text)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
    .background(SettingsPalette.control.opacity(0.74))
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .stroke(health.tone.color.opacity(0.28), lineWidth: 1))
    .help(health.help)
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

  private func recentSyncLabel(now: Date) -> String {
    guard let recentSync else { return "never" }
    let age = lastSyncLabel(
      last: Date(timeIntervalSince1970: TimeInterval(recentSync.lastSyncedAt)),
      now: now)
    if recentSync.lastResponseSaturated {
      return "\(recentSync.lastResponseCount) seen · possible gap"
    }
    if recentSync.lastInsertedCount > 0 {
      return "\(recentSync.lastInsertedCount) added · \(age)"
    }
    return "caught up · \(age)"
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
        let queries = StatsQueries(dbq: dbq)
        return (
          enrichment: try queries.enrichmentProgress(),
          recentSync: try queries.recentPlaySyncHealth(),
          queueHealth: try queries.enrichmentQueueHealth()
        )
      }.value
      guard !Task.isCancelled else { return }
      await MainActor.run {
        enrichment = snapshot.enrichment
        recentSync = snapshot.recentSync
        queueHealth = snapshot.queueHealth
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
    let repaired = enrichment.trackArtistAliased.formatted(.number.notation(.compactName))
    return "\(idDone) / \(total) matched · \(repaired) repaired · \(artDone) covers · \(artistDone) / \(artistTotal) genres"
  }

  private func tagLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.tagArtistTotal == 0 { return "-" }
    let checked = enrichment.tagArtistChecked.formatted(.number.notation(.compactName))
    let tagged = enrichment.tagArtistTagged.formatted(.number.notation(.compactName))
    let total = enrichment.tagArtistTotal.formatted(.number.notation(.compactName))
    return "Last.fm \(checked) / \(total) checked · \(tagged) tagged"
  }

  private var identityHealth: HealthItem {
    guard enrichment.total > 0 else {
      return HealthItem(label: "Identity", value: "-", tone: .quiet, help: "No imported or counted Spotify tracks yet.")
    }
    let unresolved = max(0, enrichment.total - enrichment.trackArtistResolved)
    if unresolved == 0 {
      return HealthItem(
        label: "Identity",
        value: "clean",
        tone: .ok,
        help: "Every counted track has either a direct Spotify artist ID or a repaired artist alias.")
    }
    return HealthItem(
      label: "Identity",
      value: "\(compact(unresolved)) unresolved",
      tone: unresolved > 2_000 ? .watch : .quiet,
      help: "\(enrichment.trackArtistDirect.formatted()) tracks have direct Spotify artist IDs; \(enrichment.trackArtistAliased.formatted()) are repaired through \(enrichment.artistIdentityAliases.formatted()) aliases; \(unresolved.formatted()) still need a stronger identity signal.")
  }

  private var themeHealth: HealthItem {
    guard let decision = coord.nowPlaying.soundThemeDecision else {
      return HealthItem(label: "Theme", value: "waiting", tone: .quiet, help: "No current track theme decision yet.")
    }
    let percent = Int((decision.confidence * 100).rounded())
    let tone: HealthTone = decision.confidence < 0.56 || decision.source == .held ? .watch : .ok
    return HealthItem(
      label: "Theme",
      value: "\(percent)% · \(decision.source.shortLabel)",
      tone: tone,
      help: decision.reason)
  }

  private func recentHealth(now: Date) -> HealthItem {
    guard let recentSync else {
      return HealthItem(label: "Recent", value: "never", tone: .watch, help: "Recent-play catch-up has not written a sync checkpoint yet.")
    }
    let value = recentSync.lastResponseSaturated
      ? "gap risk"
      : (recentSync.lastInsertedCount > 0 ? "\(recentSync.lastInsertedCount) added" : "caught up")
    let help = recentSync.lastResponseSaturated
      ? "Spotify returned a full \(recentSync.lastResponseCount)-play page \(recentSync.consecutiveSaturated) time(s) in a row, so Dial may need another pass."
      : "Last recent-play check was \(lastSyncLabel(last: Date(timeIntervalSince1970: TimeInterval(recentSync.lastSyncedAt)), now: now))."
    return HealthItem(
      label: "Recent",
      value: value,
      tone: recentSync.lastResponseSaturated ? .watch : .ok,
      help: help)
  }

  private var retryHealth: HealthItem {
    if queueHealth.retryReadyTotal > 0 {
      return HealthItem(
        label: "Retry",
        value: "\(compact(queueHealth.retryReadyTotal)) ready",
        tone: .watch,
        help: "\(queueHealth.metadataRetryReady.formatted()) Spotify metadata and \(queueHealth.tagRetryReady.formatted()) Last.fm tag retries are eligible now.")
    }
    if queueHealth.retryWaitingTotal > 0 {
      return HealthItem(
        label: "Retry",
        value: "\(compact(queueHealth.retryWaitingTotal)) cooling",
        tone: .quiet,
        help: "Failed or limited enrichment rows exist, but their retry windows are still cooling down.")
    }
    return HealthItem(label: "Retry", value: "clear", tone: .ok, help: "No failed or rate-limited enrichment rows are queued.")
  }

  private var staleHealth: HealthItem {
    let total = queueHealth.staleMetadataTotal
    if total == 0 {
      return HealthItem(label: "Stale", value: "fresh", tone: .ok, help: "No successful Spotify metadata rows are past their refresh window.")
    }
    return HealthItem(
      label: "Stale",
      value: "\(compact(total)) stale",
      tone: total > 1_000 ? .watch : .quiet,
      help: "\(queueHealth.staleTrackMetadata.formatted()) tracks are older than 90 days and \(queueHealth.staleArtistMetadata.formatted()) artists are older than 60 days.")
  }

  private var tagHealth: HealthItem {
    guard enrichment.tagArtistTotal > 0 else {
      return HealthItem(label: "Tags", value: "-", tone: .quiet, help: "No taggable Spotify artists yet.")
    }
    let missing = max(0, enrichment.tagArtistTotal - enrichment.tagArtistChecked)
    let tone: HealthTone = missing > 0 ? .quiet : .ok
    return HealthItem(
      label: "Tags",
      value: "\(compact(enrichment.tagArtistTagged)) / \(compact(enrichment.tagArtistTotal))",
      tone: tone,
      help: "\(enrichment.tagArtistChecked.formatted()) artists checked through Last.fm; \(enrichment.tagArtistTagged.formatted()) have usable normalized tags.")
  }

  private func compact(_ value: Int) -> String {
    value.formatted(.number.notation(.compactName))
  }
}

private struct HealthItem {
  let label: String
  let value: String
  let tone: HealthTone
  let help: String
}

private enum HealthTone {
  case ok
  case quiet
  case watch

  var color: Color {
    switch self {
    case .ok:
      return SettingsPalette.accent
    case .quiet:
      return SettingsPalette.muted.opacity(0.82)
    case .watch:
      return Dial.Palette.accentAlt
    }
  }
}

private extension SoundThemeSource {
  var shortLabel: String {
    switch self {
    case .artistTags:    return "tags"
    case .spotifyGenres: return "genres"
    case .trackMetadata: return "text"
    case .recentSession: return "session"
    case .held:          return "hold"
    }
  }
}
