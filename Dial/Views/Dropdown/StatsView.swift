// Dial/Views/Dropdown/StatsView.swift
import SwiftUI
import GRDB

enum StatsViewPlacement {
  case legacyPanel
  case hardwareShell
}

/// Inline Stats panel — replaces the dropdown body when the user taps STATS
/// in the controls bar. Compact editorial layout designed for ~320 wide.
struct StatsView: View {
  let dbq: DatabaseQueue
  @Bindable var artworkCache: ArtworkCache
  let onBack: () -> Void
  let onSnapshot: (StatsViewSnapshot) -> Void
  var placement: StatsViewPlacement = .legacyPanel
  @State private var totals = StatsQueries.Totals(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0)
  @State private var topTracks: [StatsQueries.TopRow] = []
  @State private var topArtists: [StatsQueries.TopRow] = []
  @State private var topGenres: [StatsQueries.GenreRow] = []
  @State private var weeklyMemory: StatsQueries.WeeklyMemorySnapshot?
  @State private var rhythmBuckets: [StatsQueries.RhythmBucket] = []
  @State private var badgeSummaries: [StatsQueries.BadgeSummary] = []
  @State private var recentBadges: [StatsQueries.BadgeMemoryRow] = []
  @State private var selectedRange: StatsRange = .ytd
  @State private var reloadLoader = CoalescedSnapshotLoader<StatsViewSnapshot>("stats.snapshot.load")
  @Environment(\.dialTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    dbq: DatabaseQueue,
    artworkCache: ArtworkCache,
    initialSnapshot: StatsViewSnapshot? = nil,
    onBack: @escaping () -> Void,
    onSnapshot: @escaping (StatsViewSnapshot) -> Void = { _ in },
    placement: StatsViewPlacement = .legacyPanel
  ) {
    self.dbq = dbq
    self.artworkCache = artworkCache
    self.onBack = onBack
    self.onSnapshot = onSnapshot
    self.placement = placement
    _totals = State(initialValue: initialSnapshot?.totals ?? StatsQueries.Totals(
      plays: 0,
      listeningMs: 0,
      uniqueTracks: 0,
      uniqueArtists: 0))
    _topTracks = State(initialValue: initialSnapshot?.topTracks ?? [])
    _topArtists = State(initialValue: initialSnapshot?.topArtists ?? [])
    _topGenres = State(initialValue: initialSnapshot?.topGenres ?? [])
    _weeklyMemory = State(initialValue: initialSnapshot?.weeklyMemory)
    _rhythmBuckets = State(initialValue: initialSnapshot?.rhythmBuckets ?? [])
    _badgeSummaries = State(initialValue: initialSnapshot?.badgeSummaries ?? [])
    _recentBadges = State(initialValue: initialSnapshot?.recentBadges ?? [])
  }

  var body: some View {
    Group {
      switch placement {
      case .legacyPanel:
        legacyPanelBody
      case .hardwareShell:
        hardwareShellBody
      }
    }
    .task(id: ObjectIdentifier(dbq)) {
      reload()
      let observation = StatsQueries(dbq: dbq).observePlaysChanges()
      do {
        for try await _ in observation.values(in: dbq) { reload() }
      } catch {
        reload()
      }
    }
    .onChange(of: selectedRange) { _, _ in reload() }
    .onDisappear {
      reloadLoader.cancel()
    }
  }

  private var legacyPanelBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(theme.hairline.opacity(0.92)).frame(height: 1)
      statsScroll
    }
  }

  private var hardwareShellBody: some View {
    VStack(spacing: 0) {
      railHeader
        .frame(width: Dial.Layout.StatusRail.contentWidth, height: Dial.Layout.StatusRail.railHeight)
        .offset(y: Dial.Layout.Dropdown.hudRailContentYOffset)
        .frame(maxWidth: .infinity)
        .frame(height: Dial.Layout.Dropdown.hudTopChromeHeight)

      statsPlate
        .frame(height: Dial.Layout.SecondaryShell.plateHeight)
        .padding(.top, Dial.Layout.SecondaryShell.plateTopPadding)
        .padding(.horizontal, Dial.Layout.SecondaryShell.plateHorizontalPadding)
    }
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.hudBottomPaddingWithoutTransport)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var statsPlate: some View {
    statsScroll
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .modifier(RecessedScreen(depth: 0.42, height: 18))
      .lcdPanel(
        fill: theme.ground.opacity(Dial.Layout.SecondaryShell.plateFillOpacity),
        strokeOpacity: Dial.Layout.SecondaryShell.plateStrokeOpacity)
  }

  private var statsScroll: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Dial.Layout.SecondaryScreen.sectionSpacing) {
        overviewPanel
        if let weeklyMemory {
          WeeklyMemoryStatsCard(memory: weeklyMemory)
        }
        genreSignalSection
        rhythmSection
        topTracksSection
        topArtistsSection
        memoriesSection
      }
      .padding(Dial.Layout.SecondaryScreen.contentPadding)
    }
  }

  private var header: some View {
    HStack(spacing: Dial.Layout.Header.spacing) {
      BackButton(action: onBack)
      Text("STATS")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(theme.accent)
      Spacer()
      rangeControl
    }
    .padding(EdgeInsets(
      top: Dial.Layout.Header.topPadding,
      leading: Dial.Layout.Header.leadingPadding,
      bottom: Dial.Layout.Header.bottomPadding,
      trailing: Dial.Layout.Header.trailingPadding))
  }

  private var railHeader: some View {
    HStack(spacing: 0) {
      HStack(spacing: Dial.Layout.Header.spacing) {
        BackButton(action: onBack)
        Text("STATS")
          .font(Dial.Typography.monoLabel)
          .tracking(1.6)
          .foregroundStyle(theme.accent)
      }
      .offset(x: Dial.Layout.SecondaryShell.railLeadingOffset)

      Spacer(minLength: 8)

      rangeControl
        .offset(x: Dial.Layout.SecondaryShell.railTrailingOffset)
    }
    .padding(.horizontal, 2)
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
            .foregroundStyle(selectedRange == range ? theme.ground : theme.textMuted.opacity(0.78))
            .frame(width: 34, height: 18)
            .background(
              RoundedRectangle(cornerRadius: Dial.Radius.tiny)
                .fill(selectedRange == range ? theme.accent : theme.surface.opacity(0.86))
            )
            .dialHitSlop(horizontal: 5, vertical: 13)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(range.label) stats range")
        .accessibilityValue(selectedRange == range ? "Selected" : "Not selected")
      }
    }
    .padding(2)
    .background(
      RoundedRectangle(cornerRadius: Dial.Radius.media)
        .fill(theme.ground.opacity(0.55))
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.media)
            .stroke(theme.hairline.opacity(0.9), lineWidth: 1))
    )
  }

  // MARK: Overview

  private var overviewPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(selectedRange.heroTitle)
            .font(Dial.Typography.monoLabel)
            .tracking(1.6)
            .foregroundStyle(theme.textMuted.opacity(0.82))
          Text(hoursFormatted(totals.listeningMs))
            .font(.custom("GeistMono-Medium", size: 34))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .monospacedDigit()
          Text(overviewCaption)
            .font(Dial.Typography.monoSmall)
            .foregroundStyle(theme.textMuted.opacity(0.70))
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 8) {
          overviewSideStat("PLAYS", totals.plays.formatted(.number))
          overviewSideStat("REPEAT", repeatRate())
        }
        .frame(width: 78, alignment: .trailing)
      }

      Rectangle()
        .fill(theme.hairline.opacity(0.64))
        .frame(height: 1)

      HStack(spacing: 0) {
        overviewBottomStat("TRACKS", totals.uniqueTracks.formatted(.number))
        overviewDivider
        overviewBottomStat("ARTISTS", totals.uniqueArtists.formatted(.number))
        overviewDivider
        overviewBottomStat("BADGES", totalBadgeCount.formatted(.number))
      }
    }
    .padding(EdgeInsets(top: 11, leading: 11, bottom: 10, trailing: 11))
    .frame(maxWidth: .infinity, alignment: .leading)
    .dialRecessedPanel(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous),
      fill: theme.subtle,
      strokeOpacity: 0.24,
      topSheenOpacity: 0.16,
      innerShadowOpacity: 0.34)
  }

  private var overviewCaption: String {
    "total listening time"
  }

  private var overviewDivider: some View {
    Rectangle()
      .fill(theme.hairline.opacity(0.58))
      .frame(width: 1, height: 28)
      .padding(.horizontal, 9)
  }

  private func overviewSideStat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(1.0)
        .foregroundStyle(theme.textMuted.opacity(0.72))
      Text(value)
        .font(.custom("GeistMono-Medium", size: 14))
        .foregroundStyle(theme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .monospacedDigit()
    }
  }

  private func overviewBottomStat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(1.0)
        .foregroundStyle(theme.textMuted.opacity(0.70))
      Text(value)
        .font(.custom("GeistMono-Medium", size: 15))
        .foregroundStyle(theme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.66)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
              .foregroundStyle(theme.textMuted.opacity(0.66))
            Spacer()
          }
          .padding(.top, 2)
        }
        VStack(spacing: 0) {
          ForEach(Array(recentBadges.dropFirst().prefix(3).enumerated()), id: \.element.id) { idx, row in
            BadgeMemoryRowView(row: row)
            if idx < min(max(0, recentBadges.count - 1), 3) - 1 {
              Rectangle().fill(theme.hairline.opacity(0.54)).frame(height: 1)
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
        .fill(memoryColor(summary.category, theme: theme))
        .frame(width: 5, height: 5)
      Text(summary.category.label.uppercased())
        .font(Dial.Typography.monoTiny)
        .tracking(0.8)
      Text(summary.count.formatted(.number.notation(.compactName)))
        .font(Dial.Typography.monoTiny)
        .monospacedDigit()
    }
    .foregroundStyle(theme.textPrimary.opacity(0.86))
    .padding(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 7))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.printed, style: .continuous),
      color: memoryColor(summary.category, theme: theme),
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
        .background(theme.surface.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.media))

        Text(rhythmFootnote)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.62))
          .lineLimit(1)
      }
    }
  }

  // MARK: Sound signal

  private var genreSignalSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      sectionHeader("SOUND SIGNAL", detail: topGenres.isEmpty ? "NO TAGS" : "PLAYS")
      if topGenres.isEmpty {
        emptyHint("Add a Last.fm key in Settings to teach Dial your sound")
      } else {
        let maxPlays = max(1, topGenres.map(\.playCount).max() ?? 1)
        VStack(spacing: 6) {
          ForEach(topGenres.prefix(5)) { row in
            GenreSignalRow(row: row, maxPlayCount: maxPlays)
          }
        }
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
              Rectangle().fill(theme.hairline.opacity(0.54)).frame(height: 1)
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
                .foregroundStyle(theme.textMuted.opacity(0.72))
                .frame(width: 18, alignment: .leading)
              Text(row.name)
                .font(Dial.Typography.sansCaption)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
              Spacer()
              Text(row.count.formatted(.number))
                .font(Dial.Typography.monoTiny)
                .foregroundStyle(theme.accent)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 5)
            if idx < min(topArtists.count, 5) - 1 {
              Rectangle().fill(theme.hairline.opacity(0.54)).frame(height: 1)
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
        .foregroundStyle(theme.textMuted.opacity(0.78))
      if let detail {
        Spacer()
        Text(detail)
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(theme.accent.opacity(0.58))
          .lineLimit(1)
          .frame(width: 62, alignment: .trailing)
      } else {
        Spacer()
      }
    }
  }

  private func emptyHint(_ text: String = "Not enough data yet") -> some View {
    Text(text)
      .font(Dial.Typography.monoSmall)
      .foregroundStyle(theme.textMuted.opacity(0.66))
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
    let range = selectedRange
    reloadLoader.schedule {
      await StatsViewSnapshot.load(dbq: dbq, range: range)
    } apply: { snapshot in
      apply(snapshot, range: range)
    }
  }

  private func apply(_ snapshot: StatsViewSnapshot, range: StatsRange) {
    totals = snapshot.totals
    topTracks = snapshot.topTracks
    topArtists = snapshot.topArtists
    topGenres = snapshot.topGenres
    weeklyMemory = snapshot.weeklyMemory
    rhythmBuckets = snapshot.rhythmBuckets
    badgeSummaries = snapshot.badgeSummaries
    recentBadges = snapshot.recentBadges
    if range == .ytd {
      onSnapshot(snapshot)
    }
  }
}

private struct WeeklyMemoryStatsCard: View {
  let memory: StatsQueries.WeeklyMemorySnapshot
  @Environment(\.dialTheme) private var theme

  var body: some View {
    let memoryTheme = DialTheme.palette(for: memory.theme)
    let accent = memoryTheme.accent

    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("THIS WEEK")
            .font(Dial.Typography.monoTiny)
            .tracking(1.0)
            .foregroundStyle(theme.textMuted.opacity(0.72))

          Text(memory.trait.uppercased())
            .font(Dial.Typography.monoTiny)
            .tracking(1.0)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        Text(memory.memento.uppercased())
          .font(Dial.Typography.monoLabel)
          .tracking(1.1)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)

        Text(memory.recapLine)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.72))
          .lineLimit(1)
          .minimumScaleFactor(0.64)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .trailing, spacing: 3) {
        Text((memory.dominantGenre ?? memory.theme.label).uppercased())
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(accent.opacity(0.95))
          .lineLimit(1)
          .minimumScaleFactor(0.62)

        Text(roomObjectLabel(memory.roomObjectName))
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(theme.textPrimary.opacity(0.80))
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
          .minimumScaleFactor(0.66)
      }
      .frame(width: 90, alignment: .trailing)
    }
    .padding(EdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9))
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      color: accent,
      fillOpacity: 0.04,
      edgeOpacity: 0.16)
    .help(helpText)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("This week's memory")
    .accessibilityValue("\(memory.trait). \(memory.memento). \(memory.recapLine)")
  }

  private var helpText: String {
    let genre = memory.dominantGenre ?? memory.theme.label
    return "\(memory.trait): \(memory.recapLine) Memento: \(memory.memento). Room object: \(roomObjectLabel(memory.roomObjectName)). Dominant sound: \(genre)."
  }
}

private struct RhythmBar: View {
  let bucket: StatsQueries.RhythmBucket
  let maxValue: Double
  let isDaily: Bool
  @Environment(\.dialTheme) private var theme

  var body: some View {
    VStack(spacing: 4) {
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: Dial.Radius.pixel)
          .fill(theme.ground.opacity(0.74))
          .frame(width: 24, height: 42)
        RoundedRectangle(cornerRadius: Dial.Radius.pixel)
          .fill(isPeak ? theme.accent : theme.textMuted.opacity(0.38))
          .frame(width: 24, height: height)
      }
      Text(bucket.label)
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(isPeak ? theme.accent : theme.textMuted.opacity(0.70))
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

private struct GenreSignalRow: View {
  let row: StatsQueries.GenreRow
  let maxPlayCount: Int
  @Environment(\.dialTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Circle()
          .fill(signalColor.opacity(0.9))
          .frame(width: 5, height: 5)
        Text(row.genre.capitalized)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(row.playCount.formatted(.number))
          .font(Dial.Typography.monoTiny)
          .foregroundStyle(signalColor)
          .monospacedDigit()
      }
      GeometryReader { proxy in
        let width = proxy.size.width * CGFloat(row.playCount) / CGFloat(max(1, maxPlayCount))
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(theme.surface.opacity(0.66))
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(signalColor.opacity(0.82))
            .frame(width: max(4, width))
        }
      }
      .frame(height: 4)
      Text(detailText)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(theme.textMuted.opacity(0.66))
        .lineLimit(1)
    }
    .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    .background(
      RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous)
        .fill(signalColor.opacity(0.035))
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.media, style: .continuous)
            .stroke(signalColor.opacity(0.14), lineWidth: 1))
    )
  }

  private var signalColor: Color {
    (row.theme.map { DialTheme.palette(for: $0) } ?? theme).soundAccent
  }

  private var detailText: String {
    let artists = "\(row.artistCount.formatted(.number)) \(row.artistCount == 1 ? "artist" : "artists")"
    let details = row.detailTags.prefix(3).joined(separator: " / ")
    return details.isEmpty ? artists : "\(artists) · \(details)"
  }
}

private struct FeaturedBadgeMemory: View {
  let row: StatsQueries.BadgeMemoryRow
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 10) {
      BadgePixelIcon(kind: row.kind, color: memoryColor(row.category, theme: theme), size: 22)
        .frame(width: 30, height: 30)
        .dialPrintedChip(
          shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
          color: memoryColor(row.category, theme: theme),
          fillOpacity: 0.05,
          edgeOpacity: 0.20)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(row.kind.label.uppercased())
            .font(Dial.Typography.monoTiny)
            .tracking(1.0)
            .foregroundStyle(memoryColor(row.category, theme: theme))
          Text(row.category.label.uppercased())
            .font(Dial.Typography.monoTiny)
            .tracking(0.8)
            .foregroundStyle(theme.textMuted.opacity(0.66))
        }
        Text(subtitle)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
        Text(relativeBadgeTime(row.earnedAt))
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.70))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    .background(theme.surface.opacity(0.46))
    .overlay(
      RoundedRectangle(cornerRadius: Dial.Radius.media)
        .stroke(theme.hairline.opacity(0.72), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.media))
  }

  private var subtitle: String {
    let track = row.trackName?.isEmpty == false ? row.trackName! : "Unknown track"
    guard let artist = row.artistName, !artist.isEmpty else { return track }
    return "\(track) · \(artist)"
  }
}

private struct BadgeMemoryRowView: View {
  let row: StatsQueries.BadgeMemoryRow
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(memoryColor(row.category, theme: theme))
        .frame(width: 6, height: 6)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.kind.label)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
        Text(subtitle)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.78))
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Text(relativeBadgeTime(row.earnedAt))
        .font(Dial.Typography.monoTiny)
        .tracking(0.6)
        .foregroundStyle(theme.textMuted.opacity(0.68))
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

private func memoryColor(_ category: BadgeCategory, theme: DialTheme) -> Color {
  switch category {
  case .discovery: return theme.accent
  case .pattern: return theme.memoryAccent
  case .milestone: return theme.textPrimary
  }
}

private func roomObjectLabel(_ name: String) -> String {
  name
    .replacingOccurrences(of: "_", with: " ")
    .uppercased()
}

private struct TopTrackRow: View {
  let rank: Int
  let row: StatsQueries.TopRow
  @Bindable var artworkCache: ArtworkCache
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 10) {
      Text(String(format: "%02d", rank))
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(theme.textMuted.opacity(0.72))
        .frame(width: 18, alignment: .leading)
      Group {
        if let urlString = row.artUrl, let image = artworkCache.image(for: urlString) {
          Image(nsImage: image)
            .resizable()
        } else {
          Rectangle().fill(theme.surface)
            .task(id: row.artUrl) {
              await artworkCache.load(row.artUrl)
            }
        }
      }
      .frame(width: 28, height: 28)
      .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.printed))
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.printed)
          .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
      )
      VStack(alignment: .leading, spacing: 1) {
        Text(row.name)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
        if let subtitle = row.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(Dial.Typography.monoSmall)
            .foregroundStyle(theme.textMuted.opacity(0.78))
            .lineLimit(1)
        }
      }
      Spacer()
      Text(row.count.formatted(.number))
        .font(.custom("GeistMono-Medium", size: 16))
        .foregroundStyle(theme.accent)
        .monospacedDigit()
        .frame(width: 44, alignment: .trailing)
    }
    .padding(.vertical, 6)
  }
}
