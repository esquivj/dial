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
  @Bindable var aggCache: AggregationsCache
  @Bindable var menubar: MenubarStripViewModel
  let dbq: DatabaseQueue
  let onBack: () -> Void

  @State private var lifetimePlays: Int = 0
  @State private var todayListeningMs: Int64 = 0
  @State private var recentBadgeCounts: [BadgeCategory: Int] = [:]
  @State private var unlockedTricks: [PetTrickUnlock] = []
  @State private var petState: PetState? = nil
  @State private var actionFeedback: String?
  @State private var interactionBehavior: PetBehavior?
  @State private var actionPulse = false
  @State private var feedbackTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      ScrollView {
        content
      }
    }
    .task(id: ObjectIdentifier(dbq)) {
      reload()
    }
    .onChange(of: pet.xp) { _, _ in reload() }
    .onChange(of: pet.streakDays) { _, _ in reload() }
    .onDisappear {
      feedbackTask?.cancel()
      feedbackTask = nil
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: Dial.Layout.Header.spacing) {
      BackButton(action: onBack)
      Text("PET")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(Dial.Palette.accent)
      Spacer()
      Text(pet.stage.rawValue.uppercased())
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.textMuted)
        .contentTransition(.opacity)
    }
    .padding(EdgeInsets(
      top: Dial.Layout.Header.topPadding,
      leading: Dial.Layout.Header.leadingPadding,
      bottom: Dial.Layout.Header.bottomPadding,
      trailing: Dial.Layout.Header.trailingPadding))
  }

  // MARK: - Content

  private var content: some View {
    VStack(alignment: .leading, spacing: Dial.Layout.SecondaryScreen.petSectionSpacing) {
      spriteCard
      bondLoopSection
      xpSection
      statsList
    }
    .padding(Dial.Layout.SecondaryScreen.petContentPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Sprite

  /// Larger LCD-within-LCD frame. The dedicated pet screen should let the
  /// sprite become the object, while still leaving visible screen padding
  /// so it feels housed inside old handheld glass.
  private var spriteCard: some View {
    HStack {
      Spacer(minLength: 0)
      ZStack {
        // Tamagotchi-style "powered LCD" inside the bezel (matches the
        // smaller pet block in TrackHero) — black-and-white pet silhouette
        // on a muted green-gray lit screen.
        RoundedRectangle(cornerRadius: 8)
          .fill(Dial.Palette.lcd)
        BulldogSprite(stage: pet.stage, behavior: displayBehavior, height: 88)
          .frame(width: 90, height: 90)
          .scaleEffect(actionPulse ? 1.045 : 1)
          .animation(.easeOut(duration: 0.16), value: actionPulse)
      }
      .frame(width: 116, height: 116)
      .dialRaisedGel(
        shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
        fill: Dial.Palette.lcd,
        edgeOpacity: 0.36,
        fillTopOpacity: 0.07,
        fillBottomOpacity: 0.025,
        sheenOpacity: 0.44,
        sheenLineWidth: 1.1,
        contactShadowOpacity: 0,
        innerShadowOpacity: 0.20)
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .inset(by: 4)
          .stroke(Dial.Palette.accent.opacity(0.24), lineWidth: 0.7)
      )
      .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
      Spacer(minLength: 0)
    }
  }

  // MARK: - Bond loop

  private var bondLoopSection: some View {
    let snapshot = bondSnapshot

    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(snapshot.moodLabel)
          .font(Dial.Typography.sansTitle)
          .foregroundStyle(Dial.Palette.textPrimary)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text("\(percent(snapshot.bondScore)) BOND")
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.textMuted)
          .monospacedDigit()
      }

      Text(actionFeedback ?? snapshot.reason)
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(actionFeedback == nil ? Dial.Palette.textMuted : Dial.Palette.accent)
        .lineLimit(2)
        .minimumScaleFactor(0.82)
        .contentTransition(.opacity)

      VStack(spacing: 6) {
        PetBondMeter(label: "Bond", value: snapshot.bondScore, color: Dial.Palette.accent)
        PetBondMeter(label: "Discovery", value: snapshot.discoveryScore, color: Dial.Palette.accentAlt)
        PetBondMeter(label: "Energy", value: snapshot.energyScore, color: energyColor(snapshot.energyScore))
      }

      Button {
        runPrimaryAction(snapshot)
      } label: {
        HStack(spacing: 7) {
          DialThickIcon(iconName(for: snapshot.primaryAction), size: 12, weight: 0.55)
          Text(snapshot.primaryAction.label)
            .font(Dial.Typography.monoLabel)
            .tracking(1.1)
          Spacer(minLength: 0)
        }
        .foregroundStyle(Dial.Palette.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Dial.Palette.surface.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .stroke(Dial.Palette.hairline.opacity(0.95), lineWidth: 1)
        )
      }
      .buttonStyle(.pressable)

      if !unlockedTricks.isEmpty {
        unlockedTricksStrip
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var unlockedTricksStrip: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Tricks")
        .font(Dial.Typography.monoTiny)
        .tracking(0.9)
        .foregroundStyle(Dial.Palette.textMuted)
      HStack(spacing: 6) {
        ForEach(unlockedTricks) { unlock in
          Text(unlock.trick.label)
            .font(Dial.Typography.monoTiny)
            .tracking(0.5)
            .foregroundStyle(Dial.Palette.textPrimary.opacity(0.88))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Dial.Palette.surface.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(Dial.Palette.hairline.opacity(0.88), lineWidth: 1)
            )
        }
        Spacer(minLength: 0)
      }
    }
  }

  // MARK: - XP

  private var xpSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        // Body-content label, mixed-case sansCaption (was mono-caps).
        Text("Evolution")
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(Dial.Palette.textMuted)
        Spacer()
        Text(evolutionStatus)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(Dial.Palette.accent)
          .monospacedDigit()
          .contentTransition(.numericText())
      }
      progressBar
      stageRail
      Text(xpDetailText)
        .font(.system(size: 10))
        .foregroundStyle(Dial.Palette.textMuted.opacity(0.76))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Evolution progress")
    .accessibilityValue(accessibilityXPValue)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      let fillWidth = visibleXPFillWidth(in: proxy.size.width)
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Dial.Palette.surface.opacity(0.9))
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(Dial.Palette.hairline.opacity(0.95), lineWidth: 1)
          )
          .frame(height: xpBarHeight)

        RoundedRectangle(cornerRadius: 4)
          .fill(Dial.Palette.accent)
          .frame(width: fillWidth, height: xpBarHeight)

        if fillWidth > 0 {
          Circle()
            .fill(Dial.Palette.textPrimary.opacity(0.9))
            .frame(width: 3, height: 3)
            .offset(x: max(4, min(fillWidth - 5, proxy.size.width - 7)))
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: xpBarHeight)
  }

  private var stageRail: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(stageName(pet.stage))
        .font(Dial.Typography.monoTiny)
        .tracking(0.8)
        .foregroundStyle(Dial.Palette.textPrimary.opacity(0.82))
      Text("->")
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.textMuted.opacity(0.62))
      if let next = nextStage {
        Text(stageName(next))
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.accent.opacity(0.9))
      } else {
        Text("MAX")
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.accent.opacity(0.9))
      }
      Spacer(minLength: 8)
    }
  }

  // MARK: - Stats

  private var statsList: some View {
    VStack(spacing: 10) {
      statRow("Live streak", value: "\(pet.streakDays) \(pet.streakDays == 1 ? "day" : "days")")
      statRow("Hatched", value: hatchedLabel)
      if !isElder, let until = daysUntilElder {
        statRow("Days until elder", value: "\(until) \(until == 1 ? "day" : "days")")
      }
      statRow("Lifetime plays", value: lifetimePlays.formatted(.number.notation(.compactName)))
    }
  }

  /// Mixed-case sansCaption labels (was mono-caps) — these are body content
  /// inside a screen, not device chrome. The 1.4-tracked mono-caps treatment
  /// is reserved for actual chrome (PET title, NOW PLAYING, SPECTRUM, etc.)
  /// so it doesn't get diluted by appearing on every label everywhere.
  private func statRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(Dial.Typography.sansCaption)
        .foregroundStyle(Dial.Palette.textMuted)
      Spacer()
      Text(value)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.textPrimary)
        .monospacedDigit()
        .contentTransition(.numericText())
    }
  }

  // MARK: - Reload

  private func reload() {
    let queries = StatsQueries(dbq: dbq)
    petState = (try? PetStateDAO(dbq: dbq).get()) ?? nil
    lifetimePlays = (try? queries.totals().plays) ?? 0
    todayListeningMs = (try? queries.totals(since: startOfTodayEpoch()).listeningMs) ?? 0
    let recentCutoff = Int64(Date().timeIntervalSince1970) - 7 * 86_400
    let summaries = (try? queries.badgeSummaries(since: recentCutoff)) ?? []
    recentBadgeCounts = summaries.reduce(into: [:]) { acc, summary in
      acc[summary.category] = summary.count
    }
    unlockedTricks = (try? PetTrickUnlocksDAO(dbq: dbq).all()) ?? []
  }

  // MARK: - Computed

  private var displayBehavior: PetBehavior {
    interactionBehavior ?? pet.behavior
  }

  private var bondSnapshot: PetBondSnapshot {
    PetBondSnapshot.make(.init(
      xp: pet.xp,
      streakDays: pet.streakDays,
      playsYTDForCurrentTrack: aggCache.playsYTD,
      playbackState: menubar.state,
      todayListeningMs: todayListeningMs,
      recentBadgeCounts: recentBadgeCounts,
      currentBadge: aggCache.currentBadgeInsight,
      currentTrackName: menubar.track?.name,
      unlockedTricks: unlockedTricks.map(\.trick)))
  }

  private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private func energyColor(_ value: Double) -> Color {
    value < 0.22 ? Dial.Palette.textMuted : Dial.Palette.accent
  }

  private func iconName(for action: PetBondPrimaryAction) -> String {
    switch action {
    case .rememberThis: return "clock.arrow.circlepath"
    case .teachTrick: return "sparkles"
    case .wakeUp: return "flame.fill"
    case .showFavorite: return "heart.fill"
    case .showTrick: return "sparkles"
    case .syncToBeat: return "music.note"
    case .checkIn: return "heart"
    }
  }

  private func runPrimaryAction(_ snapshot: PetBondSnapshot) {
    feedbackTask?.cancel()

    let reaction: (text: String, behavior: PetBehavior)
    switch snapshot.primaryAction {
    case .rememberThis:
      reaction = (
        aggCache.currentBadgeInsight.map { "Memory held: \($0.kind.label)." } ?? "Memory held.",
        behaviorForCurrentBadge()
      )
    case .teachTrick(let trick):
      let didUnlock = (try? PetTrickUnlocksDAO(dbq: dbq)
        .unlock(trick, sourceBadge: aggCache.currentBadgeInsight?.kind)) ?? false
      reload()
      reaction = (
        didUnlock ? "\(trick.label) unlocked." : "\(trick.label) already unlocked.",
        behavior(for: trick)
      )
    case .wakeUp:
      reaction = ("Nudge sent. Start a track to wake it fully.", .walk)
    case .showFavorite:
      reaction = ("Favorite signal locked.", .beatSync(bpm: pet.currentBPM ?? 118))
    case .showTrick(let trick):
      reaction = ("Showing \(trick.label).", behavior(for: trick))
    case .syncToBeat:
      reaction = ("Beat sync engaged.", .beatSync(bpm: pet.currentBPM ?? 118))
    case .checkIn:
      reaction = ("Still with you.", .idle)
    }

    actionFeedback = reaction.text
    interactionBehavior = reaction.behavior
    withAnimation(.easeOut(duration: 0.16)) { actionPulse = true }

    feedbackTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 180_000_000)
      actionPulse = false
      try? await Task.sleep(nanoseconds: 1_350_000_000)
      actionFeedback = nil
      interactionBehavior = nil
      feedbackTask = nil
    }
  }

  private func behavior(for trick: PetTrick) -> PetBehavior {
    return trick.displayBehavior
  }

  private func behaviorForCurrentBadge() -> PetBehavior {
    switch aggCache.currentBadgeInsight?.kind {
    case .firstListen, .newArtist:
      return .expressed(.firstListen, motion: currentMotion)
    case .rediscovered, .deepCut:
      return .expressed(.rediscovered, motion: currentMotion)
    case .play10, .play50, .play100, .anniversary:
      return .expressed(.levelUp, motion: currentMotion)
    case .onStreak, .repeatTrack, .albumMode:
      return .eating
    case nil:
      return .walk
    }
  }

  private var currentMotion: PetMotion {
    guard menubar.state == .playing else { return .idle }
    if let bpm = pet.currentBPM { return .beatSync(bpm: bpm) }
    return .walk
  }

  private func startOfTodayEpoch() -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let start = calendar.startOfDay(for: Date())
    return Int64(start.timeIntervalSince1970)
  }

  /// XP threshold for the *next* stage above the pet's current stage.
  /// Caps at 100k (elder).
  private var nextThreshold: Int64 {
    nextStagePair?.xp ?? PetStageTable.thresholds.last?.xp ?? 100_000
  }

  private var nextStage: PetStage? {
    nextStagePair?.stage
  }

  private var nextStagePair: (stage: PetStage, xp: Int64)? {
    let cur = pet.stage
    let pairs = PetStageTable.thresholds
    if let idx = pairs.firstIndex(where: { $0.stage == cur }), idx + 1 < pairs.count {
      return pairs[idx + 1]
    }
    return nil
  }

  private var stageLowerThreshold: Int64 {
    PetStageTable.thresholds.first(where: { $0.stage == pet.stage })?.xp ?? 0
  }

  private var stageSpanXP: Int64 {
    max(0, nextThreshold - stageLowerThreshold)
  }

  private var stageProgressXP: Int64 {
    guard stageSpanXP > 0 else { return 0 }
    return min(stageSpanXP, max(0, pet.xp - stageLowerThreshold))
  }

  private var xpUntilNext: Int64 {
    guard nextStage != nil else { return 0 }
    return max(0, nextThreshold - pet.xp)
  }

  private var evolutionStatus: String {
    guard let next = nextStage else { return "MAX STAGE" }
    if next == .elder, xpUntilNext == 0, let until = daysUntilElder, until > 0 {
      return "\(until)D TO ELDER"
    }
    return "\(formatXP(xpUntilNext)) TO \(stageName(next).uppercased())"
  }

  private var xpDetailText: String {
    guard let next = nextStage else {
      return "\(formatXP(pet.xp)) lifetime XP · max stage reached"
    }
    let stageProgress = "\(formatXP(stageProgressXP)) / \(formatXP(stageSpanXP)) stage XP"
    if next == .elder, let until = daysUntilElder, until > 0 {
      return "\(stageProgress) · elder unlocks in \(until)d"
    }
    return "\(stageProgress) · \(formatXP(pet.xp)) lifetime XP"
  }

  private var accessibilityXPValue: String {
    guard let next = nextStage else {
      return "\(formatXP(pet.xp)) lifetime XP, max stage reached"
    }
    return "\(formatXP(stageProgressXP)) of \(formatXP(stageSpanXP)) XP toward \(stageName(next))"
  }

  /// 0…1 progress within the current stage's range.
  private var xpProgress: CGFloat {
    if nextStage == nil { return 1 }
    guard stageSpanXP > 0 else { return 1 }
    let p = Double(stageProgressXP) / Double(stageSpanXP)
    return CGFloat(min(1, max(0, p)))
  }

  private var xpBarHeight: CGFloat { 9 }

  private func visibleXPFillWidth(in availableWidth: CGFloat) -> CGFloat {
    guard availableWidth > 0, xpProgress > 0 else { return 0 }
    if xpProgress >= 1 { return availableWidth }
    // At companion, early real progress can be a 2-3 px sliver. Keep a
    // visible nonzero fill while the exact XP text carries the true math.
    return min(availableWidth, max(availableWidth * xpProgress, 12))
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

  private func stageName(_ stage: PetStage) -> String {
    stage.rawValue.uppercased()
  }
}

private struct PetBondMeter: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .font(Dial.Typography.monoTiny)
        .tracking(0.7)
        .foregroundStyle(Dial.Palette.textMuted)
        .frame(width: 58, alignment: .leading)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3)
            .fill(Dial.Palette.surface.opacity(0.92))
          RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: max(4, proxy.size.width * CGFloat(min(1, max(0, value)))))
        }
      }
      .frame(height: 6)

      Text("\(Int((value * 100).rounded()))")
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.textPrimary.opacity(0.82))
        .monospacedDigit()
        .frame(width: 24, alignment: .trailing)
    }
    .frame(height: 12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label) \(Int((value * 100).rounded())) percent")
  }
}
