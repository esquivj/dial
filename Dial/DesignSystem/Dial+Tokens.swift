// Dial/DesignSystem/Dial+Tokens.swift
import SwiftUI

enum Dial {
  enum Palette {
    static let ground   = Color(red: 0x0B/255, green: 0x0C/255, blue: 0x0F/255)
    static let surface  = Color(red: 0x17/255, green: 0x18/255, blue: 0x1C/255)
    static let amber    = Color(red: 0xFF/255, green: 0xB5/255, blue: 0x47/255)
    static let orange   = Color(red: 0xE8/255, green: 0x52/255, blue: 0x2A/255)
    static let ivory    = Color(red: 0xE6/255, green: 0xE2/255, blue: 0xD6/255)
    static let muted    = Color(red: 0x6B/255, green: 0x6E/255, blue: 0x74/255)
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
