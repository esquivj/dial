// Dial/Views/Settings/SettingsComponents.swift
import SwiftUI
import Foundation

// MARK: - Components

enum SettingsLayout {
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

enum SettingsTab: String, CaseIterable, Identifiable {
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

enum SettingsPalette {
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

enum SettingsType {
  static let tab = Font.custom("GeistMono-Medium", size: 12)
  static let section = Font.custom("GeistPixel-Square", size: 10)
  static let rowTitle = Font.custom("GeistMono-Medium", size: 13)
  static let caption = Font.custom("GeistMono-Regular", size: 11)
  static let mono = Font.custom("GeistMono-Medium", size: 11)
}

struct SettingsSidebar: View {
  @Binding var selection: SettingsTab
  let onSelect: (SettingsTab) -> Void

  init(selection: Binding<SettingsTab>, onSelect: @escaping (SettingsTab) -> Void = { _ in }) {
    self._selection = selection
    self.onSelect = onSelect
  }

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
              onSelect(tab)
              selection = tab
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
                  .overlay(alignment: .leading) {
                    Capsule()
                      .fill(SettingsPalette.accent)
                      .frame(width: 2, height: 16)
                      .padding(.leading, 5)
                  }
                  .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: Dial.Radius.control, style: .continuous)
                      .fill(SettingsPalette.highlight)
                      .frame(height: 1)
                  }
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

struct SettingsSection<Content: View>: View {
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

struct SettingsDisclosureLabel: View {
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

struct SettingsToggle: View {
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

struct SettingsHelpMark: View {
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

struct SettingsCheckbox: View {
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

struct SettingsSliderRow: View {
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

struct SettingsPickerRow<Value>: View
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

struct SettingsActionRow<Content: View>: View {
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

struct SettingsPresetGrid: View {
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

struct SettingsButtonStyle: ButtonStyle {
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
        // Keep the whole label. Rows give their text column layout
        // priority, which otherwise squeezes the label down to nothing.
        .fixedSize()
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
