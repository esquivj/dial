// Dial/Views/Dropdown/PetView.swift
import SwiftUI
import GRDB

enum PetViewPlacement {
  case legacyPanel
  case hardwareShell
}

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
  let livingMemoriesEnabled: Bool
  let onBack: () -> Void
  var placement: PetViewPlacement = .legacyPanel

  @State private var todayListeningMs: Int64 = 0
  @State private var recentBadgeCounts: [BadgeCategory: Int] = [:]
  @State private var unlockedTricks: [PetTrickUnlock] = []
  @State private var artifacts: [Artifact] = []
  @State private var weeklyMemory: StatsQueries.WeeklyMemorySnapshot?
  @State private var weeklyMemoryLog: [WeeklyMemoryRecord] = []
  @State private var petState: PetState? = nil
  @State private var actionFeedback: String?
  @State private var interactionBehavior: PetBehavior?
  @State private var actionPulse = false
  @State private var feedbackTask: Task<Void, Never>?
  @State private var reloadLoader = CoalescedSnapshotLoader<PetViewSnapshot>("pet.snapshot.load")
  @Environment(\.dialTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    pet: PetViewModel,
    aggCache: AggregationsCache,
    menubar: MenubarStripViewModel,
    dbq: DatabaseQueue,
    livingMemoriesEnabled: Bool,
    initialTodayListeningMs: Int64 = 0,
    initialBadgeCounts: [BadgeCategory: Int] = [:],
    initialUnlockedTricks: [PetTrickUnlock] = [],
    initialArtifacts: [Artifact] = [],
    initialWeeklyMemory: StatsQueries.WeeklyMemorySnapshot? = nil,
    initialWeeklyMemoryLog: [WeeklyMemoryRecord] = [],
    initialPetState: PetState? = nil,
    placement: PetViewPlacement = .legacyPanel,
    onBack: @escaping () -> Void
  ) {
    self.pet = pet
    self.aggCache = aggCache
    self.menubar = menubar
    self.dbq = dbq
    self.livingMemoriesEnabled = livingMemoriesEnabled
    self.onBack = onBack
    self.placement = placement
    _todayListeningMs = State(initialValue: initialTodayListeningMs)
    _recentBadgeCounts = State(initialValue: initialBadgeCounts)
    _unlockedTricks = State(initialValue: initialUnlockedTricks)
    _artifacts = State(initialValue: initialArtifacts)
    _weeklyMemory = State(initialValue: initialWeeklyMemory)
    _weeklyMemoryLog = State(initialValue: initialWeeklyMemoryLog)
    _petState = State(initialValue: initialPetState)
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .task(id: ObjectIdentifier(dbq)) {
      reload()
    }
    .onChange(of: livingMemoriesEnabled) { _, _ in reload() }
    .onChange(of: pet.xp) { _, _ in reload() }
    .onChange(of: pet.streakDays) { _, _ in reload() }
    .onDisappear {
      feedbackTask?.cancel()
      reloadLoader.cancel()
      feedbackTask = nil
    }
  }

  // MARK: - Header

  private var legacyPanelBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Rectangle().fill(theme.hairline.opacity(0.92)).frame(height: 1)
      content
    }
  }

  private var hardwareShellBody: some View {
    VStack(spacing: 0) {
      railHeader
        .frame(width: Dial.Layout.StatusRail.contentWidth, height: Dial.Layout.StatusRail.railHeight)
        .offset(y: Dial.Layout.Dropdown.hudRailContentYOffset)
        .frame(maxWidth: .infinity)
        .frame(height: Dial.Layout.Dropdown.hudTopChromeHeight)

      petPlate
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
      Text("ROOM")
        .font(Dial.Typography.monoLabel)
        .tracking(1.6)
        .foregroundStyle(theme.accent)
      Spacer()
      Text(pet.stage.rawValue.uppercased())
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.textMuted.opacity(0.74))
        .contentTransition(.opacity)
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
        Text("ROOM")
          .font(Dial.Typography.monoLabel)
          .tracking(1.6)
          .foregroundStyle(theme.accent)
      }
      .offset(x: Dial.Layout.SecondaryShell.railLeadingOffset)

      Spacer(minLength: 8)

      Text(pet.stage.rawValue.uppercased())
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(theme.textMuted.opacity(0.74))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .contentTransition(.opacity)
        .offset(x: Dial.Layout.SecondaryShell.railTrailingOffset)
    }
    .padding(.horizontal, 2)
  }

  private var petPlate: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .modifier(RecessedScreen(depth: 0.42, height: 18))
      .lcdPanel(
        fill: theme.ground.opacity(Dial.Layout.SecondaryShell.plateFillOpacity),
        strokeOpacity: Dial.Layout.SecondaryShell.plateStrokeOpacity)
  }

  // MARK: - Content

  private var content: some View {
    VStack(alignment: .leading, spacing: Dial.Layout.PetScreen.contentSpacing) {
      petCompanionPanel
      if livingMemoriesEnabled {
        weeklyMemoryCapsule
      }
      memoryShelf
      xpSection
    }
    .padding(Dial.Layout.PetScreen.contentPadding)
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
        featuredObjectName: livingMemoriesEnabled ? weeklyMemory?.roomObjectName : nil,
        notesActive: menubar.state == .playing || actionPulse,
        actionPulse: actionPulse)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 8) {
          petStateSummary(snapshot)
          Spacer(minLength: 8)
          roomAction(snapshot)
        }

        roomBondGauge(snapshot)
      }
    }
    .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
    .frame(maxWidth: .infinity)
    .frame(height: Dial.Layout.PetScreen.companionPanelHeight)
    .dialRecessedPanel(
      shape: panelShape,
      fill: theme.subtle,
      strokeOpacity: 0.24)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Room")
    .accessibilityValue("\(snapshot.moodLabel). \(snapshot.reason)")
  }

  private var weeklyMemoryCapsule: some View {
    let shape = RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)

    return Group {
      if let memory = weeklyMemory {
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              Text("THIS WEEK")
                .font(Dial.Typography.monoTiny)
                .tracking(0.8)
                .foregroundStyle(theme.textMuted.opacity(0.70))

              Text(memory.trait.uppercased())
                .font(Dial.Typography.monoTiny)
                .tracking(0.8)
                .foregroundStyle(weeklyMemoryColor(memory))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }

            Text(memory.memento.uppercased())
              .font(Dial.Typography.monoLabel)
              .tracking(1.0)
              .foregroundStyle(theme.textPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.80)

            Text(memory.recapLine)
              .font(Dial.Typography.monoTiny)
              .foregroundStyle(theme.textMuted.opacity(0.78))
              .lineLimit(1)
              .minimumScaleFactor(0.66)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .trailing, spacing: 3) {
            Text((memory.dominantGenre ?? memory.theme.label).uppercased())
              .font(Dial.Typography.monoTiny)
              .tracking(0.8)
              .foregroundStyle(weeklyMemoryColor(memory).opacity(0.92))
              .lineLimit(1)
              .minimumScaleFactor(0.62)

            Text(roomObjectLabel(memory.roomObjectName))
              .font(Dial.Typography.monoTiny)
              .tracking(0.8)
              .foregroundStyle(theme.textPrimary.opacity(0.82))
              .lineLimit(2)
              .multilineTextAlignment(.trailing)
              .minimumScaleFactor(0.68)
          }
          .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Dial.Layout.PetScreen.weeklyMemoryHeight)
        .dialPrintedChip(
          shape: shape,
          color: weeklyMemoryColor(memory),
          fillOpacity: 0.045,
          edgeOpacity: 0.16)
        .help(weeklyMemoryHelp(memory))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week")
        .accessibilityValue("\(memory.trait). \(memory.memento). \(memory.recapLine)")
      } else {
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text("THIS WEEK")
              .font(Dial.Typography.monoTiny)
              .tracking(0.8)
              .foregroundStyle(theme.textMuted.opacity(0.70))

            Text("NO ROOM MEMORY YET")
              .font(Dial.Typography.monoLabel)
              .tracking(1.0)
              .foregroundStyle(theme.textPrimary.opacity(0.78))

            Text("Listening writes a trait, memento, and object.")
              .font(Dial.Typography.monoTiny)
              .foregroundStyle(theme.textMuted.opacity(0.74))
              .lineLimit(1)
              .minimumScaleFactor(0.70)
          }

          Spacer(minLength: 0)

          Text("WAITING")
            .font(Dial.Typography.monoTiny)
            .tracking(0.8)
            .foregroundStyle(theme.textMuted.opacity(0.70))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Dial.Layout.PetScreen.weeklyMemoryHeight)
        .dialPrintedChip(
          shape: shape,
          color: theme.accent,
          fillOpacity: 0.028,
          edgeOpacity: 0.10)
        .help("The weekly room memory appears after Dial sees at least one play this week.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week")
        .accessibilityValue("No room memory yet.")
      }
    }
  }

  private func petStateSummary(_ snapshot: PetBondSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if let badge = aggCache.currentBadgeInsight {
          BadgePixelIcon(
            kind: badge.kind,
            color: badge.kind.category == .pattern ? theme.memoryAccent : theme.accent,
            size: 11)
        }
        Text(snapshot.moodLabel)
          .font(Dial.Typography.sansCaption)
          .foregroundStyle(theme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.86)
      }

      Text(actionFeedback ?? snapshot.reason)
        .font(Dial.Typography.monoSmall)
        .foregroundStyle(actionFeedback == nil ? theme.textMuted.opacity(0.76) : theme.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .contentTransition(.opacity)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var memoryShelf: some View {
    let visibleArtifacts = Array(artifacts.prefix(4))
    let latestMemory = weeklyMemoryLog.first.map { "\(weekLabel($0.weekStart)) · \($0.trait.uppercased())" }
    let latestArtifact = artifacts.first.map { "LATEST \($0.kind.label.uppercased())" }
    let latestLabel = livingMemoriesEnabled
      ? (latestMemory ?? latestArtifact ?? "BADGES + TRICKS")
      : (latestArtifact ?? "BADGES + TRICKS")
    let countLabel = livingMemoriesEnabled
      ? "\(weeklyMemoryLog.count)W · \(artifacts.count) OBJ"
      : "\(artifacts.count) OBJ"

    return HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text("MEMORIES")
            .font(Dial.Typography.monoTiny)
            .tracking(0.8)
            .foregroundStyle(theme.textMuted.opacity(0.72))
          Text(countLabel)
            .font(Dial.Typography.monoTiny)
            .foregroundStyle(theme.accent)
            .monospacedDigit()
        }

        Text(latestLabel)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(artifacts.isEmpty ? theme.textMuted.opacity(0.72) : theme.textPrimary.opacity(0.86))
          .lineLimit(1)
          .minimumScaleFactor(0.74)
      }
      .frame(width: 154, alignment: .leading)

      Spacer(minLength: 0)

      HStack(spacing: 5) {
        if visibleArtifacts.isEmpty {
          ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)
              .stroke(theme.hairline.opacity(0.42), lineWidth: 1)
              .frame(width: 28, height: 28)
          }
        } else {
          ForEach(visibleArtifacts) { artifact in
            ArtifactSprite(kind: artifact.kind, color: artifactColor(artifact), size: 21)
              .frame(width: 28, height: 28)
              .dialPrintedChip(
                shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
                color: artifactColor(artifact),
                fillOpacity: 0.06,
                edgeOpacity: 0.18)
              .help(artifact.detail ?? artifact.kind.label)
          }
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: Dial.Layout.PetScreen.memoryShelfHeight)
    .dialPrintedChip(
      shape: RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous),
      color: theme.accent,
      fillOpacity: 0.035,
      edgeOpacity: 0.12)
    .help("Weekly mementos and permanent objects. Hover an object for its source.")
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Memories")
    .accessibilityValue(memoryShelfAccessibilityValue(latestLabel: latestLabel))
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
      .foregroundStyle(theme.textPrimary)
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .frame(width: 106, height: 24, alignment: .leading)
      .background(theme.surface.opacity(0.82))
      .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)
          .stroke(theme.hairline.opacity(0.78), lineWidth: 1)
      )
      .dialHitSlop(horizontal: 5, vertical: 10)
    }
    .buttonStyle(.pressable)
    .accessibilityLabel(snapshot.primaryAction.label)
  }

  private func roomBondGauge(_ snapshot: PetBondSnapshot) -> some View {
    HStack(spacing: 7) {
      Text("BOND")
        .font(Dial.Typography.monoTiny)
        .tracking(0.8)
        .foregroundStyle(theme.textMuted.opacity(0.70))

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(theme.surface.opacity(0.88))
          RoundedRectangle(cornerRadius: Dial.Radius.pixel)
            .fill(theme.accent)
            .frame(width: max(4, proxy.size.width * CGFloat(min(1, max(0, snapshot.bondScore)))))
        }
      }
      .frame(height: 5)

      Text(percent(snapshot.bondScore))
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(theme.textPrimary.opacity(0.82))
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
          .foregroundStyle(theme.textMuted.opacity(0.70))
        Spacer()
        Text(evolutionStatus)
          .font(Dial.Typography.monoSmall)
          .foregroundStyle(theme.accent)
          .monospacedDigit()
          .contentTransition(.numericText())
      }
      progressBar
      stageRail
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .help(xpDetailText)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Evolution progress")
    .accessibilityValue(accessibilityXPValue)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: Dial.Layout.PetScreen.evolutionHeight)
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
          .fill(theme.surface.opacity(0.88))
          .overlay(
            RoundedRectangle(cornerRadius: Dial.Radius.tiny)
              .stroke(theme.hairline.opacity(0.84), lineWidth: 1)
          )
          .frame(height: xpBarHeight)

        RoundedRectangle(cornerRadius: Dial.Radius.tiny)
          .fill(theme.accent)
          .frame(width: fillWidth, height: xpBarHeight)

        if fillWidth > 0 {
          Circle()
            .fill(theme.textPrimary.opacity(0.9))
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
        .foregroundStyle(theme.textPrimary.opacity(0.82))
      Text("->")
        .font(Dial.Typography.monoTiny)
        .foregroundStyle(theme.textMuted.opacity(0.58))
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
    let startOfToday = startOfTodayEpoch()
    let shouldLoadLivingMemories = livingMemoriesEnabled
    reloadLoader.schedule {
      await PetViewSnapshot.load(
        dbq: dbq,
        startOfToday: startOfToday,
        livingMemoriesEnabled: shouldLoadLivingMemories)
    } apply: { snapshot in
      apply(snapshot)
    }
  }

  private func apply(_ snapshot: PetViewSnapshot) {
    petState = snapshot.petState
    todayListeningMs = snapshot.todayListeningMs
    recentBadgeCounts = snapshot.recentBadgeCounts
    unlockedTricks = snapshot.unlockedTricks
    artifacts = snapshot.artifacts
    weeklyMemory = snapshot.weeklyMemory
    weeklyMemoryLog = snapshot.weeklyMemoryLog
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
        return theme.memoryAccent
      case .play10Trophy, .play50Trophy, .play100Trophy, .anniversaryRelic:
        return theme.textPrimary
      default:
        return theme.accent
      }
    case .trick:
      return theme.memoryAccent
    case .weeklyMemory:
      return artifact.sourceWeekStart.flatMap { weekStart in
        weeklyMemoryLog.first(where: { $0.weekStart == weekStart }).map(weeklyMemoryColor)
      } ?? theme.memoryAccent
    }
  }

  private func weeklyMemoryColor(_ memory: StatsQueries.WeeklyMemorySnapshot) -> Color {
    if memory.theme == theme.id { return theme.accent }
    return DialTheme.palette(for: memory.theme).accent
  }

  private func weeklyMemoryColor(_ memory: WeeklyMemoryRecord) -> Color {
    if memory.theme == theme.id { return theme.accent }
    return DialTheme.palette(for: memory.theme).accent
  }

  private func roomObjectLabel(_ name: String) -> String {
    name
      .replacingOccurrences(of: "_", with: " ")
      .uppercased()
  }

  private func weeklyMemoryHelp(_ memory: StatsQueries.WeeklyMemorySnapshot) -> String {
    let genre = memory.dominantGenre ?? memory.theme.label
    return "\(memory.trait): \(memory.recapLine) Memento: \(memory.memento). Room object: \(roomObjectLabel(memory.roomObjectName)). Dominant sound: \(genre)."
  }

  private func weeklyMemoryHelp(_ memory: WeeklyMemoryRecord) -> String {
    let genre = memory.dominantGenre ?? memory.theme.label
    return "\(weekLabel(memory.weekStart)): \(memory.trait). \(memory.recapLine) Memento: \(memory.memento). Room object: \(roomObjectLabel(memory.roomObjectName)). Dominant sound: \(genre)."
  }

  private func memoryShelfAccessibilityValue(latestLabel: String) -> String {
    if livingMemoriesEnabled {
      return "\(weeklyMemoryLog.count) saved weeks. \(artifacts.count) objects. \(latestLabel)."
    }
    return artifacts.isEmpty ? "None yet. Badges and tricks unlock objects." : "\(artifacts.count) objects. \(latestLabel)."
  }

  private func weekLabel(_ weekStart: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(weekStart))
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date).uppercased()
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
      reaction = ("Quiet until the next track.", .idle)
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
    withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.62)) {
      actionPulse = true
    }

    feedbackTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 180_000_000)
      withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78)) {
        actionPulse = false
      }
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
