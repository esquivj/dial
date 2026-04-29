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

  @State private var todayListeningMs: Int64 = 0
  @State private var recentBadgeCounts: [BadgeCategory: Int] = [:]
  @State private var unlockedTricks: [PetTrickUnlock] = []
  @State private var artifacts: [Artifact] = []
  @State private var petState: PetState? = nil
  @State private var actionFeedback: String?
  @State private var interactionBehavior: PetBehavior?
  @State private var actionPulse = false
  @State private var feedbackTask: Task<Void, Never>?
  @Environment(\.dialTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(Dial.Palette.hairline).frame(height: 1)
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
      Text("ROOM")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(theme.accent)
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
    VStack(alignment: .leading, spacing: 5) {
      petCompanionPanel
      artifactShelf
      xpSection
    }
    .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Companion

  /// Keep the pet as a housed object, not a full-width stats widget. The LCD
  /// belongs to the creature; mood/action live around it on the device surface.
  private var petCompanionPanel: some View {
    let snapshot = bondSnapshot
    let panelShape = RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)

    return VStack(spacing: 5) {
      RoomSceneView(
        pet: pet,
        behavior: displayBehavior,
        artifacts: artifacts,
        actionPulse: actionPulse)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              if let badge = aggCache.currentBadgeInsight {
                BadgePixelIcon(kind: badge.kind, color: badge.kind.category == .pattern ? theme.accentAlt : theme.accent, size: 11)
              }
              Text(snapshot.moodLabel)
                .font(Dial.Typography.sansCaption)
                .foregroundStyle(Dial.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            }

            Text(actionFeedback ?? snapshot.reason)
              .font(Dial.Typography.monoSmall)
              .foregroundStyle(actionFeedback == nil ? Dial.Palette.textMuted : theme.accent)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
              .contentTransition(.opacity)
          }

          Spacer(minLength: 8)

          VStack(alignment: .trailing, spacing: 2) {
            Text(percent(snapshot.bondScore))
              .font(Dial.Typography.sansCaption)
              .foregroundStyle(theme.accent)
              .monospacedDigit()
            Text("BOND")
              .font(Dial.Typography.monoTiny)
              .tracking(0.8)
              .foregroundStyle(Dial.Palette.textMuted)
          }
          .frame(width: 46, alignment: .trailing)
        }

        HStack(spacing: 8) {
          roomAction(snapshot)
          roomBondGauge(snapshot)
        }
      }
    }
    .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
    .frame(maxWidth: .infinity)
    .dialRecessedPanel(
      shape: panelShape,
      fill: Dial.Palette.subtle,
      strokeOpacity: 0.24)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Room")
    .accessibilityValue("\(snapshot.moodLabel). \(snapshot.reason)")
  }

  private var artifactShelf: some View {
    HStack(alignment: .center, spacing: 7) {
      VStack(alignment: .leading, spacing: 2) {
        Text("ARTIFACTS")
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.textMuted)
        Text(artifacts.isEmpty ? "EMPTY" : "\(artifacts.count) KEPT")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.accent)
          .monospacedDigit()
      }
      .frame(width: 72, alignment: .leading)

      if artifacts.isEmpty {
        Text("Earn badges to leave objects in the room.")
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(Dial.Palette.textMuted.opacity(0.76))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      } else {
        HStack(spacing: 4) {
          ForEach(Array(artifacts.prefix(6))) { artifact in
            ArtifactSprite(kind: artifact.kind, color: artifactColor(artifact), size: 20)
              .frame(width: 28, height: 28)
              .dialPrintedChip(
                shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
                color: artifactColor(artifact),
                fillOpacity: 0.045,
                edgeOpacity: 0.18)
              .help(artifact.detail ?? artifact.kind.label)
          }
          Spacer(minLength: 0)
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: 36)
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      color: theme.accent,
      fillOpacity: 0.035,
      edgeOpacity: 0.12)
  }

  private func roomAction(_ snapshot: PetBondSnapshot) -> some View {
    Button {
      runPrimaryAction(snapshot)
    } label: {
      HStack(spacing: 7) {
        DialThickIcon(iconName(for: snapshot.primaryAction), size: 12, weight: 0.55)
        Text(snapshot.primaryAction.label)
          .font(Dial.Typography.monoLabel)
          .tracking(1.0)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundStyle(Dial.Palette.textPrimary)
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .frame(width: 106, height: 24, alignment: .leading)
      .background(Dial.Palette.surface.opacity(0.82))
      .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)
          .stroke(Dial.Palette.hairline.opacity(0.88), lineWidth: 1)
      )
    }
    .buttonStyle(.pressable)
  }

  private func roomBondGauge(_ snapshot: PetBondSnapshot) -> some View {
    HStack(spacing: 7) {
      Text("BOND")
        .font(Dial.Typography.monoTiny)
        .tracking(0.8)
        .foregroundStyle(Dial.Palette.textMuted)

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(Dial.Palette.surface.opacity(0.92))
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(theme.accent)
            .frame(width: max(4, proxy.size.width * CGFloat(min(1, max(0, snapshot.bondScore)))))
        }
      }
      .frame(height: 5)

      Text(percent(snapshot.bondScore))
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(Dial.Palette.textPrimary.opacity(0.82))
        .monospacedDigit()
        .frame(width: 32, alignment: .trailing)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Bond \(percent(snapshot.bondScore))")
  }

  // MARK: - XP

  private var xpSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        // Body-content label, mixed-case sansCaption (was mono-caps).
        Text("EVOLUTION")
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(Dial.Palette.textMuted)
        Spacer()
        Text(evolutionStatus)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.accent)
          .monospacedDigit()
          .contentTransition(.numericText())
      }
      progressBar
      stageRail
      Text(xpDetailText)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(Dial.Palette.textMuted.opacity(0.76))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Evolution progress")
    .accessibilityValue(accessibilityXPValue)
    .frame(maxWidth: .infinity, alignment: .leading)
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      color: theme.accent,
      fillOpacity: 0.035,
      edgeOpacity: 0.12)
  }

  private var progressBar: some View {
    GeometryReader { proxy in
      let fillWidth = visibleXPFillWidth(in: proxy.size.width)
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: Dial.Radius.tiny)
          .fill(Dial.Palette.surface.opacity(0.9))
          .overlay(
            RoundedRectangle(cornerRadius: Dial.Radius.tiny)
              .stroke(Dial.Palette.hairline.opacity(0.95), lineWidth: 1)
          )
          .frame(height: xpBarHeight)

        RoundedRectangle(cornerRadius: Dial.Radius.tiny)
          .fill(theme.accent)
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
          .foregroundStyle(theme.accent.opacity(0.9))
      } else {
        Text("MAX")
          .font(Dial.Typography.monoTiny)
          .tracking(0.8)
          .foregroundStyle(theme.accent.opacity(0.9))
      }
      Spacer(minLength: 8)
    }
  }

  // MARK: - Reload

  private func reload() {
    let queries = StatsQueries(dbq: dbq)
    petState = (try? PetStateDAO(dbq: dbq).get()) ?? nil
    todayListeningMs = (try? queries.totals(since: startOfTodayEpoch()).listeningMs) ?? 0
    let recentCutoff = Int64(Date().timeIntervalSince1970) - 7 * 86_400
    let summaries = (try? queries.badgeSummaries(since: recentCutoff)) ?? []
    recentBadgeCounts = summaries.reduce(into: [:]) { acc, summary in
      acc[summary.category] = summary.count
    }
    unlockedTricks = (try? PetTrickUnlocksDAO(dbq: dbq).all()) ?? []
    artifacts = (try? ArtifactsDAO(dbq: dbq).syncFromMemoriesAndTricks()) ?? []
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

  private func artifactColor(_ artifact: Artifact) -> Color {
    switch artifact.source {
    case .badge:
      switch artifact.kind {
      case .firstListenSpark, .newArtistToken, .streakFlame:
        return theme.accentAlt
      case .play10Trophy, .play50Trophy, .play100Trophy, .anniversaryRelic:
        return Dial.Palette.textPrimary
      default:
        return theme.accent
      }
    case .trick:
      return theme.accentAlt
    }
  }

  private func iconName(for action: PetBondPrimaryAction) -> String {
    switch action {
    case .reactToBadge: return "sparkles"
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
    case .reactToBadge:
      reaction = (
        aggCache.currentBadgeInsight.map { "Reacting to \($0.kind.label)." } ?? "Reacting.",
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
    if reduceMotion {
      actionPulse = true
    } else {
      withAnimation(.easeOut(duration: 0.16)) { actionPulse = true }
    }

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
