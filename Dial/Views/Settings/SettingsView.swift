import SwiftUI

extension Notification.Name {
  static let dialSelectSettingsTab = Notification.Name("DialSelectSettingsTab")
}

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
  @State private var pendingTabSwitch: SettingsTab?
  @State private var tabSwitchPerf: DialPerfInterval?

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(selection: $selectedTab) { tab in
        beginTabSwitch(to: tab)
      }

      Rectangle()
        .fill(SettingsPalette.rule)
        .frame(width: 1)

      ScrollViewReader { proxy in
        ScrollView {
          Color.clear
            .frame(height: 0)
            .id(SettingsLayout.scrollTopID)

          VStack(alignment: .leading, spacing: SettingsLayout.sectionGap) {
            currentTab
              .background {
                SettingsTabSwitchProbe(tab: selectedTab) { tab in
                  finishTabSwitch(for: tab)
                }
              }
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
    .onDisappear {
      finishPendingTabSwitch()
    }
    .onReceive(NotificationCenter.default.publisher(for: .dialSelectSettingsTab)) { notification in
      guard
        let rawValue = notification.object as? String,
        let tab = SettingsTab(rawValue: rawValue)
      else { return }
      selectTab(tab)
    }
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

  private func beginTabSwitch(to tab: SettingsTab) {
    finishPendingTabSwitch()
    pendingTabSwitch = tab
    tabSwitchPerf = DialPerf.begin("settings.tab_switch")
  }

  private func selectTab(_ tab: SettingsTab) {
    guard selectedTab != tab else { return }
    beginTabSwitch(to: tab)
    selectedTab = tab
  }

  private func finishTabSwitch(for tab: SettingsTab) {
    guard pendingTabSwitch == tab else { return }
    finishPendingTabSwitch()
  }

  private func finishPendingTabSwitch() {
    tabSwitchPerf?.end()
    tabSwitchPerf = nil
    pendingTabSwitch = nil
  }
}

private struct SettingsTabSwitchProbe: View {
  let tab: SettingsTab
  let onReady: (SettingsTab) -> Void

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .task(id: tab) {
        await Task.yield()
        await MainActor.run {
          onReady(tab)
        }
      }
  }
}
