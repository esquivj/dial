import SwiftUI
import AppKit

/// Hosted by the SwiftUI `Settings` scene in `DialApp`.
/// The layout intentionally mirrors compact utility apps like Codexbar:
/// icon tabs up top, plain section headers, and dense rows with short
/// explanations. No giant settings cockpit.
struct SettingsView: View {
  @Bindable var vm: SettingsViewModel
  /// Diagnostic data source — exposes lastSuccessfulPoll, the visualizer
  /// state, and the dbq for enrichment-progress queries.
  @Bindable var coord: AppCoordinator
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  @State private var selectedTab: SettingsTab = .general
  @State private var showDisconnectAlert = false
  @State private var showAdvancedHUDTuning = false
  @State private var enrichment: StatsQueries.EnrichmentProgress = .init(total: 0, enriched: 0)

  var body: some View {
    VStack(spacing: 0) {
      tabBar
      Divider().overlay(SettingsPalette.rule)
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
      .scrollIndicators(.visible)
    }
    .foregroundStyle(SettingsPalette.text)
    .background(SettingsPalette.canvas)
    .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
    .task {
      enrichment = (try? StatsQueries(dbq: coord.dbq).enrichmentProgress())
        ?? .init(total: 0, enriched: 0)
    }
  }

  // MARK: - Chrome

  private var tabBar: some View {
    HStack(spacing: 4) {
      ForEach(SettingsTab.allCases) { tab in
        Button {
          withAnimation(.easeOut(duration: 0.12)) {
            selectedTab = tab
          }
        } label: {
          HStack(spacing: 6) {
            DialIcon(tab.symbol)
              .frame(width: 13, height: 13)
              .frame(width: 16)
            Text(tab.title)
              .font(SettingsType.tab)
          }
          .foregroundStyle(selectedTab == tab ? SettingsPalette.accent : SettingsPalette.muted)
          .frame(width: 102, height: 30)
          .background {
            if selectedTab == tab {
              RoundedRectangle(cornerRadius: 7)
                .fill(SettingsPalette.control)
                .overlay(
                  RoundedRectangle(cornerRadius: 7)
                    .stroke(SettingsPalette.rule, lineWidth: 1))
            }
          }
        }
        .buttonStyle(.pressable)
      }
    }
    .padding(4)
    .background(
      RoundedRectangle(cornerRadius: 11)
        .fill(SettingsPalette.tray)
        .overlay(
          RoundedRectangle(cornerRadius: 11)
            .stroke(SettingsPalette.rule, lineWidth: 1))
    )
    .padding(.top, 14)
    .padding(.bottom, 12)
  }

  @ViewBuilder
  private var currentTab: some View {
    switch selectedTab {
    case .general:
      generalTab
    case .menuBar:
      menuBarTab
    case .hud:
      hudTab
    case .pet:
      petTab
    }
  }

  // MARK: - General

  private var generalTab: some View {
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
                  Button("Disconnect", role: .destructive) { vm.markSignedOut() }
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

      SettingsSection("STATUS") {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          VStack(alignment: .leading, spacing: 8) {
            statusRow("Last sync", value: lastSyncLabel(now: ctx.date))
            statusRow("Visualizer", value: visualizerLabel)
            statusRow("Enriched", value: enrichmentLabel)
          }
        }
      }

      SettingsSection("ABOUT") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Dial 0.1")
            .font(SettingsType.rowTitle)
          Text("A personal Spotify HUD that turns listening history into track context.")
            .font(SettingsType.caption)
            .foregroundStyle(SettingsPalette.muted)
        }
      }
    }
  }

  // MARK: - Menu Bar

  private var menuBarTab: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
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
            title: "Show progress line",
            detail: "Draw a tiny cyan playback meter under the menu bar item.",
            isOn: $vm.showProgressInMenuBar)

          SettingsToggle(
            title: "Flash on new track",
            detail: "Pulse the menu bar item when Spotify changes songs.",
            isOn: $vm.flashOnTrackChange)

          SettingsToggle(
            title: "Live Dock artwork",
            detail: "Show Dial in the Dock using the current album cover.",
            isOn: $vm.showDockArtwork)

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text("Max text width")
                  .font(SettingsType.rowTitle)
                Text("Safety cap only; shorter tracks shrink to fit.")
                  .font(SettingsType.caption)
                  .foregroundStyle(SettingsPalette.muted)
              }
              Spacer()
              Text("\(Int(vm.menuBarTitleWidth)) pt")
                .font(SettingsType.mono)
                .foregroundStyle(SettingsPalette.text)
                .monospacedDigit()
            }
            Slider(value: $vm.menuBarTitleWidth, in: 80...260, step: 10)
              .tint(SettingsPalette.accent)
          }
        }
      }
    }
  }

  // MARK: - HUD

  private var hudTab: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
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
            detail: "Keep PLAYS and RANK cards on the Now Playing screen.",
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

          SettingsPickerRow(
            title: "Animation level",
            detail: "Controls the HUD entrance timing.",
            selection: $vm.animationLevel,
            values: DialAnimationLevel.allCases)
        }
      }

      SettingsSection("SPECTRUM") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsPickerRow(
            title: "Style",
            detail: "Precise uses a Blackman window and mel bands. Punchy favors faster hits.",
            selection: $vm.spectrumStyle,
            values: SpectrumStyle.allCases)

          SettingsPickerRow(
            title: "Density",
            detail: "More bands reveal more frequency detail inside the same strip.",
            selection: $vm.spectrumDensity,
            values: SpectrumDensity.allCases)

          SettingsPickerRow(
            title: "Motion",
            detail: "Controls how quickly bars rise and fall.",
            selection: $vm.spectrumMotion,
            values: SpectrumMotion.allCases)

          SettingsToggle(
            title: "Peak markers",
            detail: "Hold a bright top cell for loud transients.",
            isOn: $vm.spectrumPeakMarkers)
        }
      }

      SettingsSection("ADVANCED UI TUNING") {
        DisclosureGroup(isExpanded: $showAdvancedHUDTuning) {
          VStack(spacing: SettingsLayout.controlGap) {
            SettingsSliderRow(
              title: "Track title size",
              detail: "Primary Now Playing title size.",
              value: $vm.hudHeroTitleSize,
              range: 14...22,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Artist size",
              detail: "Artist line size under the track title.",
              value: $vm.hudHeroArtistSize,
              range: 11...17,
              step: 1,
              valueText: { "\(Int($0.rounded())) pt" })

            SettingsSliderRow(
              title: "Album size",
              detail: "Album line size under the artist.",
              value: $vm.hudHeroAlbumSize,
              range: 10...16,
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
              detail: "Space above the badge or pet reaction line.",
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

            HStack {
              Spacer()
              Button("Reset HUD Defaults") { vm.resetHUDTuningDefaults() }
                .buttonStyle(SettingsButtonStyle())
            }
          }
          .padding(.top, 12)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text("HUD layout controls")
              .font(SettingsType.rowTitle)
              .foregroundStyle(SettingsPalette.text)
            Text("Typography, spacing, badge scale, and shell curvature.")
              .font(SettingsType.caption)
              .foregroundStyle(SettingsPalette.muted)
          }
        }
        .tint(SettingsPalette.accent)
      }

      SettingsSection("BADGES") {
        VStack(spacing: SettingsLayout.controlGap) {
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
        }
      }
    }
  }

  // MARK: - Pet

  private var petTab: some View {
    VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
      SettingsSection("COMPANION") {
        VStack(spacing: SettingsLayout.controlGap) {
          SettingsToggle(
            title: "Enable pet",
            detail: "Let the pixel companion react to playback and history.",
            isOn: $vm.petEnabled)

          SettingsToggle(
            title: "Show pet in HUD",
            detail: "Show the pet and its current reaction next to the track.",
            isOn: $vm.showPetInHUD)
            .disabled(!vm.petEnabled)
            .opacity(vm.petEnabled ? 1 : 0.35)
        }
      }

      SettingsSection("REACTIONS") {
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
      }
    }
  }

  // MARK: - Status

  private var historyImportSubtitle: String {
    if let last = vm.lastImport {
      return "Last import: \(last.rowsInserted.formatted(.number)) rows"
    }
    return "Import your Spotify Extended Streaming History folder."
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

  private var enrichmentLabel: String {
    if enrichment.total == 0 { return "-" }
    let done = enrichment.enriched.formatted(.number.notation(.compactName))
    let total = enrichment.total.formatted(.number.notation(.compactName))
    return "\(done) / \(total) tracks"
  }
}

// MARK: - Components

private enum SettingsLayout {
  static let windowWidth: CGFloat = 500
  static let windowHeight: CGFloat = 460
  static let sidePadding: CGFloat = 32
  static let contentTop: CGFloat = 20
  static let contentBottom: CGFloat = 24
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
  static let tray = Color(red: 0x13/255, green: 0x14/255, blue: 0x15/255)
  static let control = Color(red: 0x24/255, green: 0x25/255, blue: 0x26/255)
  static let controlPressed = Color(red: 0x2E/255, green: 0x30/255, blue: 0x32/255)
  static let text = Color(red: 0xEA/255, green: 0xEA/255, blue: 0xEA/255)
  static let muted = Color(red: 0x8F/255, green: 0x90/255, blue: 0x94/255)
  static let faint = Color(red: 0x5D/255, green: 0x5F/255, blue: 0x63/255)
  static let rule = Color.white.opacity(0.08)
  static let accent = Dial.Palette.accent
}

private enum SettingsType {
  static let tab = Font.custom("IBMPlexSans-Medium", size: 12)
  static let section = Font.custom("IBMPlexMono-Medium", size: 10)
  static let rowTitle = Font.custom("IBMPlexSans-Medium", size: 13)
  static let caption = Font.custom("IBMPlexSans-Regular", size: 11)
  static let mono = Font.custom("IBMPlexMono-Medium", size: 11)
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
        Text(valueText(value))
          .font(SettingsType.mono)
          .foregroundStyle(SettingsPalette.text)
          .monospacedDigit()
      }
      Slider(value: $value, in: range, step: step)
        .tint(SettingsPalette.accent)
    }
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
          RoundedRectangle(cornerRadius: 7)
            .fill(prominent ? SettingsPalette.accent : SettingsPalette.control)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.white.opacity(prominent ? 0.10 : 0.08), lineWidth: 1)
        )
        .opacity(configuration.isPressed ? 0.82 : 1.0)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}
