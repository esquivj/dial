// Dial/DesignSystem/Dial+Tokens.swift
import SwiftUI

enum DialThemeID: String, CaseIterable, Identifiable {
  case classic
  case slime
  case aqua
  case ember

  var id: String { rawValue }

  var label: String {
    switch self {
    case .classic: "Classic"
    case .slime:   "Slime"
    case .aqua:    "Aqua"
    case .ember:   "Magenta"
    }
  }
}

struct DialTheme {
  let id: DialThemeID
  let ground: Color
  let surface: Color
  let subtle: Color
  let hairline: Color
  let accent: Color
  let accentAlt: Color
  let textPrimary: Color
  let textMuted: Color
  let lcd: Color
  let buttonRubber: Color
  let buttonChrome: Color
  let buttonGlow: Color

  static let classic = DialTheme(
    id: .classic,
    ground: Dial.Palette.ground,
    surface: Dial.Palette.surface,
    subtle: Dial.Palette.subtle,
    hairline: Dial.Palette.hairline,
    accent: Dial.Palette.accent,
    accentAlt: Dial.Palette.accentAlt,
    textPrimary: Dial.Palette.textPrimary,
    textMuted: Dial.Palette.textMuted,
    lcd: Dial.Palette.lcd,
    buttonRubber: Color(red: 0x19/255, green: 0x1E/255, blue: 0x24/255),
    buttonChrome: Color(red: 0xB8/255, green: 0xC0/255, blue: 0xC8/255),
    buttonGlow: Dial.Palette.accent)

  static let slime = DialTheme(
    id: .slime,
    ground: Color(red: 0x05/255, green: 0x13/255, blue: 0x0B/255),
    surface: Color(red: 0x0F/255, green: 0x1E/255, blue: 0x12/255),
    subtle: Color(red: 0x0B/255, green: 0x18/255, blue: 0x0F/255),
    hairline: Color(red: 0x2B/255, green: 0x39/255, blue: 0x2A/255),
    accent: Color(red: 0xB8/255, green: 0xFF/255, blue: 0x38/255),
    accentAlt: Color(red: 0xFF/255, green: 0xD5/255, blue: 0x43/255),
    textPrimary: Color(red: 0xEC/255, green: 0xF4/255, blue: 0xE4/255),
    textMuted: Color(red: 0x98/255, green: 0xA5/255, blue: 0x8E/255),
    lcd: Color(red: 0xC3/255, green: 0xD5/255, blue: 0x95/255),
    buttonRubber: Color(red: 0xEE/255, green: 0xC8/255, blue: 0x3C/255),
    buttonChrome: Color(red: 0xD0/255, green: 0xD7/255, blue: 0xC7/255),
    buttonGlow: Color(red: 0xB8/255, green: 0xFF/255, blue: 0x38/255))

  static let aqua = DialTheme(
    id: .aqua,
    ground: Color(red: 0x06/255, green: 0x0F/255, blue: 0x1C/255),
    surface: Color(red: 0x0E/255, green: 0x18/255, blue: 0x2A/255),
    subtle: Color(red: 0x0A/255, green: 0x14/255, blue: 0x22/255),
    hairline: Color(red: 0x22/255, green: 0x33/255, blue: 0x4C/255),
    accent: Color(red: 0x25/255, green: 0xC7/255, blue: 0xFF/255),
    accentAlt: Color(red: 0x74/255, green: 0xA0/255, blue: 0xFF/255),
    textPrimary: Color(red: 0xE9/255, green: 0xF0/255, blue: 0xF6/255),
    textMuted: Color(red: 0xA8/255, green: 0xB5/255, blue: 0xC4/255),
    lcd: Color(red: 0xB7/255, green: 0xC6/255, blue: 0xAE/255),
    buttonRubber: Color(red: 0xE9/255, green: 0xEC/255, blue: 0xEA/255),
    buttonChrome: Color(red: 0xB8/255, green: 0xC8/255, blue: 0xDA/255),
    buttonGlow: Color(red: 0x25/255, green: 0xC7/255, blue: 0xFF/255))

  static let ember = DialTheme(
    id: .ember,
    ground: Color(red: 0x12/255, green: 0x06/255, blue: 0x10/255),
    surface: Color(red: 0x23/255, green: 0x0F/255, blue: 0x20/255),
    subtle: Color(red: 0x19/255, green: 0x0A/255, blue: 0x17/255),
    hairline: Color(red: 0x53/255, green: 0x25/255, blue: 0x49/255),
    accent: Color(red: 0xFF/255, green: 0x4D/255, blue: 0xD2/255),
    accentAlt: Color(red: 0xFF/255, green: 0xB1/255, blue: 0xE8/255),
    textPrimary: Color(red: 0xF8/255, green: 0xE8/255, blue: 0xF4/255),
    textMuted: Color(red: 0xC8/255, green: 0xA2/255, blue: 0xBB/255),
    lcd: Color(red: 0xD7/255, green: 0xB8/255, blue: 0xCC/255),
    buttonRubber: Color(red: 0xA9/255, green: 0x43/255, blue: 0x87/255),
    buttonChrome: Color(red: 0xF5/255, green: 0xB8/255, blue: 0xE4/255),
    buttonGlow: Color(red: 0xFF/255, green: 0x4D/255, blue: 0xD2/255))

  static func palette(for id: DialThemeID) -> DialTheme {
    switch id {
    case .classic: classic
    case .slime:   slime
    case .aqua:    aqua
    case .ember:   ember
    }
  }
}

private struct DialThemeKey: EnvironmentKey {
  static let defaultValue = DialTheme.classic
}

extension EnvironmentValues {
  var dialTheme: DialTheme {
    get { self[DialThemeKey.self] }
    set { self[DialThemeKey.self] = newValue }
  }
}

/// Crystal Y2K palette — dark mode, cyan-LCD-on-black aesthetic.
enum Dial {
  enum Radius {
    /// Tiny individual pixels / meter cells. Kept small so the interface
    /// still feels like LCD hardware instead of soft app chrome.
    static let pixel: CGFloat = 2
    static let pixelCell: CGFloat = 1.5
    static let spectrumCellMax: CGFloat = 0.8

    /// Printed labels, badges, thumbnail masks.
    static let printed: CGFloat = 3
    static let tiny: CGFloat = 4

    /// Album art, pet LCDs, small media frames.
    static let media: CGFloat = 6

    /// Utility controls, readout rails, selected nav rows.
    static let control: CGFloat = 8
    static let transportTop: CGFloat = 4
    static let transportFoot: CGFloat = 8

    /// Inset panels and preview wells.
    static let panel: CGFloat = 10
    static let lcd: CGFloat = 12

    /// The whole handheld body. Slightly sharper than the previous 32pt
    /// corner so Dial reads less like a floating macOS bubble and more like
    /// a molded Y2K device.
    static let device: CGFloat = 28
  }

  enum Palette {
    /// Near-black with a teal shift — main background. Pure #000 reads
    /// too harsh and uniform-dark; nudging green up and red down gives
    /// the device body a subtle "tinted glass" identity instead of
    /// "rectangle filled with neutral dark." Mint glows bleed into a
    /// background that's already slightly mint-leaning, which reads as
    /// material continuity rather than "glow stuck on dark paint."
    static let ground   = Color(red: 0x07/255, green: 0x0E/255, blue: 0x14/255)
    /// Slightly elevated surface for cards, inset panels.
    static let surface  = Color(red: 0x12/255, green: 0x16/255, blue: 0x1B/255)
    /// Cyan-blue — primary accent. LCD readouts, numerals, status dot.
    /// #1FB6FF (was mint #00FFA3). Pivot to the Digivice-style cyan
    /// palette: cooler, more "powered LCD on a translucent toy device"
    /// than the prior mint reading. Contrast against `ground` is well
    /// above WCAG-AA at small text sizes.
    static let accent   = Color(red: 0x1F/255, green: 0xB6/255, blue: 0xFF/255)
    /// Hot pink — secondary, Y2K complement to mint.
    /// #FF4DD8 (was magenta #E84B98). Brightened to keep complementary
    /// tension against the brighter mint primary; muddier pinks read as
    /// "wine" rather than "neon" against #00FFA3.
    /// Used for ON STREAK / firstListen and other secondary moments.
    static let accentAlt = Color(red: 0xFF/255, green: 0x4D/255, blue: 0xD8/255)
    /// Cool off-white — primary text on dark.
    static let textPrimary = Color(red: 0xE8/255, green: 0xEB/255, blue: 0xED/255)
    /// Cool gray — secondary text, labels. Brightened from #6B7178 to
    /// #898F98 to clear WCAG-AA 4.5:1 contrast against `ground` for
    /// small text (the previous value was 3.93:1, technically failing).
    /// Still reads as "muted" against the cyan accent; the hue stays
    /// cool-neutral so it doesn't compete with the cyan/magenta.
    static let textMuted = Color(red: 0x89/255, green: 0x8F/255, blue: 0x98/255)

    // Legacy aliases for old call sites and historical tests. New code
    // should use semantic names above.
    static let amber = accent
    static let orange = accentAlt
    static let ivory = textPrimary
    static let muted = textMuted

    /// Hairline divider — subtle dark line on the dark ground.
    static let hairline = Color(red: 0x25/255, green: 0x2A/255, blue: 0x30/255)

    /// Slightly tinted card surface for inner panels (Stats pet panel, etc.).
    /// Sits between ground and surface.
    static let subtle   = Color(red: 0x0F/255, green: 0x13/255, blue: 0x16/255)

    /// Muted green-gray — the "powered-on Tamagotchi LCD" color. Used as
    /// the inside-fill of the pet's LCD bezel in TrackHero / PetView so
    /// the black-and-white pet sprite reads against a literally lit screen
    /// rather than against pure dark device chrome. Duller than the main
    /// cyan system on purpose: the pet should feel embedded in old handheld
    /// LCD glass, not like another active control.
    static let lcd      = Color(red: 0xB5/255, green: 0xBA/255, blue: 0x91/255)
  }

  enum Typography {
    /// Geist Pixel is the printed/LCD accent layer: section stamps,
    /// badge labels, tiny shell copy. Keep body and values in Geist Mono
    /// so the toy aesthetic doesn't tax quick reading.
    static let pixelLabel  = Font.custom("GeistPixel-Square", size: 9)
    static let pixelTiny   = Font.custom("GeistPixel-Square", size: 8)
    static let pixelBadge  = Font.custom("GeistPixel-Square", size: 9)
    static let pixelDecal  = Font.custom("GeistPixel-Square", size: 16)

    static let monoLabel   = pixelLabel
    /// Hero numeric values (PLAYS · YTD, RANK · 7D). 20 (was 28) — 28pt
    /// values were dominating the HUD's vertical real estate, especially
    /// when the values were "0" or "—" so the size shouted at empty
    /// content. 20 still reads as a "stat hero" without carrying its own
    /// gravity.
    static let monoValue   = Font.custom("GeistMono-Medium",  size: 20)
    static let monoSmall   = Font.custom("GeistMono-Regular", size: 10)
    static let monoTiny    = pixelTiny
    /// Pixel/mono treatment for the track title in TrackHero. Reserved
    /// for "this readout is on the device's LCD" — distinct from sansTitle,
    /// which is for app-text strings (e.g. the welcome screen heading).
    /// 16pt — bumped from 14pt now that the body is 360pt wide (was 320),
    /// giving the title VStack ~164pt of horizontal room. At 16pt mono
    /// medium most real-world titles (~14–17 chars) fit without
    /// triggering the marquee. The bigger size lets the title dominate
    /// the track row, which it should — it's the most important data
    /// point on the screen.
    static let monoTitle   = Font.custom("GeistMono-Medium",  size: 16)
    static let sansTitle   = Font.custom("GeistMono-Medium",  size: 14)
    static let sansBody    = Font.custom("GeistMono-Regular", size: 12)
    static let sansCaption = Font.custom("GeistMono-Regular", size: 11)
  }
}
