// Dial/Views/Windows/HistoryWindow.swift
import SwiftUI
import GRDB

/// Standalone window listing every play in reverse chronological order.
struct HistoryWindow: View {
  let dbq: DatabaseQueue
  @State private var rows: [StatsQueries.HistoryRow] = []
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider().background(Color.white.opacity(0.08))
      if rows.isEmpty && loaded {
        empty
      } else {
        list
      }
    }
    .frame(minWidth: 480, minHeight: 600)
    .background(Dial.Palette.ground)
    .task(id: ObjectIdentifier(dbq)) {
      let observation = StatsQueries(dbq: dbq).observePlaysChanges()
      do {
        for try await _ in observation.values(in: dbq) {
          reload()
        }
      } catch {
        // Initial load fallback if the stream errors.
        reload()
      }
    }
  }

  private var header: some View {
    HStack {
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
    .padding(EdgeInsets(top: 18, leading: 20, bottom: 12, trailing: 20))
  }

  private var empty: some View {
    VStack(spacing: 8) {
      Spacer()
      Text("No plays yet")
        .font(Dial.Typography.sansTitle)
        .foregroundStyle(Dial.Palette.ivory)
      Text("Play a track in Spotify and it'll show up here.")
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(Dial.Palette.muted)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(rows) { row in
          HistoryRowView(row: row)
          Divider().background(Color.white.opacity(0.05))
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
    HStack(spacing: 12) {
      AsyncImage(url: row.albumArtUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        Rectangle().fill(Dial.Palette.surface)
      }
      .frame(width: 36, height: 36)
      .clipShape(RoundedRectangle(cornerRadius: 3))

      VStack(alignment: .leading, spacing: 2) {
        Text(row.trackName.isEmpty ? row.trackUri : row.trackName)
          .font(Dial.Typography.sansBody)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        HStack(spacing: 4) {
          Text(row.artistName)
            .foregroundStyle(Dial.Palette.muted)
          if let album = row.albumName, !album.isEmpty {
            Text("·").foregroundStyle(Dial.Palette.muted.opacity(0.5))
            Text(album).foregroundStyle(Dial.Palette.muted.opacity(0.7))
          }
        }
        .font(Dial.Typography.sansCaption)
        .lineLimit(1)
      }

      Spacer(minLength: 8)

      Text(relative(row.playedAt))
        .font(Dial.Typography.monoLabel)
        .tracking(1.0)
        .foregroundStyle(Dial.Palette.muted)
    }
    .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
  }

  private func relative(_ unix: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(unix))
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: Date())
  }
}
