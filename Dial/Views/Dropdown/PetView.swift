// Dial/Views/Dropdown/PetView.swift
import SwiftUI
import GRDB

/// Dedicated pet screen — a focused view of the bulldog with the stats
/// and progress info that don't fit on the main HUD's tiny StatusRail
/// thumbnail. Reachable via:
///
///   * tapping the pet sprite in the StatusRail
///   * right-click on the menubar icon → Open Pet
///
/// Layout follows the same back-button / panel pattern as HistoryView and
/// StatsView so transitions feel consistent.
struct PetView: View {
  @Bindable var pet: PetViewModel
  let dbq: DatabaseQueue
  let onBack: () -> Void

  @State private var lifetimePlays: Int = 0
  @State private var petState: PetState? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      content
    }
    .task(id: ObjectIdentifier(dbq)) {
      reload()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 10) {
      BackButton(action: onBack)
      Text("PET")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.amber)
      Spacer()
      Text(pet.stage.rawValue.uppercased())
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
        .contentTransition(.opacity)
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 14))
  }

  // MARK: - Content

  private var content: some View {
    VStack(alignment: .leading, spacing: 18) {
      spriteCard
      xpSection
      statsList
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 18, leading: 14, bottom: 14, trailing: 14))
  }

  // MARK: - Sprite

  /// Larger LCD-within-LCD frame, same Tamagotchi-housing aesthetic as the
  /// StatusRail thumbnail but ~3× the size — gives the bulldog room to be
  /// the focal point.
  private var spriteCard: some View {
    HStack {
      Spacer(minLength: 0)
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.black.opacity(0.55))
        BulldogSprite(stage: pet.stage, behavior: pet.behavior, height: 80)
          .frame(width: 80, height: 80)
      }
      .frame(width: 100, height: 100)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(Dial.Palette.amber.opacity(0.55), lineWidth: 1)
      )
      .shadow(color: Dial.Palette.amber.opacity(0.35), radius: 10, x: 0, y: 0)
      Spacer(minLength: 0)
    }
  }

  // MARK: - XP

  private var xpSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("XP")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.muted)
        Spacer()
        Text("\(formatXP(pet.xp)) / \(formatXP(nextThreshold))")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(Dial.Palette.amber)
          .monospacedDigit()
          .contentTransition(.numericText())
      }
      progressBar
    }
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Dial.Palette.surface)
          .frame(height: 5)
        Capsule()
          .fill(Dial.Palette.amber)
          .frame(width: max(0, xpProgress * proxy.size.width), height: 5)
          .shadow(color: Dial.Palette.amber.opacity(0.7), radius: 4, x: 0, y: 0)
      }
    }
    .frame(height: 5)
  }

  // MARK: - Stats

  private var statsList: some View {
    VStack(spacing: 10) {
      statRow("STREAK", value: "\(pet.streakDays) \(pet.streakDays == 1 ? "DAY" : "DAYS")")
      statRow("HATCHED", value: hatchedLabel)
      if !isElder, let until = daysUntilElder {
        statRow("DAYS UNTIL ELDER", value: "\(until) \(until == 1 ? "DAY" : "DAYS")")
      }
      statRow("LIFETIME PLAYS", value: lifetimePlays.formatted(.number.notation(.compactName)))
    }
  }

  private func statRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      Spacer()
      Text(value)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.ivory)
        .monospacedDigit()
        .contentTransition(.numericText())
    }
  }

  // MARK: - Reload

  private func reload() {
    petState = (try? PetStateDAO(dbq: dbq).get()) ?? nil
    lifetimePlays = (try? StatsQueries(dbq: dbq).totals().plays) ?? 0
  }

  // MARK: - Computed

  /// XP threshold for the *next* stage above the pet's current stage.
  /// Caps at 100k (elder).
  private var nextThreshold: Int64 {
    let cur = pet.stage
    let pairs = PetStageTable.thresholds
    if let idx = pairs.firstIndex(where: { $0.stage == cur }), idx + 1 < pairs.count {
      return pairs[idx + 1].xp
    }
    return pairs.last?.xp ?? 100_000
  }

  /// 0…1 progress within the current stage's range.
  private var xpProgress: CGFloat {
    let pairs = PetStageTable.thresholds
    let cur = pet.stage
    guard let idx = pairs.firstIndex(where: { $0.stage == cur }) else { return 0 }
    let lower = pairs[idx].xp
    let upper = idx + 1 < pairs.count ? pairs[idx + 1].xp : pairs[idx].xp
    if upper == lower { return 1 }  // elder, max stage
    let p = Double(pet.xp - lower) / Double(upper - lower)
    return CGFloat(min(1, max(0, p)))
  }

  private var isElder: Bool { pet.stage == .elder }

  private var hatchedLabel: String {
    guard let hatched = petState?.hatchedAt else { return "INCUBATING" }
    let now = Int64(Date().timeIntervalSince1970)
    let days = max(0, (now - hatched) / 86_400)
    return "\(days) \(days == 1 ? "DAY" : "DAYS") AGO"
  }

  /// Elder unlocks 30 days after install (per PetEngine). Returns nil
  /// once already elder.
  private var daysUntilElder: Int64? {
    guard let installed = petState?.installedAt, !isElder else { return nil }
    let elderUnlockEpoch = installed + 30 * 86_400
    let now = Int64(Date().timeIntervalSince1970)
    let remainingSec = elderUnlockEpoch - now
    return max(0, remainingSec / 86_400)
  }

  private func formatXP(_ x: Int64) -> String {
    Int(x).formatted(.number.notation(.compactName))
  }
}
