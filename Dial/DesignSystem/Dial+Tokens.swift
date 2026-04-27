// Dial/DesignSystem/Dial+Tokens.swift
import SwiftUI

/// Crystal Y2K palette — dark mode, cyan-glass-on-black aesthetic.
/// Pivoted from the prior "Editorial Wine" cream + wine pass.
/// Token *names* preserved; their roles now read as:
///   amber  → primary accent (crystal cyan)
///   orange → secondary accent (electric magenta — Y2K complement)
///   ivory  → primary text on dark
///   muted  → secondary text / labels
enum Dial {
  enum Palette {
    /// Near-black with a hint of blue — main background. Pure #000 reads
    /// too harsh, this gives the cyan glows somewhere to bleed into.
    static let ground   = Color(red: 0x0A/255, green: 0x0D/255, blue: 0x11/255)
    /// Slightly elevated surface for cards, inset panels.
    static let surface  = Color(red: 0x12/255, green: 0x16/255, blue: 0x1B/255)
    /// Crystal cyan — primary accent. Numerals, chips, the pet sprite.
    static let amber    = Color(red: 0x1A/255, green: 0xC5/255, blue: 0xBC/255)
    /// Electric magenta — secondary, classic Y2K complement to cyan.
    /// Used for ON STREAK and other secondary moments.
    static let orange   = Color(red: 0xE8/255, green: 0x4B/255, blue: 0x98/255)
    /// Cool off-white — primary text on dark.
    static let ivory    = Color(red: 0xE8/255, green: 0xEB/255, blue: 0xED/255)
    /// Cool gray — secondary text, labels. Brightened from #6B7178 to
    /// #898F98 to clear WCAG-AA 4.5:1 contrast against `ground` for
    /// small text (the previous value was 3.93:1, technically failing).
    /// Still reads as "muted" against the cyan accent; the hue stays
    /// cool-neutral so it doesn't compete with the cyan/magenta.
    static let muted    = Color(red: 0x89/255, green: 0x8F/255, blue: 0x98/255)

    /// Hairline divider — subtle dark line on the dark ground.
    static let hairline = Color(red: 0x25/255, green: 0x2A/255, blue: 0x30/255)

    /// Slightly tinted card surface for inner panels (Stats pet panel, etc.).
    /// Sits between ground and surface.
    static let subtle   = Color(red: 0x0F/255, green: 0x13/255, blue: 0x16/255)

    /// Pale green-cream — the "powered-on Tamagotchi LCD" color. Used as
    /// the inside-fill of the pet's LCD bezel in TrackHero / PetView so
    /// the black-and-white pet sprite reads against a literally lit screen
    /// rather than against pure dark device chrome. Sits outside the
    /// cyan/magenta accent system intentionally — the pet is its own
    /// identity, separate from the rest of the UI's tone palette.
    static let lcd      = Color(red: 0xC5/255, green: 0xCC/255, blue: 0xA0/255)
  }

  enum Typography {
    static let monoLabel   = Font.custom("IBMPlexMono-Regular", size: 9)
    /// Hero numeric values (PLAYS · 30D, RANK · 7D). 20 (was 28) — 28pt
    /// values were dominating the HUD's vertical real estate, especially
    /// when the values were "0" or "—" so the size shouted at empty
    /// content. 20 still reads as a "stat hero" without carrying its own
    /// gravity.
    static let monoValue   = Font.custom("IBMPlexMono-Medium",  size: 20)
    static let monoSmall   = Font.custom("IBMPlexMono-Regular", size: 10)
    static let monoTiny    = Font.custom("IBMPlexMono-Medium",  size: 8)
    static let sansTitle   = Font.custom("IBMPlexSans-Medium",  size: 14)
    static let sansBody    = Font.custom("IBMPlexSans-Regular", size: 12)
    static let sansCaption = Font.custom("IBMPlexSans-Regular", size: 11)
  }
}
