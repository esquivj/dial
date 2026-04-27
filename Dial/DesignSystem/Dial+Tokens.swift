// Dial/DesignSystem/Dial+Tokens.swift
import SwiftUI

/// Crystal Y2K palette — dark mode, cyan-LCD-on-black aesthetic.
/// Pivoted to cyan-blue (#1FB6FF) as primary to match the Digivice-style
/// translucent toy reference. Token *names* preserved; their roles now
/// read as:
///   amber  → primary accent (cyan-blue LCD readout)
///   orange → secondary accent (hot pink — Y2K complement)
///   ivory  → primary text on dark
///   muted  → secondary text / labels
enum Dial {
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
    static let amber    = Color(red: 0x1F/255, green: 0xB6/255, blue: 0xFF/255)
    /// Hot pink — secondary, Y2K complement to mint.
    /// #FF4DD8 (was magenta #E84B98). Brightened to keep complementary
    /// tension against the brighter mint primary; muddier pinks read as
    /// "wine" rather than "neon" against #00FFA3.
    /// Used for ON STREAK / firstListen and other secondary moments.
    static let orange   = Color(red: 0xFF/255, green: 0x4D/255, blue: 0xD8/255)
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
    /// Pixel/mono treatment for the track title in TrackHero. Reserved
    /// for "this readout is on the device's LCD" — distinct from sansTitle,
    /// which is for app-text strings (e.g. the welcome screen heading).
    /// 16pt — bumped from 14pt now that the body is 360pt wide (was 320),
    /// giving the title VStack ~164pt of horizontal room. At 16pt mono
    /// medium most real-world titles (~14–17 chars) fit without
    /// triggering the marquee. The bigger size lets the title dominate
    /// the track row, which it should — it's the most important data
    /// point on the screen.
    static let monoTitle   = Font.custom("IBMPlexMono-Medium",  size: 16)
    static let sansTitle   = Font.custom("IBMPlexSans-Medium",  size: 14)
    static let sansBody    = Font.custom("IBMPlexSans-Regular", size: 12)
    static let sansCaption = Font.custom("IBMPlexSans-Regular", size: 11)
  }
}
