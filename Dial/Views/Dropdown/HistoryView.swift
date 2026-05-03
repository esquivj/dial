// Dial/Views/Dropdown/HistoryView.swift
import SwiftUI
import GRDB

enum HistoryViewPlacement {
  case legacyPanel
  case hardwareShell
}

/// Inline History panel — replaces the dropdown body when the user taps
/// HISTORY in the controls bar. Lives in the same NSPopover, sized to the
/// dropdown's frame.
struct HistoryView: View {
  let dbq: DatabaseQueue
  @Bindable var artworkCache: ArtworkCache
  let onBack: () -> Void
  let onSnapshot: (HistoryViewSnapshot) -> Void
  var placement: HistoryViewPlacement = .legacyPanel
  @State private var rows: [StatsQueries.HistoryRow] = []
  @State private var totalPlays: Int = 0
  @State private var loaded = false
  @State private var reloadLoader = CoalescedSnapshotLoader<HistoryViewSnapshot>("history.snapshot.load")
  @Environment(\.dialTheme) private var theme

  init(
    dbq: DatabaseQueue,
    artworkCache: ArtworkCache,
    initialSnapshot: HistoryViewSnapshot? = nil,
    onBack: @escaping () -> Void,
    onSnapshot: @escaping (HistoryViewSnapshot) -> Void = { _ in },
    placement: HistoryViewPlacement = .legacyPanel
  ) {
    self.dbq = dbq
    self.artworkCache = artworkCache
    self.onBack = onBack
    self.onSnapshot = onSnapshot
    self.placement = placement
    _rows = State(initialValue: initialSnapshot?.rows ?? [])
    _totalPlays = State(initialValue: initialSnapshot?.totalPlays ?? 0)
    _loaded = State(initialValue: initialSnapshot != nil)
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
      reload(totalPlays: nil)
      let observation = StatsQueries(dbq: dbq).observePlaysChanges()
      do {
        // The observation's value is `SELECT COUNT(*) FROM plays` — capture
        // it as the lifetime total instead of throwing it away. No extra
        // query: the observation has to run the count anyway to know when
        // to fire, so we just keep the result.
        for try await total in observation.values(in: dbq) {
          reload(totalPlays: total)
        }
      } catch {
        reload(totalPlays: nil)
      }
    }
    .onDisappear {
      reloadLoader.cancel()
    }
  }

  private var legacyPanelBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(theme.hairline.opacity(0.92)).frame(height: 1)
      if rows.isEmpty && loaded {
        empty
      } else {
        list
      }
    }
  }

  private var hardwareShellBody: some View {
    VStack(spacing: 0) {
      railHeader
        .frame(width: Dial.Layout.StatusRail.contentWidth, height: Dial.Layout.StatusRail.railHeight)
        .offset(y: Dial.Layout.Dropdown.hudRailContentYOffset)
        .frame(maxWidth: .infinity)
        .frame(height: Dial.Layout.Dropdown.hudTopChromeHeight)

      historyPlate
        .frame(height: Dial.Layout.SecondaryShell.plateHeight)
        .padding(.top, Dial.Layout.SecondaryShell.plateTopPadding)
        .padding(.horizontal, Dial.Layout.SecondaryShell.plateHorizontalPadding)
    }
    .padding(.top, Dial.Layout.Dropdown.outerTopPadding)
    .padding(.bottom, Dial.Layout.Dropdown.hudBottomPaddingWithoutTransport)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var header: some View {
    HStack(spacing: Dial.Layout.Header.spacing) {
      BackButton(action: onBack)
      Text("HISTORY")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(theme.accent)
      Spacer()
      // "LAST N · TOTAL" — communicates that we're showing a recent slice
      // and gives the lifetime context (e.g. "LAST 200 · 193K"). When
      // shown count equals total (early days, < 200 plays), drop the
      // suffix to avoid the redundant "LAST 47 · 47".
      Text(headerCount)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.textMuted.opacity(0.74))
        .contentTransition(.numericText())
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
        Text("HISTORY")
          .font(Dial.Typography.monoLabel)
          .tracking(1.6)
          .foregroundStyle(theme.accent)
      }
      .offset(x: Dial.Layout.SecondaryShell.railLeadingOffset)

      Spacer(minLength: 8)

      Text(headerCount)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.textMuted.opacity(0.74))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .contentTransition(.numericText())
        .offset(x: Dial.Layout.SecondaryShell.railTrailingOffset)
    }
    .padding(.horizontal, 2)
  }

  private var headerCount: String {
    if rows.count >= totalPlays {
      return "LAST \(rows.count)"
    }
    // Compact notation: 193456 → "193K", 1.2M, etc.
    let total = totalPlays.formatted(.number.notation(.compactName))
    return "LAST \(rows.count) · \(total)"
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Spacer()
      Text("No plays yet")
        .font(Dial.Typography.sansTitle)
        .foregroundStyle(theme.textPrimary)
      Text("Play a track in Spotify and it'll show up here.")
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(theme.textMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var historyPlate: some View {
    Group {
      if rows.isEmpty && loaded {
        empty
      } else {
        list
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .modifier(RecessedScreen(depth: 0.42, height: 18))
    .lcdPanel(
      fill: theme.ground.opacity(Dial.Layout.SecondaryShell.plateFillOpacity),
      strokeOpacity: Dial.Layout.SecondaryShell.plateStrokeOpacity)
  }

  private var list: some View {
    ScrollView(.vertical, showsIndicators: true) {
      LazyVStack(spacing: 0) {
        ForEach(rows) { row in
          HistoryRowView(row: row, artworkCache: artworkCache)
          Rectangle().fill(theme.hairline.opacity(0.54)).frame(height: 1)
        }
      }
      .padding(.top, placement == .hardwareShell ? 8 : 0)
      .padding(.bottom, 10)
    }
  }

  private func reload(totalPlays: Int?) {
    reloadLoader.schedule {
      await HistoryViewSnapshot.load(dbq: dbq, totalPlays: totalPlays)
    } apply: { snapshot in
      rows = snapshot.rows
      self.totalPlays = snapshot.totalPlays
      loaded = true
      onSnapshot(snapshot)
    }
  }
}

struct HistoryViewSnapshot {
  let rows: [StatsQueries.HistoryRow]
  let totalPlays: Int

  static func load(dbq: DatabaseQueue, totalPlays: Int?) async -> HistoryViewSnapshot {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let rows = (try? StatsQueries(dbq: dbq).recentPlays(limit: 200)) ?? []
        continuation.resume(returning: HistoryViewSnapshot(
          rows: rows,
          totalPlays: totalPlays ?? rows.count))
      }
    }
  }
}

private struct HistoryRowView: View {
  let row: StatsQueries.HistoryRow
  @Bindable var artworkCache: ArtworkCache
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let urlString = row.albumArtUrl, let image = artworkCache.image(for: urlString) {
          Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(theme.surface)
            .task(id: row.albumArtUrl) {
              guard let albumArtUrl = row.albumArtUrl else { return }
              await artworkCache.load(albumArtUrl)
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
        Text(displayName)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
        Text(displaySubtitle)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.textMuted.opacity(0.82))
          .lineLimit(1)
      }

      Spacer(minLength: 6)

      Text(relative(row.playedAt))
        .font(Dial.Typography.monoTiny)
        .tracking(0.6)
        .foregroundStyle(theme.textMuted.opacity(0.72))
    }
    .padding(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
  }

  /// If the track name is empty (track played before metadata backfill ran),
  /// fall back to a friendly placeholder instead of the raw `spotify:track:…`
  /// URI — the enricher will populate it the next time the app is online.
  private var displayName: String {
    if !row.trackName.isEmpty { return row.trackName }
    return "Loading metadata…"
  }

  private var displaySubtitle: String {
    if row.artistName.isEmpty && (row.albumName ?? "").isEmpty { return "" }
    if let album = row.albumName, !album.isEmpty {
      return row.artistName.isEmpty ? album : "\(row.artistName) · \(album)"
    }
    return row.artistName
  }

  private func relative(_ unix: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(unix))
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: Date())
  }
}
