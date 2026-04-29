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
  @State private var showAdvancedMenuBarControls = false
  @State private var showAdvancedHUDControls = false
  @State private var showAdvancedPetControls = false

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(selection: $selectedTab)

      Rectangle()
        .fill(SettingsPalette.rule)
        .frame(width: 1)

      ScrollView {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
          currentTab
        }
        .padding(EdgeInsets(
          top: SettingsLayout.contentTop,
          leading: SettingsLayout.sidePadding,
          bottom: SettingsLayout.contentBottom,
          trailing: SettingsLayout.sidePadding))
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .id(selectedTab)
      .transaction { $0.animation = nil }
      .scrollIndicators(.visible)
    }
    .foregroundStyle(SettingsPalette.text)
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
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  @State private var showDisconnectAlert = false

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("SPOTIFY") {
        VStack(alignment: .leading, spacing: SettingsLayout.rowGap) {
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text(vm.signedIn ? "Connected" : "Not connected")
                .font(SettingsType.rowTitle)
                .foregroundStyle(SettingsPalette.text)
              Text(vm.signedIn
                   ? "Dial is reading playback, liked songs, and your local history."
                   : "Connect Spotify so Dial can learn what tracks mean to you.")
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
            }
            Spacer()
            if vm.signedIn {
              Button("Disconnect") { showDisconnectAlert = true }
                .buttonStyle(SettingsButtonStyle())
                .alert("Disconnect from Spotify?", isPresented: $showDisconnectAlert) {
                  Button("Cancel", role: .cancel) {}
                  Button("Disconnect", role: .destructive) {
                    coord.stopBackgroundEnrichment()
                    vm.markSignedOut()
                  }
                } message: {
                  Text("You'll need to reconnect to keep tracking listens. Your local history stays.")
                }
            } else {
              Button("Connect") { Task { await onSignIn() } }
                .buttonStyle(SettingsButtonStyle(prominent: true))
            }
          }

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
            Spacer()
            Button("Choose Folder") {
              let panel = NSOpenPanel()
              panel.canChooseDirectories = true
              panel.canChooseFiles = false
              if panel.runModal() == .OK, let url = panel.url { onImport(url) }
            }
            .buttonStyle(SettingsButtonStyle())
          }
        }
      }

      SettingsSection("SOUND INTELLIGENCE") {
        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Background analysis",
            detail: "Keep resolving track IDs, artist metadata, and tags while Dial is open.",
            isOn: Binding(
              get: { vm.backgroundEnrichmentEnabled },
              set: { value in
                vm.backgroundEnrichmentEnabled = value
                coord.syncBackgroundEnrichment()
              }))

          SettingsToggle(
            title: "Use Last.fm tags",
            detail: "Fetch artist tags and turn them into Dial sound families.",
            isOn: Binding(
              get: { vm.lastFMTagEnrichmentEnabled },
              set: { value in
                vm.lastFMTagEnrichmentEnabled = value
                coord.restartBackgroundEnrichmentNow()
              }))

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Last.fm API key")
                .font(SettingsType.rowTitle)
              Text("Required for genre-like tags. Stored locally in UserDefaults.")
                .font(SettingsType.caption)
                .foregroundStyle(SettingsPalette.muted)
            }
            Spacer()
            TextField("API key", text: $vm.lastFMAPIKey)
              .textFieldStyle(.plain)
              .font(SettingsType.mono)
              .foregroundStyle(SettingsPalette.text)
              .padding(.horizontal, 9)
              .frame(width: 178, height: 28)
              .background(SettingsPalette.control)
              .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                  .stroke(SettingsPalette.rule, lineWidth: 1))
          }

          SettingsActionRow {
            Button("Run Now") {
              vm.backgroundEnrichmentEnabled = true
              coord.restartBackgroundEnrichmentNow()
            }
            .buttonStyle(SettingsButtonStyle(prominent: true))
            .disabled(!vm.signedIn)
          }
        }
      }

      SettingsStatusPanel(coord: coord)

      SettingsSection("ABOUT") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Dial 0.1")
            .font(SettingsType.rowTitle)
          Text("A private music memory device for your Spotify history.")
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.muted)
        }
      }
    }
  }

  private var historyImportSubtitle: String {
    if let last = vm.lastImport {
      return "Last import: \(last.rowsInserted.formatted(.number)) rows"
    }
    return "Import your Spotify Extended Streaming History folder."
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
            detail: "Choose what lives in the menu bar.",
            selection: $vm.menuBarDisplayMode,
            values: MenuBarDisplayMode.allCases)

          SettingsToggle(
            title: "Show album art",
            detail: "Use the current cover when the selected mode has an art slot.",
            isOn: $vm.showAlbumArtInMenuBar)

          SettingsToggle(
            title: "Live Dock artwork",
            detail: "Use the current album cover as Dial's Dock icon.",
            isOn: $vm.showDockArtwork)
        }
      }

      SettingsSection("ADVANCED") {
        DisclosureGroup(isExpanded: $showAdvancedControls) {
          VStack(spacing: SettingsLayout.controlGap) {
            SettingsToggle(
              title: "Show progress line",
              detail: "Draw a tiny playback meter under the menu bar item.",
              isOn: $vm.showProgressInMenuBar)

            SettingsToggle(
              title: "Flash on new track",
              detail: "Pulse the menu bar item when Spotify changes songs.",
              isOn: $vm.flashOnTrackChange)

            SettingsSliderRow(
              title: "Max text width",
              detail: "Safety cap only; shorter tracks shrink to fit.",
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
            detail: "Progress, change pulse, and width cap.")
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
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsPickerRow(
            title: "Color mode",
            detail: "Use one mockup shell palette or let the current sound choose.",
            selection: $vm.hudColorMode,
            values: HUDColorMode.allCases)

          ThemeSwatchRow(selected: vm.hudColorMode)
        }
      }

      SettingsSection("OPENING") {
        SettingsPickerRow(
          title: "Default screen",
          detail: "Where a normal menu bar click should land.",
          selection: $vm.defaultDropdownScreen,
          values: DefaultDropdownScreen.allCases)
      }

      SettingsSection("CONTENT") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Show readouts",
            detail: "Keep PLAYS, RANK, and LAST PLAYED on the Now Playing screen.",
            isOn: $vm.showReadoutsInHUD)

          SettingsToggle(
            title: "Show badges",
            detail: "Show personal track context on the Now Playing screen.",
            isOn: $vm.showBadgesInHUD)

          SettingsToggle(
            title: "Show spectrum",
            detail: "Render the live ScreenCaptureKit audio visualizer.",
            isOn: $vm.showVisualizerInHUD)

          SettingsToggle(
            title: "Show transport",
            detail: "Show playback controls under the LCD panel.",
            isOn: $vm.showTransportInHUD)
        }
      }

      SettingsSection("ADVANCED") {
        DisclosureGroup(isExpanded: $showAdvancedControls) {
          VStack(spacing: SettingsLayout.controlGap) {
            SettingsPickerRow(
              title: "Animation level",
              detail: "Controls the HUD entrance timing.",
              selection: $vm.animationLevel,
              values: DialAnimationLevel.allCases)

            SettingsPickerRow(
              title: "Spectrum style",
              detail: "Precise uses a Blackman window and mel bands. Punchy favors faster hits.",
              selection: $vm.spectrumStyle,
              values: SpectrumStyle.allCases)

            SettingsPickerRow(
              title: "Spectrum density",
              detail: "More bands reveal more frequency detail inside the same strip.",
              selection: $vm.spectrumDensity,
              values: SpectrumDensity.allCases)

            SettingsPickerRow(
              title: "Spectrum motion",
              detail: "Controls how quickly bars rise and fall.",
              selection: $vm.spectrumMotion,
              values: SpectrumMotion.allCases)

            SettingsToggle(
              title: "Peak markers",
              detail: "Hold a bright top cell for loud transients.",
              isOn: $vm.spectrumPeakMarkers)

            SettingsToggle(
              title: "Discovery badges",
              detail: "First listens, new artists, rediscoveries, and deep cuts.",
              isOn: $vm.discoveryBadgesEnabled)

            SettingsToggle(
              title: "Pattern badges",
              detail: "Streaks, repeat runs, and album-mode listening.",
              isOn: $vm.patternBadgesEnabled)

            SettingsToggle(
              title: "Milestone badges",
              detail: "10th, 50th, 100th plays, and anniversaries.",
              isOn: $vm.milestoneBadgesEnabled)

            SettingsSliderRow(
              title: "Track title size",
              detail: "Primary Now Playing title size.",
              value: $vm.hudHeroTitleSize,
              range: 13...18,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Artist size",
              detail: "Artist line size under the track title.",
              value: $vm.hudHeroArtistSize,
              range: 10...15,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Album size",
              detail: "Album line size under the artist.",
              value: $vm.hudHeroAlbumSize,
              range: 9...14,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Metadata gap",
              detail: "Space between the title and artist/album cluster.",
              value: $vm.hudHeroMetadataGap,
              range: 0...8,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Badge gap",
              detail: "Space above the badge.",
              value: $vm.hudHeroBadgeGap,
              range: 2...10,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Badge scale",
              detail: "Overall size of the track-context badge.",
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
            detail: "Spectrum, badge categories, motion, and layout values.")
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
            detail: "Let the pixel companion react to playback and history.",
            isOn: $vm.petEnabled)

          SettingsToggle(
            title: "Show pet in HUD",
            detail: "Show the pet next to the current track.",
            isOn: $vm.showPetInHUD)
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
                detail: "A counted play briefly feeds the pet.",
                isOn: $vm.petFeedingAnimation)
              SettingsToggle(
                title: "First-listen animation",
                detail: "The pet perks up when a new track enters your history.",
                isOn: $vm.petFirstListenAnimation)
              SettingsToggle(
                title: "Rediscovery animation",
                detail: "The pet reacts when an old favorite comes back.",
                isOn: $vm.petRediscoveryAnimation)
              SettingsToggle(
                title: "Level-up animation",
                detail: "Stage changes get the big celebration treatment.",
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
            detail: "Fine-tune which playback events animate the pet.")
        }
        .tint(SettingsPalette.accent)
      }
    }
  }
}

// MARK: - Diagnostics

private struct SettingsStatusPanel: View {
  let coord: AppCoordinator

  var body: some View {
    SettingsSection("STATUS") {
      TimelineView(.periodic(from: .now, by: 1)) { ctx in
        let enrichment = currentEnrichment()
        VStack(alignment: .leading, spacing: 8) {
          statusRow("Last sync", value: lastSyncLabel(now: ctx.date))
          statusRow("Analyzer", value: coord.backgroundEnrichmentLabel)
          statusRow("Visualizer", value: visualizerLabel)
          statusRow("Enriched", value: enrichmentLabel(enrichment))
          statusRow("Sound tags", value: tagLabel(enrichment))
        }
      }
    }
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
    }
  }

  private func lastSyncLabel(now: Date) -> String {
    guard let last = coord.lastSuccessfulPoll else { return "never" }
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

  private func currentEnrichment() -> StatsQueries.EnrichmentProgress {
    (try? StatsQueries(dbq: coord.dbq).enrichmentProgress())
      ?? .init(
        total: 0,
        enriched: 0,
        trackArtistResolved: 0,
        artistTotal: 0,
        artistEnriched: 0,
        tagArtistTotal: 0,
        tagArtistChecked: 0,
        tagArtistTagged: 0)
  }

  private func enrichmentLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.total == 0 { return "-" }
    let artDone = enrichment.enriched.formatted(.number.notation(.compactName))
    let idDone = enrichment.trackArtistResolved.formatted(.number.notation(.compactName))
    let total = enrichment.total.formatted(.number.notation(.compactName))
    let artistDone = enrichment.artistEnriched.formatted(.number.notation(.compactName))
    let artistTotal = enrichment.artistTotal.formatted(.number.notation(.compactName))
    return "\(idDone) / \(total) IDs · \(artDone) art · \(artistDone) / \(artistTotal) artists"
  }

  private func tagLabel(_ enrichment: StatsQueries.EnrichmentProgress) -> String {
    if enrichment.tagArtistTotal == 0 { return "-" }
    let checked = enrichment.tagArtistChecked.formatted(.number.notation(.compactName))
    let tagged = enrichment.tagArtistTagged.formatted(.number.notation(.compactName))
    let total = enrichment.tagArtistTotal.formatted(.number.notation(.compactName))
    return "\(checked) / \(total) checked · \(tagged) tagged"
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
              RoundedRectangle(cornerRadius: Dial.Radius.tiny, style: .continuous)
                .fill(
                  LinearGradient(
                    colors: [SettingsPalette.accent.opacity(0.7), SettingsPalette.text.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
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

private struct ThemeSwatchRow: View {
  let selected: HUDColorMode

  var body: some View {
    HStack(spacing: 8) {
      ForEach(DialThemeID.allCases) { id in
        let theme = DialTheme.palette(for: id)
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 4) {
            swatch(theme.ground)
            swatch(theme.accent)
            swatch(theme.accentAlt)
            swatch(theme.buttonRubber)
          }
          Text(id.label.uppercased())
            .font(SettingsType.section)
            .tracking(1.0)
            .foregroundStyle(isSelected(id) ? theme.accent : SettingsPalette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(theme.subtle.opacity(isSelected(id) ? 1.0 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
            .stroke(isSelected(id) ? theme.accent.opacity(0.45) : SettingsPalette.rule, lineWidth: 1))
      }
    }
  }

  private func isSelected(_ id: DialThemeID) -> Bool {
    switch selected {
    case .followSound:
      return false
    case .classic:
      return id == .classic
    case .slime:
      return id == .slime
    case .aqua:
      return id == .aqua
    case .ember:
      return id == .ember
    }
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
        Text(showInHUD ? "Visible on Now Playing." : "Hidden from Now Playing.")
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
  static let windowWidth: CGFloat = 640
  static let windowHeight: CGFloat = 500
  static let sidebarWidth: CGFloat = 148
  static let sidePadding: CGFloat = 28
  static let contentTop: CGFloat = 24
  static let contentBottom: CGFloat = 26
  static let sectionGap: CGFloat = 22
  static let rowGap: CGFloat = 12
  static let controlGap: CGFloat = 14
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
  static let canvas = Color(red: 0x18/255, green: 0x19/255, blue: 0x19/255)
  static let sidebar = Color(red: 0x12/255, green: 0x13/255, blue: 0x14/255)
  static let tray = Color(red: 0x13/255, green: 0x14/255, blue: 0x15/255)
  static let control = Color(red: 0x24/255, green: 0x25/255, blue: 0x26/255)
  static let controlPressed = Color(red: 0x2E/255, green: 0x30/255, blue: 0x32/255)
  static let preview = Color(red: 0x1D/255, green: 0x1F/255, blue: 0x20/255)
  static let text = Color(red: 0xEA/255, green: 0xEA/255, blue: 0xEA/255)
  static let muted = Color(red: 0x8F/255, green: 0x90/255, blue: 0x94/255)
  static let faint = Color(red: 0x5D/255, green: 0x5F/255, blue: 0x63/255)
  static let rule = Color.white.opacity(0.08)
  static let accent = Dial.Palette.accent
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
            selection = tab
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
    }
  }
}

private struct SettingsDisclosureLabel: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(SettingsType.rowTitle)
        .foregroundStyle(SettingsPalette.text)
      Text(detail)
        .font(SettingsType.caption)
        .foregroundStyle(SettingsPalette.faint)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct SettingsToggle: View {
  let title: String
  let detail: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.checkbox)
        .tint(SettingsPalette.accent)
        .controlSize(.small)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(SettingsType.rowTitle)
          .foregroundStyle(SettingsPalette.text)
        Text(detail)
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.faint)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(minHeight: 34, alignment: .top)
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
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(SettingsType.rowTitle)
          Text(detail)
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.faint)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 10)
        Text(valueText(draft))
          .font(SettingsType.mono)
          .foregroundStyle(SettingsPalette.text)
          .monospacedDigit()
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
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(SettingsType.rowTitle)
        Text(detail)
          .font(SettingsType.caption)
          .foregroundStyle(SettingsPalette.faint)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 10)
      Picker("", selection: $selection) {
        ForEach(values) { value in
          Text(label(for: value)).tag(value)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 138)
      .controlSize(.regular)
    }
    .frame(minHeight: 36)
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
        .foregroundStyle(prominent ? Color.white : SettingsPalette.text)
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
        .opacity(configuration.isPressed ? 0.82 : 1.0)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}
