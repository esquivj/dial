// Dial/Views/Dropdown/StatsView.swift
import SwiftUI
import GRDB

/// Inline Stats panel — replaces the dropdown body when the user taps STATS
/// in the controls bar. Compact editorial layout designed for ~320 wide.
struct StatsView: View {
  let dbq: DatabaseQueue
  let onBack: () -> Void
  @State private var totals = StatsQueries.Totals(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0)
  @State private var topTracks: [StatsQueries.TopRow] = []
  @State private var topArtists: [StatsQueries.TopRow] = []
  @State private var pet: PetState? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          hero
          secondaryStats
          topTracksSection
          topArtistsSection
          if let pet { petPanel(pet) }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 16, trailing: 14))
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
      Text("STATS")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.amber)
      Spacer()
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 14))
  }

  // MARK: Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("TOTAL TIME")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.muted)
      Text(hoursFormatted(totals.listeningMs))
        .font(.custom("IBMPlexMono-Medium", size: 40))
        .foregroundStyle(Dial.Palette.amber)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text("across \(totals.plays) \(totals.plays == 1 ? "play" : "plays")")
        .font(.system(size: 10))
        .foregroundStyle(Dial.Palette.muted)
    }
  }

  // MARK: Secondary stats — single row

  private var secondaryStats: some View {
    HStack(spacing: 16) {
      stat("TRACKS", "\(totals.uniqueTracks)")
      stat("ARTISTS", "\(totals.uniqueArtists)")
      stat("AVG", avgPerTrack())
      Spacer()
    }
  }

  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(1.2)
        .foregroundStyle(Dial.Palette.muted)
      Text(value)
        .font(.custom("IBMPlexMono-Medium", size: 18))
        .foregroundStyle(Dial.Palette.ivory)
    }
  }

  // MARK: Top tracks (compact, with album art)

  private var topTracksSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionHeader("TOP TRACKS", count: topTracks.count)
      if topTracks.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topTracks.prefix(5).enumerated()), id: \.element.id) { idx, row in
            TopTrackRow(rank: idx + 1, row: row)
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
      sectionHeader("TOP ARTISTS", count: topArtists.count)
      if topArtists.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topArtists.prefix(5).enumerated()), id: \.element.id) { idx, row in
            HStack(spacing: 10) {
              Text(String(format: "%02d", idx + 1))
                .font(Dial.Typography.monoTiny)
                .foregroundStyle(Dial.Palette.muted)
                .frame(width: 18, alignment: .leading)
              Text(row.name)
                .font(Dial.Typography.sansCaption)
                .foregroundStyle(Dial.Palette.ivory)
                .lineLimit(1)
              Spacer()
              Text("\(row.count)")
                .font(Dial.Typography.monoTiny)
                .foregroundStyle(Dial.Palette.amber)
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

  // MARK: Pet panel

  private func petPanel(_ p: PetState) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionHeader("YOUR PET", count: nil)
      HStack(spacing: 12) {
        PixelSprite(grid: PetSprites.grid(for: p.stage, behavior: .idle), pixelSize: 3)
          .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(p.stage.rawValue.uppercased())
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.amber)
          HStack(spacing: 10) {
            label("XP", value: "\(p.xp)")
            label("STREAK", value: "\(p.streakDays)d")
          }
        }
        Spacer()
      }
      .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
      .background(Dial.Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 4))
    }
  }

  private func label(_ key: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(key)
        .font(Dial.Typography.monoTiny)
        .tracking(1.0)
        .foregroundStyle(Dial.Palette.muted)
      Text(value)
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.ivory)
    }
  }

  // MARK: Helpers

  private func sectionHeader(_ title: String, count: Int?) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.muted)
      if let count, count > 0 {
        Text("· \(count)")
          .font(Dial.Typography.monoLabel)
          .foregroundStyle(Dial.Palette.muted.opacity(0.6))
      }
      Spacer()
    }
  }

  private func emptyHint() -> some View {
    Text("Not enough data yet")
      .font(.system(size: 10))
      .foregroundStyle(Dial.Palette.muted.opacity(0.7))
      .padding(.vertical, 4)
  }

  private func hoursFormatted(_ ms: Int64) -> String {
    let totalSec = ms / 1000
    let h = totalSec / 3600
    let m = (totalSec % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "—"
  }

  private func avgPerTrack() -> String {
    guard totals.uniqueTracks > 0 else { return "—" }
    return String(format: "%.1f", Double(totals.plays) / Double(totals.uniqueTracks))
  }

  private func reload() {
    let q = StatsQueries(dbq: dbq)
    totals = (try? q.totals()) ?? totals
    topTracks = (try? q.topTracks()) ?? []
    topArtists = (try? q.topArtists()) ?? []
    pet = try? PetStateDAO(dbq: dbq).get()
  }
}

private struct TopTrackRow: View {
  let rank: Int
  let row: StatsQueries.TopRow

  var body: some View {
    HStack(spacing: 10) {
      Text(String(format: "%02d", rank))
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.muted)
        .frame(width: 18, alignment: .leading)
      AsyncImage(url: row.artUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        Rectangle().fill(Dial.Palette.surface)
      }
      .frame(width: 28, height: 28)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      VStack(alignment: .leading, spacing: 1) {
        Text(row.name)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        if let subtitle = row.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(Dial.Palette.muted)
            .lineLimit(1)
        }
      }
      Spacer()
      Text("\(row.count)")
        .font(.custom("IBMPlexMono-Medium", size: 16))
        .foregroundStyle(Dial.Palette.amber)
    }
    .padding(.vertical, 6)
  }
}
