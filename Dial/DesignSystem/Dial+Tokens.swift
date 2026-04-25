// Dial/DesignSystem/Dial+Tokens.swift
import SwiftUI

/// Editorial Wine palette — light mode, pivoted from the original
/// "Vehicle Dashboard" amber-on-instrument-black mood. Token *names* are
/// kept (e.g. `amber`, `ivory`) so adopting code doesn't churn; their
/// roles now read as:
///   amber  → primary accent (dark wine)
///   orange → secondary accent (rose)
///   ivory  → primary text on cream
///   muted  → secondary text on cream
enum Dial {
  enum Palette {
    /// Warm cream / parchment — main background
    static let ground   = Color(red: 0xFA/255, green: 0xF7/255, blue: 0xF2/255)
    /// Pure white — elevated cards, panels, popover surfaces
    static let surface  = Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255)
    /// Dark wine — primary accent (numerals, chips, the pet sprite)
    static let amber    = Color(red: 0x3E/255, green: 0x05/255, blue: 0x1E/255)
    /// Rose — secondary accent, used for ON STREAK and other contextual moments
    static let orange   = Color(red: 0xA1/255, green: 0x30/255, blue: 0x6A/255)
    /// Warm charcoal — primary text on cream/white
    static let ivory    = Color(red: 0x1A/255, green: 0x14/255, blue: 0x19/255)
    /// Warm gray — secondary text, labels
    static let muted    = Color(red: 0x7A/255, green: 0x74/255, blue: 0x70/255)

    /// Hairline divider — replaces `Color.white.opacity(...)` from the dark era.
    /// Sits between ground and surface in tone.
    static let hairline = Color(red: 0xE5/255, green: 0xDF/255, blue: 0xD6/255)

    /// Slightly tinted cream for nested cards. Subtle — used inside Stats panel
    /// so blocks separate without adding visual weight.
    static let subtle   = Color(red: 0xF5/255, green: 0xF1/255, blue: 0xEA/255)
  }

  enum Typography {
    static let monoLabel   = Font.custom("IBMPlexMono-Regular", size: 9)
    static let monoValue   = Font.custom("IBMPlexMono-Medium",  size: 28)
    static let monoSmall   = Font.custom("IBMPlexMono-Regular", size: 10)
    static let monoTiny    = Font.custom("IBMPlexMono-Medium",  size: 8)
    static let sansTitle   = Font.custom("IBMPlexSans-Medium",  size: 14)
    static let sansBody    = Font.custom("IBMPlexSans-Regular", size: 12)
    static let sansCaption = Font.custom("IBMPlexSans-Regular", size: 11)
  }
}
