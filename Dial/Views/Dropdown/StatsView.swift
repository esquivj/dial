// Dial/Views/Dropdown/StatsView.swift
import SwiftUI
import GRDB

/// Inline Stats panel — replaces the dropdown body when the user taps STATS
/// in the controls bar. Compact editorial layout designed for ~320 wide.
struct StatsView: View {
  let dbq: DatabaseQueue
  @Bindable var artworkCache: ArtworkCache
  let onBack: () -> Void
  @State private var totals = StatsQueries.Totals(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0)
  @State private var topTracks: [StatsQueries.TopRow] = []
  @State private var topArtists: [StatsQueries.TopRow] = []
  @State private var rhythmBuckets: [StatsQueries.RhythmBucket] = []
  @State private var badgeSummaries: [StatsQueries.BadgeSummary] = []
  @State private var recentBadges: [StatsQueries.BadgeMemoryRow] = []
  @State private var selectedRange: StatsRange = .ytd
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      ScrollView {
        VStack(alignment: .leading, spacing: Dial.Layout.SecondaryScreen.sectionSpacing) {
          hero
          rangeSnapshot
          memoriesSection
          rhythmSection
          topTracksSection
          topArtistsSection
        }
        .padding(Dial.Layout.SecondaryScreen.contentPadding)
      }
    }
    .task(id: ObjectIdentifier(dbq)) {
      let observation = StatsQueries(dbq: dbq).observePlaysChanges()
      do {
        for try await _ in observation.values(in: dbq) { reload() }
      } catch {
        reload()
      }
    }
    .onChange(of: selectedRange) { _, _ in reload() }
  }

  private var header: some View {
    HStack(spacing: Dial.Layout.Header.spacing) {
      BackButton(action: onBack)
      Text("STATS")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.accent)
      Spacer()
      rangeControl
    }
    .padding(EdgeInsets(
      top: Dial.Layout.Header.topPadding,
      leading: Dial.Layout.Header.leadingPadding,
      bottom: Dial.Layout.Header.bottomPadding,
      trailing: Dial.Layout.Header.trailingPadding))
  }

  private var rangeControl: some View {
    HStack(spacing: 2) {
      ForEach(StatsRange.allCases) { range in
        Button {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            selectedRange = range
          }
        } label: {
          Text(range.label)
            .font(Dial.Typography.monoTiny)
            .tracking(0.9)
            .foregroundStyle(selectedRange == range ? Dial.Palette.ground : Dial.Palette.textMuted)
            .frame(width: 34, height: 18)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(selectedRange == range ? Dial.Palette.accent : Dial.Palette.surface)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(range.label) stats range")
        .accessibilityValue(selectedRange == range ? "Selected" : "Not selected")
      }
    }
    .padding(2)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Dial.Palette.ground.opacity(0.55))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Dial.Palette.hairline, lineWidth: 1))
    )
  }

  // MARK: Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(selectedRange.heroTitle)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.textMuted)
      Text(hoursFormatted(totals.listeningMs))
        .font(.custom("IBMPlexMono-Medium", size: 40))
        .foregroundStyle(Dial.Palette.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text("total listening time")
        .font(.system(size: 10))
        .foregroundStyle(Dial.Palette.textMuted)
      if selectedRange != .all {
        Text(selectedRange.context)
          .font(.system(size: 10))
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.72))
      }
    }
  }

  // MARK: Range snapshot

  private var rangeSnapshot: some View {
    HStack(spacing: 16) {
      stat("PLAYS", totals.plays.formatted(.number))
      stat("TRACKS", totals.uniqueTracks.formatted(.number))
      stat("ARTISTS", totals.uniqueArtists.formatted(.number))
      stat("REPEAT", repeatRate())
      Spacer()
    }
  }

  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(1.2)
        .foregroundStyle(Dial.Palette.textMuted)
      Text(value)
        .font(.custom("IBMPlexMono-Medium", size: 18))
        .foregroundStyle(Dial.Palette.textPrimary)
    }
  }

  // MARK: Memories

  private var memoriesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionHeader("BADGE MEMORIES", detail: badgeSummaries.isEmpty ? nil : "\(totalBadgeCount) EARNED")
      if badgeSummaries.isEmpty {
        emptyHint("No memories logged yet")
      } else {
        if let latest = recentBadges.first {
          FeaturedBadgeMemory(row: latest)
        }
        HStack(spacing: 8) {
          ForEach(badgeSummaries) { summary in
            memoryPill(summary)
          }
          Spacer(minLength: 0)
        }
        if recentBadges.count > 1 {
          HStack {
            Text("RECENT")
              .font(Dial.Typography.monoTiny)
              .tracking(1.2)
              .foregroundStyle(Dial.Palette.textMuted.opacity(0.72))
            Spacer()
          }
          .padding(.top, 2)
        }
        VStack(spacing: 0) {
          ForEach(Array(recentBadges.dropFirst().prefix(3).enumerated()), id: \.element.id) { idx, row in
            BadgeMemoryRowView(row: row)
            if idx < min(max(0, recentBadges.count - 1), 3) - 1 {
              Rectangle().fill(Dial.Palette.hairline.opacity(0.7)).frame(height: 1)
            }
          }
        }
      }
    }
  }

  private var totalBadgeCount: Int {
    badgeSummaries.reduce(0) { $0 + $1.count }
  }

  private func memoryPill(_ summary: StatsQueries.BadgeSummary) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(memoryColor(summary.category))
        .frame(width: 5, height: 5)
      Text(summary.category.label.uppercased())
        .font(Dial.Typography.monoTiny)
        .tracking(0.8)
      Text(summary.count.formatted(.number.notation(.compactName)))
        .font(Dial.Typography.monoTiny)
        .monospacedDigit()
    }
    .foregroundStyle(Dial.Palette.textPrimary.opacity(0.85))
    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 7))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: 3, style: .continuous),
      color: memoryColor(summary.category),
      fillOpacity: 0.045,
      edgeOpacity: 0.20)
  }

  // MARK: Rhythm

  private var rhythmSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      sectionHeader(rhythmTitle, detail: peakDayLabel)
      if rhythmBuckets.allSatisfy({ $0.count == 0 }) {
        emptyHint()
      } else {
        HStack(alignment: .bottom, spacing: 6) {
          ForEach(rhythmBuckets) { bucket in
            RhythmBar(
              bucket: bucket,
              maxValue: rhythmBuckets.map(\.value).max() ?? 1,
              isDaily: selectedRange == .seven)
          }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(Dial.Palette.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 5))

        Text(rhythmFootnote)
          .font(.system(size: 10))
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.68))
          .lineLimit(1)
      }
    }
  }

  // MARK: Top tracks (compact, with album art)

  private var topTracksSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionHeader("TOP TRACKS", detail: "PLAYS")
      if topTracks.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topTracks.prefix(5).enumerated()), id: \.element.id) { idx, row in
            TopTrackRow(rank: idx + 1, row: row, artworkCache: artworkCache)
            if idx < min(topTracks.count, 5) - 1 {
              Rectangle().fill(Dial.Palette.hairline.opacity(0.7)).frame(height: 1)
            }
          }
        }
      }
    }
  }

  // MARK: Top artists

  private var topArtistsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionHeader("TOP ARTISTS", detail: "PLAYS")
      if topArtists.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topArtists.prefix(5).enumerated()), id: \.element.id) { idx, row in
            HStack(spacing: 10) {
              Text(String(format: "%02d", idx + 1))
                .font(Dial.Typography.monoTiny)
                .foregroundStyle(Dial.Palette.textMuted)
                .frame(width: 18, alignment: .leading)
              Text(row.name)
                .font(Dial.Typography.sansCaption)
                .foregroundStyle(Dial.Palette.textPrimary)
                .lineLimit(1)
              Spacer()
              Text(row.count.formatted(.number))
                .font(Dial.Typography.monoTiny)
                .foregroundStyle(Dial.Palette.accent)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 5)
            if idx < min(topArtists.count, 5) - 1 {
              Rectangle().fill(Dial.Palette.hairline.opacity(0.7)).frame(height: 1)
            }
          }
        }
      }
    }
  }

  // MARK: Helpers

  private func sectionHeader(_ title: String, detail: String?) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.textMuted)
      if let detail {
        Spacer()
        Text(detail)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.6))
          .lineLimit(1)
          .frame(width: 62, alignment: .trailing)
      } else {
        Spacer()
      }
    }
  }

  private func emptyHint(_ text: String = "Not enough data yet") -> some View {
    Text(text)
      .font(.system(size: 10))
      .foregroundStyle(Dial.Palette.textMuted.opacity(0.7))
      .padding(.vertical, 4)
  }

  private func hoursFormatted(_ ms: Int64) -> String {
    let totalSec = ms / 1000
    let h = totalSec / 3600
    let m = (totalSec % 3600) / 60
    // Comma-separated hours so 7,453h doesn't read as "7453h" — large
    // play histories are common after Extended-History import and
    // unseparated thousands look like a single chunk of digits.
    if h > 0 { return "\(h.formatted(.number))h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "—"
  }

  private func repeatRate() -> String {
    guard totals.uniqueTracks > 0 else { return "—" }
    return String(format: "%.1fx", Double(totals.plays) / Double(totals.uniqueTracks))
  }

  private var rhythmTitle: String {
    selectedRange == .seven ? "RECENT SHAPE" : "WEEK SHAPE"
  }

  private var peakDayLabel: String? {
    guard let peak = rhythmBuckets.max(by: { $0.value < $1.value }), peak.value > 0 else {
      return nil
    }
    if selectedRange == .seven {
      return "\(peak.label) PEAK"
    }

    let average = rhythmBuckets.reduce(0.0) { $0 + $1.value } / Double(max(1, rhythmBuckets.count))
    guard average > 0 else { return "\(peak.label) PEAK" }
    let lift = Int((((peak.value / average) - 1) * 100).rounded(.toNearestOrAwayFromZero))
    return lift > 0 ? "\(peak.label) +\(lift)%" : "\(peak.label) PEAK"
  }

  private var rhythmFootnote: String {
    let plays = totals.plays.formatted(.number)
    switch selectedRange {
    case .all:    return "\(plays) known plays · normalized by weekday"
    case .ytd:    return "\(plays) known plays this year · normalized by weekday"
    case .thirty: return "\(plays) known plays in 30d · normalized by weekday"
    case .seven:  return "\(plays) known plays over the last 7 days"
    }
  }

  private func reload() {
    let q = StatsQueries(dbq: dbq)
    let since = selectedRange.since
    totals = (try? q.totals(since: since)) ?? totals
    topTracks = (try? q.topTracks(since: since)) ?? []
    topArtists = (try? q.topArtists(since: since)) ?? []
    if selectedRange == .seven {
      rhythmBuckets = (try? q.recentDailyRhythm(days: 7)) ?? []
    } else {
      rhythmBuckets = (try? q.weekdayRhythm(since: since)) ?? []
    }
    badgeSummaries = (try? q.badgeSummaries()) ?? []
    recentBadges = (try? q.recentBadgeMemories(limit: 5)) ?? []
  }
}

private enum StatsRange: String, CaseIterable, Identifiable {
  case all
  case ytd
  case thirty
  case seven

  var id: String { rawValue }

  var label: String {
    switch self {
    case .all:    return "ALL"
    case .ytd:    return "YTD"
    case .thirty: return "30D"
    case .seven:  return "7D"
    }
  }

  var since: Int64? {
    switch self {
    case .all:    return nil
    case .ytd:    return Self.startOfYearEpoch()
    case .thirty: return Int64(Date().timeIntervalSince1970) - 30 * 86_400
    case .seven:  return Int64(Date().timeIntervalSince1970) - 7 * 86_400
    }
  }

  var context: String {
    switch self {
    case .all:    return ""
    case .ytd:    return "so far this year"
    case .thirty: return "in the last 30 days"
    case .seven:  return "in the last 7 days"
    }
  }

  var heroTitle: String {
    switch self {
    case .all:    return "ALL KNOWN HISTORY"
    case .ytd:    return "THIS YEAR"
    case .thirty: return "LAST 30 DAYS"
    case .seven:  return "LAST 7 DAYS"
    }
  }

  private static func startOfYearEpoch() -> Int64 {
    let now = Date()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let components = calendar.dateComponents([.year], from: now)
    return Int64((calendar.date(from: components) ?? now).timeIntervalSince1970)
  }
}

private struct RhythmBar: View {
  let bucket: StatsQueries.RhythmBucket
  let maxValue: Double
  let isDaily: Bool

  var body: some View {
    VStack(spacing: 4) {
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 2)
          .fill(Dial.Palette.ground.opacity(0.7))
          .frame(width: 24, height: 42)
        RoundedRectangle(cornerRadius: 2)
          .fill(isPeak ? Dial.Palette.accent : Dial.Palette.textMuted.opacity(0.5))
          .frame(width: 24, height: height)
      }
      Text(bucket.label)
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(isPeak ? Dial.Palette.accent : Dial.Palette.textMuted.opacity(0.75))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity)
    .help(helpText)
  }

  private var height: CGFloat {
    guard maxValue > 0 else { return 0 }
    return max(3, CGFloat(bucket.value / maxValue) * 42)
  }

  private var isPeak: Bool {
    maxValue > 0 && bucket.value == maxValue
  }

  private var helpText: String {
    if isDaily {
      return "\(bucket.label): \(bucket.count.formatted(.number)) plays"
    }
    let perDay = String(format: "%.1f", bucket.value)
    return "\(bucket.label): \(bucket.count.formatted(.number)) plays · \(perDay)/day"
  }
}

private struct FeaturedBadgeMemory: View {
  let row: StatsQueries.BadgeMemoryRow

  var body: some View {
    HStack(spacing: 10) {
      BadgePixelIcon(kind: row.kind, color: memoryColor(row.category), size: 22)
        .frame(width: 30, height: 30)
        .dialPrintedChip(
          shape: RoundedRectangle(cornerRadius: 5, style: .continuous),
          color: memoryColor(row.category),
          fillOpacity: 0.05,
          edgeOpacity: 0.20)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(row.kind.label.uppercased())
            .font(Dial.Typography.monoTiny)
            .tracking(1.0)
            .foregroundStyle(memoryColor(row.category))
          Text(row.category.label.uppercased())
            .font(Dial.Typography.monoTiny)
            .tracking(0.8)
            .foregroundStyle(Dial.Palette.textMuted.opacity(0.72))
        }
        Text(subtitle)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textPrimary)
          .lineLimit(1)
        Text(relativeBadgeTime(row.earnedAt))
          .font(.system(size: 10))
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.76))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    .background(Dial.Palette.surface.opacity(0.55))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Dial.Palette.hairline.opacity(0.9), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var subtitle: String {
    let track = row.trackName?.isEmpty == false ? row.trackName! : "Unknown track"
    guard let artist = row.artistName, !artist.isEmpty else { return track }
    return "\(track) · \(artist)"
  }
}

private struct BadgeMemoryRowView: View {
  let row: StatsQueries.BadgeMemoryRow

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(memoryColor(row.category))
        .frame(width: 6, height: 6)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.kind.label)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textPrimary)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 10))
          .foregroundStyle(Dial.Palette.textMuted)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Text(relativeBadgeTime(row.earnedAt))
        .font(Dial.Typography.monoTiny)
        .tracking(0.6)
        .foregroundStyle(Dial.Palette.textMuted)
    }
    .padding(.vertical, 5)
  }

  private var subtitle: String {
    let track = row.trackName?.isEmpty == false ? row.trackName! : "Unknown track"
    guard let artist = row.artistName, !artist.isEmpty else { return track }
    return "\(track) · \(artist)"
  }

}

private func relativeBadgeTime(_ unix: Int64) -> String {
  let date = Date(timeIntervalSince1970: TimeInterval(unix))
  let f = RelativeDateTimeFormatter()
  f.unitsStyle = .abbreviated
  return f.localizedString(for: date, relativeTo: Date())
}

private func memoryColor(_ category: BadgeCategory) -> Color {
  switch category {
  case .discovery: return Dial.Palette.accent
  case .pattern: return Dial.Palette.accentAlt
  case .milestone: return Dial.Palette.textPrimary
  }
}

private struct TopTrackRow: View {
  let rank: Int
  let row: StatsQueries.TopRow
  @Bindable var artworkCache: ArtworkCache

  var body: some View {
    HStack(spacing: 10) {
      Text(String(format: "%02d", rank))
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.textMuted)
        .frame(width: 18, alignment: .leading)
      Group {
        if let urlString = row.artUrl, let image = artworkCache.image(for: urlString) {
          Image(nsImage: image)
            .resizable()
        } else {
          Rectangle().fill(Dial.Palette.surface)
            .task(id: row.artUrl) {
              await artworkCache.load(row.artUrl)
            }
        }
      }
      .frame(width: 28, height: 28)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .overlay(
        RoundedRectangle(cornerRadius: 3)
          .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
      )
      VStack(alignment: .leading, spacing: 1) {
        Text(row.name)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textPrimary)
          .lineLimit(1)
        if let subtitle = row.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(Dial.Palette.textMuted)
            .lineLimit(1)
        }
      }
      Spacer()
      Text(row.count.formatted(.number))
        .font(.custom("IBMPlexMono-Medium", size: 16))
        .foregroundStyle(Dial.Palette.accent)
        .monospacedDigit()
        .frame(width: 44, alignment: .trailing)
    }
    .padding(.vertical, 6)
  }
}
