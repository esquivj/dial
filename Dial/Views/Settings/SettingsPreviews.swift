// Dial/Views/Settings/SettingsPreviews.swift
import SwiftUI

// MARK: - Preview Blocks

struct MenuBarSettingsPreview: View {
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

struct HUDSettingsPreview: View {
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

struct ColorModeSelector: View {
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

struct ColorModeOption: View {
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

struct PetSettingsPreview: View {
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

struct MiniSpectrumPreview: View {
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
