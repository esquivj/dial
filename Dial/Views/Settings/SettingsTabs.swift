// Dial/Views/Settings/SettingsTabs.swift
import SwiftUI
import AppKit

// MARK: - Tabs

struct GeneralSettingsTab: View {
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

      LastFMSettingsSection(vm: vm, lastFM: coord.lastFM)

      PermissionsSettingsSection(coord: coord)

      StartupSettingsSection()

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
                detail: "Adds genre-style tags that help Dial choose themes and weekly traits. Uses the API key under Last.fm.",
                isOn: Binding(
                  get: { vm.lastFMTagEnrichmentEnabled },
                  set: { value in
                    vm.lastFMTagEnrichmentEnabled = value
                    coord.restartBackgroundEnrichmentNow()
                  }))

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

      SettingsShortcutsSection(hotkeys: vm.hotkeys)

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

struct MenuBarSettingsTab: View {
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

          SettingsToggle(
            title: "Desktop memory",
            detail: "Keep the current album and what it means to you on your desktop, under your windows.",
            isOn: $vm.showDesktopMemory)
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

struct HUDSettingsTab: View {
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
            title: "Memory pop-ups",
            detail: "When a new track brings back a memory, show it under the menu bar for a few seconds.",
            isOn: $vm.showMemoryPopups)

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

struct PetSettingsTab: View {
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
