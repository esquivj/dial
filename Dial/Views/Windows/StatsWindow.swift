// Dial/Views/Windows/StatsWindow.swift
import SwiftUI
import GRDB

struct StatsWindow: View {
  let dbq: DatabaseQueue
  @State private var totals = StatsQueries.Totals(plays: 0, listeningMs: 0, uniqueTracks: 0, uniqueArtists: 0)
  @State private var topTracks: [StatsQueries.TopRow] = []
  @State private var topArtists: [StatsQueries.TopRow] = []
  @State private var pet: PetState? = nil

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        hero
        secondaryStats
        topTracksSection
        topArtistsSection
        if let pet { petPanel(pet) }
      }
      .padding(EdgeInsets(top: 32, leading: 28, bottom: 32, trailing: 28))
    }
    .frame(minWidth: 540, minHeight: 640)
    .background(Dial.Palette.ground)
    .task(id: ObjectIdentifier(dbq)) {
      let observation = StatsQueries(dbq: dbq).observePlaysChanges()
      do {
        for try await _ in observation.values(in: dbq) {
          reload()
        }
      } catch {
        reload()
      }
    }
  }

  // MARK: Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("TOTAL TIME")
        .font(Dial.Typography.monoLabel)
        .tracking(1.8)
        .foregroundStyle(Dial.Palette.muted)
      Text(hoursFormatted(totals.listeningMs))
        .font(.custom("IBMPlexMono-Medium", size: 64))
        .foregroundStyle(Dial.Palette.amber)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text("listening across \(totals.plays) plays")
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(Dial.Palette.muted)
    }
  }

  // MARK: Secondary stats row

  private var secondaryStats: some View {
    HStack(spacing: 32) {
      stat("UNIQUE TRACKS", "\(totals.uniqueTracks)")
      stat("UNIQUE ARTISTS", "\(totals.uniqueArtists)")
      stat("AVG / TRACK", avgPerTrack())
      Spacer()
    }
  }

  private func stat(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      Text(value)
        .font(Dial.Typography.monoValue)        // 28 pt amber numeral
        .foregroundStyle(Dial.Palette.ivory)
    }
  }

  // MARK: Top tracks (with album art)

  private var topTracksSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("TOP TRACKS", count: topTracks.count)
      if topTracks.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topTracks.enumerated()), id: \.element.id) { idx, row in
            TopTrackRow(rank: idx + 1, row: row)
            if idx < topTracks.count - 1 {
              Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
          }
        }
      }
    }
  }

  // MARK: Top artists (compact)

  private var topArtistsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("TOP ARTISTS", count: topArtists.count)
      if topArtists.isEmpty {
        emptyHint()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(topArtists.enumerated()), id: \.element.id) { idx, row in
            HStack(spacing: 12) {
              Text(String(format: "%02d", idx + 1))
                .font(Dial.Typography.monoLabel)
                .foregroundStyle(Dial.Palette.muted)
                .frame(width: 24, alignment: .leading)
              Text(row.name)
                .font(Dial.Typography.sansBody)
                .foregroundStyle(Dial.Palette.ivory)
                .lineLimit(1)
              Spacer()
              Text("\(row.count)")
                .font(Dial.Typography.monoSmall)
                .foregroundStyle(Dial.Palette.amber)
            }
            .padding(.vertical, 8)
            if idx < topArtists.count - 1 {
              Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
          }
        }
      }
    }
  }

  // MARK: Pet panel

  private func petPanel(_ p: PetState) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader("YOUR PET", count: nil)
      HStack(spacing: 20) {
        // Sprite at 4× scale (56 px). Uses the static sprite, not animated, since this is a stats panel.
        PixelSprite(grid: PetSprites.grid(for: p.stage, behavior: .idle), pixelSize: 4)
          .frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 4) {
          Text(p.stage.rawValue.uppercased())
            .font(Dial.Typography.sansTitle)
            .foregroundStyle(Dial.Palette.amber)
          HStack(spacing: 14) {
            label("XP", value: "\(p.xp)")
            label("STREAK", value: "\(p.streakDays)d")
            label("ELDER", value: p.elderUnlockedAt == nil ? "LOCKED" : "UNLOCKED")
          }
        }
        Spacer()
      }
      .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
      .background(Dial.Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private func label(_ key: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(key)
        .font(Dial.Typography.monoLabel)
        .tracking(1.2)
        .foregroundStyle(Dial.Palette.muted)
      Text(value)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.ivory)
    }
  }

  // MARK: Helpers

  private func sectionHeader(_ title: String, count: Int?) -> some View {
    HStack {
      Text(title)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.muted)
      if let count, count > 0 {
        Text("· \(count)")
          .font(Dial.Typography.monoLabel)
          .tracking(1.0)
          .foregroundStyle(Dial.Palette.muted.opacity(0.6))
      }
      Spacer()
    }
  }

  private func emptyHint() -> some View {
    Text("Not enough data yet. Keep listening.")
      .font(Dial.Typography.sansCaption)
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

// MARK: - Top track row (album art + track + artist + count)

private struct TopTrackRow: View {
  let rank: Int
  let row: StatsQueries.TopRow

  var body: some View {
    HStack(spacing: 14) {
      Text(String(format: "%02d", rank))
        .font(Dial.Typography.monoLabel)
        .foregroundStyle(Dial.Palette.muted)
        .frame(width: 24, alignment: .leading)
      AsyncImage(url: row.artUrl.flatMap(URL.init(string:))) { img in
        img.resizable()
      } placeholder: {
        Rectangle().fill(Dial.Palette.surface)
      }
      .frame(width: 40, height: 40)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      VStack(alignment: .leading, spacing: 2) {
        Text(row.name)
          .font(Dial.Typography.sansBody)
          .foregroundStyle(Dial.Palette.ivory)
          .lineLimit(1)
        if let subtitle = row.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(Dial.Typography.sansCaption)
            .foregroundStyle(Dial.Palette.muted)
            .lineLimit(1)
        }
      }
      Spacer()
      Text("\(row.count)")
        .font(Dial.Typography.monoValue)        // 28 pt amber
        .foregroundStyle(Dial.Palette.amber)
    }
    .padding(.vertical, 10)
  }
}
