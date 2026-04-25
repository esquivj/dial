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
      VStack(alignment: .leading, spacing: 24) {
        Text("STATS")
          .font(Dial.Typography.monoLabel)
          .tracking(1.6)
          .foregroundStyle(Dial.Palette.amber)

        totalsGrid

        section(title: "TOP TRACKS", rows: topTracks)
        section(title: "TOP ARTISTS", rows: topArtists)

        if let pet { petPanel(pet) }
      }
      .padding(24)
    }
    .frame(minWidth: 480, minHeight: 600)
    .background(Dial.Palette.ground)
    .task { reload() }
  }

  private var totalsGrid: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      totalsCell("TOTAL PLAYS", value: "\(totals.plays)")
      totalsCell("LISTENING TIME", value: hours(totals.listeningMs))
      totalsCell("UNIQUE TRACKS", value: "\(totals.uniqueTracks)")
      totalsCell("UNIQUE ARTISTS", value: "\(totals.uniqueArtists)")
    }
  }

  private func totalsCell(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      Text(value)
        .font(Dial.Typography.monoValue)
        .foregroundStyle(Dial.Palette.amber)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    .background(Dial.Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func section(title: String, rows: [StatsQueries.TopRow]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.muted)
      if rows.isEmpty {
        Text("Not enough data yet")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.muted.opacity(0.7))
          .padding(.vertical, 6)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
            HStack(spacing: 12) {
              Text(String(format: "%02d", idx + 1))
                .font(Dial.Typography.monoLabel)
                .foregroundStyle(Dial.Palette.muted)
                .frame(width: 22, alignment: .leading)
              Text(row.name)
                .font(Dial.Typography.sansBody)
                .foregroundStyle(Dial.Palette.ivory)
                .lineLimit(1)
              Spacer(minLength: 8)
              Text("\(row.count)")
                .font(Dial.Typography.monoSmall)
                .foregroundStyle(Dial.Palette.amber)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(idx.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.02))
          }
        }
        .background(Dial.Palette.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
      }
    }
  }

  private func petPanel(_ p: PetState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("PET")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.muted)
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(p.stage.rawValue.uppercased())
            .font(Dial.Typography.sansTitle)
            .foregroundStyle(Dial.Palette.amber)
          Text("\(p.xp) XP")
            .font(Dial.Typography.monoSmall)
            .foregroundStyle(Dial.Palette.muted)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text("\(p.streakDays)-DAY STREAK")
            .font(Dial.Typography.monoLabel)
            .tracking(1.2)
            .foregroundStyle(Dial.Palette.ivory)
          Text(p.elderUnlockedAt == nil ? "Elder locked" : "Elder unlocked")
            .font(Dial.Typography.monoLabel)
            .foregroundStyle(Dial.Palette.muted)
        }
      }
      .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
      .background(Dial.Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private func hours(_ ms: Int64) -> String {
    let totalSec = ms / 1000
    let h = totalSec / 3600
    let m = (totalSec % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
  }

  private func reload() {
    let q = StatsQueries(dbq: dbq)
    totals = (try? q.totals()) ?? totals
    topTracks = (try? q.topTracks()) ?? []
    topArtists = (try? q.topArtists()) ?? []
    pet = try? PetStateDAO(dbq: dbq).get()
  }
}
