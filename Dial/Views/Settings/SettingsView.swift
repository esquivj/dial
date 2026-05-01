import SwiftUI
import AppKit

/// Hosted by the SwiftUI `Settings` scene in `DialApp`.
/// Settings should feel like a control panel: fast, stable, and low-drama.
struct SettingsView: View {
  @Bindable var vm: SettingsViewModel
  let coord: AppCoordinator
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  @State private var selectedTab: SettingsTab = .general
  @State private var showSoundSourceControls = false
  @State private var showAdvancedMenuBarControls = false
  @State private var showAdvancedHUDControls = false
  @State private var showAdvancedPetControls = false

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(selection: $selectedTab)

      Rectangle()
        .fill(SettingsPalette.rule)
        .frame(width: 1)

      ScrollViewReader { proxy in
        ScrollView {
          Color.clear
            .frame(height: 0)
            .id(SettingsLayout.scrollTopID)

          LazyVStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
            currentTab
          }
          .padding(EdgeInsets(
            top: SettingsLayout.contentTop,
            leading: SettingsLayout.sidePadding,
            bottom: SettingsLayout.contentBottom,
            trailing: SettingsLayout.sidePadding))
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transaction { $0.animation = nil }
        .scrollIndicators(.visible)
        .onChange(of: selectedTab) { _, _ in
          proxy.scrollTo(SettingsLayout.scrollTopID, anchor: .top)
        }
      }
    }
    .foregroundStyle(SettingsPalette.text)
    .tint(SettingsPalette.accent)
    .background(SettingsPalette.canvas)
    .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
  }

  @ViewBuilder
  private var currentTab: some View {
    switch selectedTab {
    case .general:
      GeneralSettingsTab(
        vm: vm,
        coord: coord,
        showSoundSourceControls: $showSoundSourceControls,
        onSignIn: onSignIn,
        onImport: onImport)
    case .menuBar:
      MenuBarSettingsTab(
        vm: vm,
        showAdvancedControls: $showAdvancedMenuBarControls)
    case .hud:
      HUDSettingsTab(
        vm: vm,
        showAdvancedControls: $showAdvancedHUDControls)
    case .pet:
      PetSettingsTab(
        vm: vm,
        showAdvancedControls: $showAdvancedPetControls)
    }
  }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
  @Bindable var vm: SettingsViewModel
  let coord: AppCoordinator
  @Binding var showSoundSourceControls: Bool
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  @State private var showDisconnectAlert = false
  @State private var isRunningTagPass = false
  @State private var tagRunMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("SPOTIFY") {
        VStack(alignment: .leading, spacing: SettingsLayout.rowGap) {
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text(vm.signedIn ? "Spotify connected" : "Spotify offline")
                .font(SettingsType.rowTitle)
                .foregroundStyle(SettingsPalette.text)
              Text(vm.signedIn
                   ? "Playback, likes, and history are on."
                   : "Playback and likes are off.")
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            if vm.signedIn {
              Button("Disconnect") { showDisconnectAlert = true }
                .buttonStyle(SettingsButtonStyle())
                .help("Stop live Spotify updates. Imported history stays local.")
                .alert("Disconnect from Spotify?", isPresented: $showDisconnectAlert) {
                  Button("Cancel", role: .cancel) {}
                  Button("Disconnect", role: .destructive) {
                    coord.stopBackgroundEnrichment()
                    vm.markSignedOut()
                  }
                } message: {
                  Text("Dial will stop updating playback and likes until you reconnect. Your imported history stays local.")
                }
            } else {
              Button("Connect") { Task { await onSignIn() } }
                .buttonStyle(SettingsButtonStyle(prominent: true))
                .help("Connect Spotify so Dial can read playback and liked tracks.")
            }
          }
          .help(vm.signedIn
                ? "Dial is reading playback, liked songs, and imported listening history."
                : "Connect Spotify so Dial can turn playback and history into badges, themes, and pet moments.")

          if vm.importProgress > 0, vm.importProgress < 1 {
            ProgressView(value: vm.importProgress)
              .tint(SettingsPalette.accent)
              .controlSize(.small)
          }

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Listening history")
                .font(SettingsType.rowTitle)
              Text(historyImportSubtitle)
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            Button("Import Folder") {
              let panel = NSOpenPanel()
              panel.canChooseDirectories = true
              panel.canChooseFiles = false
              if panel.runModal() == .OK, let url = panel.url { onImport(url) }
            }
            .buttonStyle(SettingsButtonStyle())
            .help("Select the folder from Spotify's Extended Streaming History export.")
          }
          .help("Dial uses this history for play counts, first-listen badges, rediscoveries, and recaps.")
        }
      }

      SettingsSection("ANALYSIS") {
        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Auto-analyze library",
            detail: "Keeps artwork, artists, tags, and theme hints up to date while Dial is open.",
            isOn: Binding(
              get: { vm.backgroundEnrichmentEnabled },
              set: { value in
                vm.backgroundEnrichmentEnabled = value
                coord.syncBackgroundEnrichment()
              }))

          DisclosureGroup(isExpanded: $showSoundSourceControls) {
            VStack(spacing: SettingsLayout.controlGap) {
              SettingsToggle(
                title: "Use Last.fm tags",
                detail: "Adds genre-style tags that help Dial choose themes and weekly traits.",
                isOn: Binding(
                  get: { vm.lastFMTagEnrichmentEnabled },
                  set: { value in
                    vm.lastFMTagEnrichmentEnabled = value
                    coord.restartBackgroundEnrichmentNow()
                  }))

              HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                  Text("Last.fm API key")
                    .font(SettingsType.rowTitle)
                  SettingsHelpMark("Needed only if Last.fm tags are on. Dial stores this key locally.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                Spacer()
                TextField("API key", text: $vm.lastFMAPIKey)
                  .textFieldStyle(.plain)
                  .font(SettingsType.mono)
                  .foregroundStyle(SettingsPalette.text)
                  .padding(.horizontal, 9)
                  .frame(width: SettingsLayout.textFieldWidth, height: 28)
                  .background(SettingsPalette.control)
                  .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                      .stroke(SettingsPalette.rule, lineWidth: 1))
                  .help("Paste your Last.fm API key. Dial stores it locally and uses it only for tags.")
              }
              .frame(minHeight: 32)
              .help("Needed only if Last.fm tags are on. Dial stores this key locally.")

              SettingsActionRow {
                Button("Analyze Now") {
                  vm.backgroundEnrichmentEnabled = true
                  coord.restartBackgroundEnrichmentNow()
                }
                .buttonStyle(SettingsButtonStyle(prominent: true))
                .disabled(!vm.signedIn)
                .help("Restart the background artwork, artist, and tag queue.")

                Button(isRunningTagPass ? "Tagging..." : "Finish Tags") {
                  finishTagsNow()
                }
                .buttonStyle(SettingsButtonStyle())
                .disabled(!canRunTagPass)
                .help("Run a one-shot Last.fm pass for the remaining artist tag queue.")
              }

              if let tagRunMessage {
                Text(tagRunMessage)
                  .font(SettingsType.caption)
                  .foregroundStyle(SettingsPalette.muted)
                  .frame(maxWidth: .infinity, alignment: .trailing)
              }
            }
            .padding(.top, 10)
          } label: {
            SettingsDisclosureLabel(
              title: "Tag sources",
              detail: "Last.fm is Dial's main sound signal. Spotify artist data is a fallback when present.")
          }
          .tint(SettingsPalette.accent)
        }
      }

      SettingsStatusPanel(coord: coord)

      SettingsSection("ABOUT") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Dial 0.1")
            .font(SettingsType.rowTitle)
          Text("Now playing, remembered.")
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.muted)
        }
      }
    }
  }

  private var historyImportSubtitle: String {
    if let last = vm.lastImport {
      return "Last import: \(last.rowsInserted.formatted(.number)) plays"
    }
    return "No history folder imported."
  }

  private var canRunTagPass: Bool {
    vm.signedIn
      && vm.lastFMTagEnrichmentEnabled
      && !vm.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isRunningTagPass
  }

  private func finishTagsNow() {
    guard canRunTagPass else { return }
    isRunningTagPass = true
    tagRunMessage = "Last.fm queue running..."

    Task {
      do {
        try await coord.runTagEnrichment(limit: 1_000)
        await MainActor.run {
          tagRunMessage = "Last.fm queue checked."
          isRunningTagPass = false
        }
      } catch {
        await MainActor.run {
          tagRunMessage = "Last.fm queue paused."
          isRunningTagPass = false
        }
      }
    }
  }
}

private struct MenuBarSettingsTab: View {
  @Bindable var vm: SettingsViewModel
  @Binding var showAdvancedControls: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("PREVIEW") {
        MenuBarSettingsPreview(
          mode: vm.menuBarDisplayMode,
          showAlbumArt: vm.showAlbumArtInMenuBar,
          maxWidth: vm.menuBarTitleWidth,
          showProgress: vm.showProgressInMenuBar)
      }

      SettingsSection("DISPLAY") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsPickerRow(
            title: "Display mode",
            detail: "Choose what Dial shows in the macOS menu bar.",
            selection: $vm.menuBarDisplayMode,
            values: MenuBarDisplayMode.allCases)

          SettingsToggle(
            title: "Show album art",
            detail: "Show the current cover in menu bar modes that include artwork.",
            isOn: $vm.showAlbumArtInMenuBar)

          SettingsToggle(
            title: "Live Dock artwork",
            detail: "Replace Dial's Dock icon with the current album cover.",
            isOn: $vm.showDockArtwork)
        }
      }

      SettingsSection("ADVANCED") {
        DisclosureGroup(isExpanded: $showAdvancedControls) {
          VStack(spacing: SettingsLayout.controlGap) {
            SettingsToggle(
              title: "Show progress line",
              detail: "Show a tiny playback progress line under the menu bar item.",
              isOn: $vm.showProgressInMenuBar)

            SettingsToggle(
              title: "Flash on new track",
              detail: "Pulse the menu bar item when the track changes.",
              isOn: $vm.flashOnTrackChange)

            SettingsSliderRow(
              title: "Max text width",
              detail: "Limit long menu bar titles so they do not crowd other items.",
              value: $vm.menuBarTitleWidth,
              range: MenuBarTextMetrics.minimumSettingWidth...MenuBarTextMetrics.maximumSettingWidth,
              step: 10,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsActionRow {
              Button("Reset Menu Bar") { vm.resetMenuBarDefaults() }
                .buttonStyle(SettingsButtonStyle())
            }
          }
          .padding(.top, 12)
        } label: {
            SettingsDisclosureLabel(
              title: "Menu bar tuning",
              detail: "Progress line, track-change pulse, and title width.")
        }
        .tint(SettingsPalette.accent)
      }
    }
  }
}

private struct HUDSettingsTab: View {
  @Bindable var vm: SettingsViewModel
  @Binding var showAdvancedControls: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("PREVIEW") {
        HUDSettingsPreview(vm: vm)
      }

      SettingsSection("PRESETS") {
        SettingsPresetGrid { preset in
          vm.applyHUDPreset(preset)
        }
      }

      SettingsSection("APPEARANCE") {
        ColorModeSelector(selection: $vm.hudColorMode)
      }

      SettingsSection("OPENING") {
        SettingsPickerRow(
          title: "Open to",
          detail: "Choose the screen that opens when you click Dial in the menu bar.",
          selection: $vm.defaultDropdownScreen,
          values: DefaultDropdownScreen.allCases)
      }

      SettingsSection("CONTENT") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Show readouts",
            detail: "Show plays, weekly rank, and last played on Now Playing.",
            isOn: $vm.showReadoutsInHUD)

          SettingsToggle(
            title: "Show badges",
            detail: "Show why the current track matters in your history.",
            isOn: $vm.showBadgesInHUD)

          SettingsToggle(
            title: "Show spectrum",
            detail: "Show the live audio meter on Now Playing.",
            isOn: $vm.showVisualizerInHUD)

          SettingsToggle(
            title: "Show transport",
            detail: "Show playback controls below Now Playing.",
            isOn: $vm.showTransportInHUD)
        }
      }

      SettingsSection("ADVANCED") {
        DisclosureGroup(isExpanded: $showAdvancedControls) {
          VStack(spacing: SettingsLayout.controlGap) {
            SettingsPickerRow(
              title: "Animation level",
              detail: "Set how much motion Dial uses when the HUD opens.",
              selection: $vm.animationLevel,
              values: DialAnimationLevel.allCases)

            SettingsPickerRow(
              title: "Spectrum style",
              detail: "Choose a steadier meter or a more reactive one.",
              selection: $vm.spectrumStyle,
              values: SpectrumStyle.allCases)

            SettingsPickerRow(
              title: "Spectrum density",
              detail: "Choose how many bars the audio meter shows.",
              selection: $vm.spectrumDensity,
              values: SpectrumDensity.allCases)

            SettingsPickerRow(
              title: "Spectrum motion",
              detail: "Set how quickly the audio bars rise and fall.",
              selection: $vm.spectrumMotion,
              values: SpectrumMotion.allCases)

            SettingsToggle(
              title: "Peak markers",
              detail: "Highlight recent loud peaks at the top of each bar.",
              isOn: $vm.spectrumPeakMarkers)

            SettingsToggle(
              title: "Discovery badges",
              detail: "Show first listens, new artists, rediscoveries, and deep cuts.",
              isOn: $vm.discoveryBadgesEnabled)

            SettingsToggle(
              title: "Pattern badges",
              detail: "Show streaks, repeat runs, and album-mode listening.",
              isOn: $vm.patternBadgesEnabled)

            SettingsToggle(
              title: "Milestone badges",
              detail: "Show 10th, 50th, 100th plays, and anniversaries.",
              isOn: $vm.milestoneBadgesEnabled)

            SettingsSliderRow(
              title: "Track title size",
              detail: "Change the size of the track title on Now Playing.",
              value: $vm.hudHeroTitleSize,
              range: 13...18,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Artist size",
              detail: "Change the size of the artist line.",
              value: $vm.hudHeroArtistSize,
              range: 10...15,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Album size",
              detail: "Change the size of the album line.",
              value: $vm.hudHeroAlbumSize,
              range: 9...14,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Title gap",
              detail: "Set the space below the track title.",
              value: $vm.hudHeroMetadataGap,
              range: 0...8,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Badge gap",
              detail: "Set the space above the track badge.",
              value: $vm.hudHeroBadgeGap,
              range: 2...10,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Badge scale",
              detail: "Resize the badge that explains the current track.",
              value: $vm.hudBadgeScale,
              range: 0.85...1.25,
              step: 0.05,
              valueText: { String(format: "%.2fx", $0) })

            SettingsActionRow {
              Button("Reset HUD") { vm.resetHUDDefaults() }
                .buttonStyle(SettingsButtonStyle())
              Button("Reset All") { vm.resetAllSettings() }
                .buttonStyle(SettingsButtonStyle())
            }
          }
          .padding(.top, 12)
        } label: {
            SettingsDisclosureLabel(
              title: "HUD tuning",
              detail: "Audio meter, badges, motion, and Now Playing spacing.")
        }
        .tint(SettingsPalette.accent)
      }
    }
  }
}

private struct PetSettingsTab: View {
  @Bindable var vm: SettingsViewModel
  @Binding var showAdvancedControls: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("PREVIEW") {
        PetSettingsPreview(enabled: vm.petEnabled, showInHUD: vm.showPetInHUD)
      }

      SettingsSection("COMPANION") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Enable pet",
            detail: "Let the pixel companion react to your listening.",
            isOn: $vm.petEnabled)

          SettingsToggle(
            title: "Show pet in HUD",
            detail: "Show the pet beside the current track on Now Playing.",
            isOn: $vm.showPetInHUD)
            .disabled(!vm.petEnabled)
            .opacity(vm.petEnabled ? 1 : 0.35)

          SettingsToggle(
            title: "Living memories",
            detail: "Save weekly traits, mementos, and room objects from your history.",
            isOn: $vm.livingMemoriesEnabled)
            .disabled(!vm.petEnabled)
            .opacity(vm.petEnabled ? 1 : 0.35)
        }
      }

      SettingsSection("ADVANCED") {
        DisclosureGroup(isExpanded: $showAdvancedControls) {
          VStack(spacing: SettingsLayout.controlGap) {
            VStack(spacing: SettingsLayout.controlGap) {
              SettingsToggle(
                title: "Feeding animation",
                detail: "Play a small feeding reaction when a listen counts.",
                isOn: $vm.petFeedingAnimation)
              SettingsToggle(
                title: "First-listen animation",
                detail: "Play a reaction when Dial sees a track for the first time.",
                isOn: $vm.petFirstListenAnimation)
              SettingsToggle(
                title: "Rediscovery animation",
                detail: "Play a reaction when an old track comes back.",
                isOn: $vm.petRediscoveryAnimation)
              SettingsToggle(
                title: "Level-up animation",
                detail: "Play a bigger reaction when the pet changes stage.",
                isOn: $vm.petLevelUpAnimation)
            }
            .disabled(!vm.petEnabled)
            .opacity(vm.petEnabled ? 1 : 0.35)

            SettingsActionRow {
              Button("Reset Pet") { vm.resetPetDefaults() }
                .buttonStyle(SettingsButtonStyle())
              Button("Reset All") { vm.resetAllSettings() }
                .buttonStyle(SettingsButtonStyle())
            }
          }
          .padding(.top, 12)
        } label: {
            SettingsDisclosureLabel(
              title: "Pet reactions",
              detail: "Choose which listening events animate the pet.")
        }
        .tint(SettingsPalette.accent)
      }
    }
  }
}

// MARK: - Diagnostics

private extension StatsQueries.EnrichmentProgress {
  static let empty = Self(
    total: 0,
    enriched: 0,
    trackArtistResolved: 0,
    artistTotal: 0,
    artistEnriched: 0,
    tagArtistTotal: 0,
    tagArtistChecked: 0,
    tagArtistTagged: 0)
}

private struct SettingsStatusPanel: View {
  let coord: AppCoordinator
  @State private var enrichment: StatsQueries.EnrichmentProgress = .empty
  @State private var enrichmentError: String?
  @State private var lastRefresh: Date?
  @State private var showThemeInspector = false

  var body: some View {
    SettingsSection("STATUS") {
      TimelineView(.periodic(from: .now, by: 5)) { ctx in
        VStack(alignment: .leading, spacing: 8) {
          statusRow("Last sync", value: lastSyncLabel(now: ctx.date))
          statusRow("Library scan", value: coord.backgroundEnrichmentLabel)
          statusRow("Audio meter", value: visualizerLabel)
          statusRow("Track data", value: enrichmentError ?? enrichmentLabel(enrichment))
          statusRow("Tags", value: enrichmentError == nil ? tagLabel(enrichment) : "-")
          if let lastRefresh {
            statusRow("Last check", value: lastSyncLabel(last: lastRefresh, now: ctx.date))
          }

          Divider()
            .overlay(SettingsPalette.rule)
            .padding(.vertical, 2)

          DisclosureGroup(isExpanded: $showThemeInspector) {
            VStack(alignment: .leading, spacing: 7) {
              statusRow("Theme", value: themeLabel)
              statusRow("Source", value: themeSourceLabel)
              statusRow("Confidence", value: themeConfidenceLabel)
              Text(themeReasonLabel)
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            .padding(.top, 6)
          } label: {
            SettingsDisclosureLabel(
              title: "Theme inspector",
              detail: "Shows why the current cartridge color was selected.")
          }
          .tint(SettingsPalette.accent)
        }
      }
    }
    .task { await refreshEnrichmentLoop() }
  }

  private func statusRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(SettingsType.caption)
        .foregroundStyle(SettingsPalette.muted)
      Spacer()
      Text(value)
        .font(SettingsType.mono)
        .contentTransition(.numericText())
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func lastSyncLabel(now: Date) -> String {
    guard let last = coord.lastSuccessfulPoll else { return "never" }
    return lastSyncLabel(last: last, now: now)
  }

  private func lastSyncLabel(last: Date, now: Date) -> String {
    let elapsed = now.timeIntervalSince(last)
    if elapsed < 5 { return "just now" }
    if elapsed < 60 { return "\(Int(elapsed)) sec ago" }
    if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
    return "\(Int(elapsed / 3600))h ago"
  }

  private var visualizerLabel: String {
    switch coord.visualizer.state {
    case .idle:    return "idle"
    case .running: return "live"
    case .denied:  return "permission denied"
    case .error:   return "offline"
    }
  }

  private var themeLabel: String {
    coord.nowPlaying.soundTheme.label
  }

  private var themeSourceLabel: String {
    coord.nowPlaying.soundThemeDecision?.source.label ?? "none"
  }

  private var themeConfidenceLabel: String {
    guard let confidence = coord.nowPlaying.soundThemeDecision?.confidence else { return "-" }
    return "\(Int((confidence * 100).rounded()))%"
  }

  private var themeReasonLabel: String {
    coord.nowPlaying.soundThemeDecision?.reason ?? "No current sound decision."
  }

  private func refreshEnrichmentLoop() async {
    await refreshEnrichment()
    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: 15_000_000_000)
      } catch {
        return
      }
      await refreshEnrichment()
    }
  }

  private func refreshEnrichment() async {
    let dbq = coord.dbq
    do {
      let snapshot = try await Task.detached(priority: .utility) {
        try StatsQueries(dbq: dbq).enrichmentProgress()
      }.value
      guard !Task.isCancelled else { return }
      await MainActor.run {
        enrichment = snapshot
        enrichmentError = nil
        lastRefresh = Date()
      }
    } catch is CancellationError {
      return
    } catch {
      await MainActor.run {
        enrichmentError = "unavailable"
        lastRefresh = Date()
      }
    }
  }

  private func enrichmentLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.total == 0 { return "-" }
    let artDone = enrichment.enriched.formatted(.number.notation(.compactName))
    let idDone = enrichment.trackArtistResolved.formatted(.number.notation(.compactName))
    let total = enrichment.total.formatted(.number.notation(.compactName))
    let artistDone = enrichment.artistEnriched.formatted(.number.notation(.compactName))
    let artistTotal = enrichment.artistTotal.formatted(.number.notation(.compactName))
    return "\(idDone) / \(total) matched · \(artDone) covers · \(artistDone) / \(artistTotal) Spotify profiles"
  }

  private func tagLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.tagArtistTotal == 0 { return "-" }
    let checked = enrichment.tagArtistChecked.formatted(.number.notation(.compactName))
    let tagged = enrichment.tagArtistTagged.formatted(.number.notation(.compactName))
    let total = enrichment.tagArtistTotal.formatted(.number.notation(.compactName))
    return "Last.fm \(checked) / \(total) checked · \(tagged) tagged"
  }
}

// MARK: - Preview Blocks

private struct MenuBarSettingsPreview: View {
  let mode: MenuBarDisplayMode
  let showAlbumArt: Bool
  let maxWidth: Double
  let showProgress: Bool

  private var measuredWidth: CGFloat {
    let textWidth = CGFloat(min(maxWidth, 186))
    switch mode {
    case .iconOnly:
      return 42
    case .albumArtTitle, .albumArtTrackArtist:
      return (showAlbumArt ? 34 : 8) + textWidth
    case .petTitle, .petOnly, .titlePlayCount, .tinyChaos:
      return textWidth
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
        .fill(SettingsPalette.control)
        .frame(width: measuredWidth, height: 28)
        .overlay(alignment: .leading) {
          HStack(spacing: 7) {
            if showAlbumArt && mode != .iconOnly {
              ZStack {
                RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)
                  .fill(SettingsPalette.accent.opacity(0.32))
                Rectangle()
                  .fill(SettingsPalette.text.opacity(0.16))
                  .frame(width: 7)
                  .offset(x: -4)
                DialIcon("music.note")
                  .frame(width: 9, height: 9)
                  .foregroundStyle(SettingsPalette.text.opacity(0.9))
              }
              .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous))
              .frame(width: 20, height: 20)
            } else {
              DialIcon("music.note")
                .frame(width: 13, height: 13)
                .foregroundStyle(SettingsPalette.text)
            }

            if mode != .iconOnly {
              Text(mode == .albumArtTrackArtist ? "VOLVER · Tainy" : "VOLVER")
                .font(.custom("GeistMono-Medium", size: 13))
                .foregroundStyle(SettingsPalette.text)
                .lineLimit(1)
            }
          }
          .padding(.horizontal, 8)
        }
        .overlay(alignment: .bottomLeading) {
          if showProgress {
            Capsule()
              .fill(SettingsPalette.accent)
              .frame(width: measuredWidth * 0.42, height: 2)
              .padding(.horizontal, 7)
              .padding(.bottom, 2)
          }
        }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(SettingsPalette.preview)
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
  }
}

private struct HUDSettingsPreview: View {
  @Bindable var vm: SettingsViewModel
  private var theme: DialTheme {
    DialTheme.palette(for: vm.hudColorMode.previewTheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .top, spacing: 12) {
        RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
          .fill(theme.surface)
          .frame(width: 52, height: 52)
          .overlay(
            DialIcon("music.note")
              .frame(width: 18, height: 18)
              .foregroundStyle(theme.accent))

        VStack(alignment: .leading, spacing: CGFloat(vm.hudHeroMetadataGap)) {
          Text("Blancanieves")
            .font(.custom("GeistMono-Medium", size: CGFloat(vm.hudHeroTitleSize * 0.68)))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
          Text("Natanael Cano")
            .font(.custom("GeistMono-Medium", size: CGFloat(vm.hudHeroArtistSize * 0.72)))
            .foregroundStyle(theme.textPrimary)
          Text("Porque La Demora")
            .font(.custom("GeistMono-Regular", size: CGFloat(vm.hudHeroAlbumSize * 0.72)))
            .foregroundStyle(theme.textMuted)

          if vm.showBadgesInHUD {
            Text("REDISCOVERED")
              .font(.custom("GeistPixel-Square", size: 7.5 * CGFloat(vm.hudBadgeScale)))
              .tracking(1.0)
              .foregroundStyle(theme.accent)
              .padding(.horizontal, 7 * CGFloat(vm.hudBadgeScale))
              .frame(height: 18 * CGFloat(vm.hudBadgeScale))
              .background(theme.accent.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous))
              .padding(.top, CGFloat(vm.hudHeroBadgeGap * 0.45))
          }
        }

        Spacer()
      }

      if vm.showReadoutsInHUD {
        HStack(spacing: 6) {
          previewReadout("PLAYS", "4")
          previewReadout("RANK", "#26")
          previewReadout("LAST", "12D")
        }
      }

      if vm.showVisualizerInHUD {
        MiniSpectrumPreview(
          density: vm.spectrumDensity,
          peakMarkers: vm.spectrumPeakMarkers,
          accent: theme.accent,
          control: theme.surface)
      }
    }
    .padding(12)
    .background(theme.subtle)
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
  }

  private func previewReadout(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(SettingsType.section)
        .foregroundStyle(theme.textMuted)
      Text(value)
        .font(.custom("GeistMono-Medium", size: 16))
        .foregroundStyle(theme.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(theme.surface.opacity(0.75))
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
  }
}

private struct ColorModeSelector: View {
  @Binding var selection: HUDColorMode

  private let fixedModes: [HUDColorMode] = [.classic, .slime, .aqua, .ember]

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 6) {
        Text("Color mode")
          .font(SettingsType.rowTitle)
          .foregroundStyle(SettingsPalette.text)
        SettingsHelpMark("Pick one theme, or let Dial choose a theme from the current track.")
      }

      VStack(spacing: 8) {
        ColorModeOption(
          mode: .followSound,
          selected: selection == .followSound,
          action: { selection = .followSound })

        LazyVGrid(columns: [
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
          ForEach(fixedModes) { mode in
            ColorModeOption(
              mode: mode,
              selected: selection == mode,
              action: { selection = mode })
          }
        }
      }
    }
  }
}

private struct ColorModeOption: View {
  let mode: HUDColorMode
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 10) {
        colorSwatches
          .frame(width: 58, alignment: .leading)

        VStack(alignment: .leading, spacing: 2) {
          Text(mode.label.uppercased())
            .font(SettingsType.section)
            .tracking(1.1)
            .foregroundStyle(selected ? accent : SettingsPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text(detail)
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.faint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Circle()
          .fill(selected ? accent : SettingsPalette.rule)
          .frame(width: 6, height: 6)
          .opacity(selected ? 1.0 : 0.55)
      }
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
          .stroke(selected ? accent.opacity(0.58) : SettingsPalette.rule, lineWidth: 1))
      .overlay(alignment: .top) {
        RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
          .fill(Color.white.opacity(selected ? 0.10 : 0.045))
          .frame(height: 1)
      }
    }
    .buttonStyle(.pressable)
    .help(helpText)
    .accessibilityLabel(mode.label)
    .accessibilityValue(selected ? "Selected" : "Not selected")
    .accessibilityHint(helpText)
  }

  @ViewBuilder
  private var colorSwatches: some View {
    if mode == .followSound {
      HStack(spacing: 3) {
        ForEach(DialThemeID.allCases) { id in
          swatch(DialTheme.palette(for: id).accent)
        }
      }
    } else {
      let theme = DialTheme.palette(for: mode.previewTheme)
      HStack(spacing: 3) {
        swatch(theme.ground)
        swatch(theme.accent)
        swatch(theme.accentAlt)
        swatch(theme.buttonRubber)
      }
    }
  }

  private var detail: String {
    switch mode {
    case .followSound: "Current track"
    case .classic:     "Neutral smoke"
    case .slime:       "Green shell"
    case .aqua:        "Blue shell"
    case .ember:       "Pink shell"
    }
  }

  private var helpText: String {
    switch mode {
    case .followSound: "Dial chooses a theme from the current track's tags and listening context."
    case .classic:     "Use the neutral smoke-gel theme for every track."
    case .slime:       "Use the green shell theme for every track."
    case .aqua:        "Use the blue shell theme for every track."
    case .ember:       "Use the translucent magenta theme for every track."
    }
  }

  private var accent: Color {
    mode == .followSound
      ? SettingsPalette.accent
      : DialTheme.palette(for: mode.previewTheme).accent
  }

  private var background: Color {
    if selected {
      return mode == .followSound
        ? SettingsPalette.controlPressed
        : DialTheme.palette(for: mode.previewTheme).subtle.opacity(0.95)
    }
    return SettingsPalette.control.opacity(0.78)
  }

  private func swatch(_ color: Color) -> some View {
    RoundedRectangle(cornerRadius: Dial.Radius.pixel, style: .continuous)
      .fill(color)
      .frame(width: 14, height: 12)
      .overlay(
        RoundedRectangle(cornerRadius: Dial.Radius.pixel, style: .continuous)
          .stroke(Color.white.opacity(0.16), lineWidth: 0.5))
  }
}

private struct PetSettingsPreview: View {
  let enabled: Bool
  let showInHUD: Bool

  var body: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous)
        .fill(enabled ? SettingsPalette.accent.opacity(0.16) : SettingsPalette.control)
        .frame(width: 58, height: 58)
        .overlay(
          DialIcon("sparkles")
            .frame(width: 20, height: 20)
            .foregroundStyle(enabled ? SettingsPalette.accent : SettingsPalette.muted))

      VStack(alignment: .leading, spacing: 3) {
        Text(enabled ? "Companion active" : "Companion disabled")
          .font(SettingsType.rowTitle)
        Text(showInHUD ? "Shown on Now Playing." : "Hidden from Now Playing.")
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.muted)
      }
      Spacer()
    }
    .padding(12)
    .background(SettingsPalette.preview)
    .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
  }
}

private struct MiniSpectrumPreview: View {
  let density: SpectrumDensity
  let peakMarkers: Bool
  let accent: Color
  let control: Color

  var body: some View {
    let columns = min(40, max(18, density.bandCount / 2))
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(0..<columns, id: \.self) { index in
        VStack(spacing: 2) {
          ForEach((0..<5).reversed(), id: \.self) { row in
            RoundedRectangle(cornerRadius: Dial.Radius.pixelCell)
              .fill(cellColor(index: index, row: row))
              .frame(width: 5, height: 4)
          }
        }
      }
    }
    .frame(height: 32, alignment: .bottom)
  }

  private func cellColor(index: Int, row: Int) -> Color {
    let height = (index * 7 + 11) % 5
    if row <= height { return accent.opacity(0.85) }
    if peakMarkers, row == height + 1 { return accent.opacity(0.28) }
    return control.opacity(0.85)
  }
}

// MARK: - Components

private enum SettingsLayout {
  static let windowWidth: CGFloat = 700
  static let windowHeight: CGFloat = 540
  static let sidebarWidth: CGFloat = 156
  static let sidePadding: CGFloat = 24
  static let contentTop: CGFloat = 20
  static let contentBottom: CGFloat = 24
  static let sectionGap: CGFloat = 16
  static let rowGap: CGFloat = 9
  static let controlGap: CGFloat = 9
  static let sectionPadding = EdgeInsets(top: 11, leading: 14, bottom: 12, trailing: 14)
  static let pickerWidth: CGFloat = 156
  static let textFieldWidth: CGFloat = 190
  static let scrollTopID = "settings-scroll-top"
}

private enum SettingsTab: String, CaseIterable, Identifiable {
  case general
  case menuBar
  case hud
  case pet

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .menuBar: "Menu Bar"
    case .hud:     "HUD"
    case .pet:     "Pet"
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape.fill"
    case .menuBar: "menubar.rectangle"
    case .hud:     "rectangle.inset.filled"
    case .pet:     "sparkles"
    }
  }
}

private enum SettingsPalette {
  private static let smoke = DialTheme.classic

  static let canvas = smoke.ground
  static let sidebar = smoke.subtle
  static let tray = Color(red: 0x08/255, green: 0x08/255, blue: 0x08/255)
  static let control = smoke.surface
  static let controlPressed = Color(red: 0x24/255, green: 0x24/255, blue: 0x24/255)
  static let preview = smoke.subtle
  static let text = smoke.textPrimary
  static let muted = smoke.textMuted
  static let faint = smoke.textMuted.opacity(0.72)
  static let rule = smoke.hairline.opacity(0.70)
  static let accent = smoke.accent
  static let prominentText = smoke.ground
  static let highlight = Color.white.opacity(0.10)
}

private enum SettingsType {
  static let tab = Font.custom("GeistMono-Medium", size: 12)
  static let section = Font.custom("GeistPixel-Square", size: 10)
  static let rowTitle = Font.custom("GeistMono-Medium", size: 13)
  static let caption = Font.custom("GeistMono-Regular", size: 11)
  static let mono = Font.custom("GeistMono-Medium", size: 11)
}

private struct SettingsSidebar: View {
  @Binding var selection: SettingsTab

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("DIAL")
        .font(SettingsType.section)
        .tracking(1.6)
        .foregroundStyle(SettingsPalette.muted)
        .padding(.horizontal, 14)
        .padding(.top, 4)

      VStack(spacing: 4) {
        ForEach(SettingsTab.allCases) { tab in
          Button {
            if selection != tab {
              let perf = DialPerf.begin("settings.tab_switch")
              selection = tab
              DispatchQueue.main.async {
                perf.end()
              }
            }
          } label: {
            HStack(spacing: 9) {
              DialIcon(tab.symbol)
                .frame(width: 14, height: 14)
                .frame(width: 18)
              Text(tab.title)
                .font(SettingsType.tab)
              Spacer(minLength: 0)
            }
            .foregroundStyle(selection == tab ? SettingsPalette.accent : SettingsPalette.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .dialHitSlop(horizontal: 4, vertical: 6)
            .background {
              if selection == tab {
                RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                  .fill(SettingsPalette.control)
                  .overlay(
                    RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                      .stroke(SettingsPalette.rule, lineWidth: 1))
              }
            }
          }
          .buttonStyle(.pressable)
          .accessibilityLabel(tab.title)
        }
      }

      Spacer()
    }
    .padding(EdgeInsets(top: 18, leading: 10, bottom: 14, trailing: 10))
    .frame(width: SettingsLayout.sidebarWidth)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(SettingsPalette.sidebar)
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(SettingsType.section)
        .tracking(1.4)
        .foregroundStyle(SettingsPalette.muted)
      content
        .padding(SettingsLayout.sectionPadding)
        .background(SettingsPalette.tray)
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous)
            .stroke(SettingsPalette.rule, lineWidth: 1))
        .overlay(alignment: .top) {
          Rectangle()
            .fill(SettingsPalette.highlight)
            .frame(height: 1)
            .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.panel, style: .continuous))
        }
    }
  }
}

private struct SettingsDisclosureLabel: View {
  let title: String
  let detail: String

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(SettingsType.rowTitle)
        .foregroundStyle(SettingsPalette.text)
      SettingsHelpMark(detail)
    }
    .help(detail)
  }
}

private struct SettingsToggle: View {
  let title: String
  let detail: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(alignment: .center, spacing: 9) {
        SettingsCheckbox(isOn: isOn)
        HStack(spacing: 6) {
          Text(title)
            .font(SettingsType.rowTitle)
            .foregroundStyle(SettingsPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.88)
          SettingsHelpMark(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        Spacer(minLength: 0)
      }
      .frame(minHeight: 31, alignment: .center)
      .contentShape(Rectangle())
    }
    .buttonStyle(.pressable)
    .help(detail)
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityHint(detail)
  }
}

private struct SettingsHelpMark: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    DialIcon("info.circle")
      .frame(width: 10, height: 10)
      .foregroundStyle(SettingsPalette.faint)
      .opacity(0.78)
      .help(text)
      .accessibilityHidden(true)
  }
}

private struct SettingsCheckbox: View {
  let isOn: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(isOn ? SettingsPalette.accent.opacity(0.16) : SettingsPalette.control)
      .frame(width: 16, height: 16)
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(isOn ? SettingsPalette.accent.opacity(0.75) : SettingsPalette.rule, lineWidth: 1)
      )
      .overlay {
        if isOn {
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(SettingsPalette.accent)
            .frame(width: 8, height: 8)
        }
      }
  }
}

private struct SettingsSliderRow: View {
  let title: String
  let detail: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let valueText: (Double) -> String

  @State private var draft: Double
  @State private var commitTask: Task<Void, Never>?

  init(
    title: String,
    detail: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    valueText: @escaping (Double) -> String
  ) {
    self.title = title
    self.detail = detail
    self._value = value
    self.range = range
    self.step = step
    self.valueText = valueText
    self._draft = State(initialValue: value.wrappedValue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        HStack(spacing: 6) {
          Text(title)
            .font(SettingsType.rowTitle)
            .lineLimit(1)
          SettingsHelpMark(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        Spacer(minLength: 10)
        Text(valueText(draft))
          .font(SettingsType.mono)
          .foregroundStyle(SettingsPalette.text)
          .monospacedDigit()
          .frame(minWidth: 56, alignment: .trailing)
      }
      Slider(
        value: Binding(
          get: { draft },
          set: { newValue in
            draft = newValue
            scheduleCommit(newValue)
          }),
        in: range,
        step: step,
        onEditingChanged: { editing in
          if !editing { commitNow() }
        })
        .tint(SettingsPalette.accent)
    }
    .onChange(of: value) { _, newValue in
      if abs(draft - newValue) > 0.0001 { draft = newValue }
    }
    .help(detail)
    .accessibilityHint(detail)
    .onDisappear { commitNow() }
  }

  private func scheduleCommit(_ newValue: Double) {
    commitTask?.cancel()
    commitTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: 180_000_000)
      } catch {
        return
      }
      value = newValue
    }
  }

  private func commitNow() {
    commitTask?.cancel()
    commitTask = nil
    value = draft
  }
}

private struct SettingsPickerRow<Value>: View
where Value: CaseIterable & Hashable & Identifiable, Value.AllCases: RandomAccessCollection {
  let title: String
  let detail: String
  @Binding var selection: Value
  let values: Value.AllCases

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      HStack(spacing: 6) {
        Text(title)
          .font(SettingsType.rowTitle)
          .lineLimit(1)
        SettingsHelpMark(detail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      Spacer(minLength: 10)
      Picker("", selection: $selection) {
        ForEach(values) { value in
          Text(label(for: value)).tag(value)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: SettingsLayout.pickerWidth)
      .controlSize(.regular)
      .dialHitSlop(horizontal: 4, vertical: 6)
    }
    .frame(minHeight: 32)
    .help(detail)
    .accessibilityHint(detail)
  }

  private func label(for value: Value) -> String {
    switch value {
    case let mode as MenuBarDisplayMode:
      mode.label
    case let screen as DefaultDropdownScreen:
      screen.label
    case let level as DialAnimationLevel:
      level.label
    case let colorMode as HUDColorMode:
      colorMode.label
    case let style as SpectrumStyle:
      style.label
    case let density as SpectrumDensity:
      density.label
    case let motion as SpectrumMotion:
      motion.label
    default:
      String(describing: value)
    }
  }
}

private struct SettingsActionRow<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    HStack(spacing: 8) {
      Spacer()
      content
    }
  }
}

private struct SettingsPresetGrid: View {
  let apply: (HUDSettingsPreset) -> Void

  var body: some View {
    LazyVGrid(columns: [
      GridItem(.flexible(), spacing: 8),
      GridItem(.flexible(), spacing: 8)
    ], spacing: 8) {
      ForEach(HUDSettingsPreset.allCases) { preset in
        Button {
          apply(preset)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(preset.label)
              .font(SettingsType.rowTitle)
              .foregroundStyle(SettingsPalette.text)
            Text(preset.detail)
              .font(SettingsType.caption)
              .foregroundStyle(SettingsPalette.faint)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
          .padding(10)
          .background(SettingsPalette.control)
          .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
              .stroke(SettingsPalette.rule, lineWidth: 1))
        }
        .buttonStyle(.pressable)
      }
    }
  }
}

private struct SettingsButtonStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    SettingsButtonBody(configuration: configuration, prominent: prominent)
  }

  private struct SettingsButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(SettingsType.tab)
        .foregroundStyle(prominent ? SettingsPalette.prominentText : SettingsPalette.text)
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(
          RoundedRectangle(cornerRadius: Dial.Radius.control)
            .fill(prominent ? SettingsPalette.accent : SettingsPalette.control)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.control)
            .stroke(Color.white.opacity(prominent ? 0.10 : 0.08), lineWidth: 1)
        )
        .dialHitSlop(horizontal: 4, vertical: 8.5)
        .opacity(configuration.isPressed ? 0.82 : 1.0)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}
