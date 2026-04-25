// Dial/Views/Dropdown/HistoryView.swift
import SwiftUI
import GRDB

/// Inline History panel — replaces the dropdown body when the user taps
/// HISTORY in the controls bar. Lives in the same NSPopover, sized to the
/// dropdown's frame.
struct HistoryView: View {
  let dbq: DatabaseQueue
  let onBack: () -> Void
  @State private var rows: [StatsQueries.HistoryRow] = []
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
      if rows.isEmpty && loaded {
        empty
      } else {
        list
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
  }

  private var header: some View {
    HStack(spacing: 10) {
      BackButton(action: onBack)
      Text("HISTORY")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.amber)
      Spacer()
      Text("\(rows.count) PLAYS")
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 14))
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Spacer()
      Text("No plays yet")
        .font(Dial.Typography.sansTitle)
        .foregroundStyle(Dial.Palette.ivory)
      Text("Play a track in Spotify and it'll show up here.")
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(Dial.Palette.muted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(rows) { row in
          HistoryRowView(row: row)
          Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
      }
    }
  }

  private func reload() {
    let q = StatsQueries(dbq: dbq)
    rows = (try? q.recentPlays(limit: 500)) ?? []
    loaded = true
  }
}

private struct HistoryRowView: View {
  let row: StatsQueries.HistoryRow

  var body: some View {
    HStack(spacing: 10) {
      AsyncImage(url: row.albumArtUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        Rectangle().fill(Dial.Palette.surface)
      }
      .frame(width: 28, height: 28)
      .clipShape(RoundedRectangle(cornerRadius: 3))

      VStack(alignment: .leading, spacing: 1) {
        Text(displayName)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        Text(displaySubtitle)
          .font(.system(size: 10))
          .foregroundStyle(Dial.Palette.muted)
          .lineLimit(1)
      }

      Spacer(minLength: 6)

      Text(relative(row.playedAt))
        .font(Dial.Typography.monoTiny)
        .tracking(0.6)
        .foregroundStyle(Dial.Palette.muted)
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
