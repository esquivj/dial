import SwiftUI

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
