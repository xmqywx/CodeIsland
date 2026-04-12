//
//  NotchTheme.swift
//  ClaudeIsland
//
//  Palette definitions for the six built-in notch themes. Palette
//  colors drive the notch background, primary foreground (text,
//  icons), and the dimmer secondary foreground (timestamps,
//  percentage indicators). Status colors (success / warning / error)
//  are intentionally NOT part of the palette — they preserve
//  semantic meaning across themes and live in Assets.xcassets
//  under NotchStatus/.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 5.3.
//

import SwiftUI

struct NotchPalette: Equatable {
    let bg: Color
    let fg: Color
    let secondaryFg: Color
}

extension NotchPalette {
    /// Lookup the palette for a given theme ID. All six cases are
    /// defined inline so adding a theme means touching exactly one
    /// switch statement.
    static func `for`(_ id: NotchThemeID) -> NotchPalette {
        switch id {
        case .classic:
            return NotchPalette(
                bg: .black,
                fg: .white,
                secondaryFg: Color(white: 1, opacity: 0.4)
            )
        case .paper:
            return NotchPalette(
                bg: .white,
                fg: .black,
                secondaryFg: Color(white: 0, opacity: 0.55)
            )
        case .neonLime:
            return NotchPalette(
                bg: Color(hex: "CAFF00"),
                fg: .black,
                secondaryFg: Color(white: 0, opacity: 0.55)
            )
        case .cyber:
            return NotchPalette(
                bg: Color(hex: "7C3AED"),
                fg: Color(hex: "F0ABFC"),
                secondaryFg: Color(hex: "C4B5FD")
            )
        case .mint:
            return NotchPalette(
                bg: Color(hex: "4ADE80"),
                fg: .black,
                secondaryFg: Color(white: 0, opacity: 0.55)
            )
        case .sunset:
            return NotchPalette(
                bg: Color(hex: "FB923C"),
                fg: .black,
                secondaryFg: Color(white: 0, opacity: 0.5)
            )
        case .rosegold, .ocean, .aurora, .mocha, .lavender, .cherry:
            return NotchPalette(
                bg: .black,
                fg: .white,
                secondaryFg: Color(white: 1, opacity: 0.4)
            )
        }
    }
}

extension NotchThemeID {
    /// Human-readable English display name for the theme picker.
    /// Localized display names are resolved separately in the
    /// settings view so this file does not depend on L10n.
    var displayName: String {
        switch self {
        case .classic:  return "Classic"
        case .paper:    return "Paper"
        case .neonLime: return "Neon Lime"
        case .cyber:    return "Cyber"
        case .mint:     return "Mint"
        case .sunset:   return "Sunset"
        case .rosegold: return "Rose Gold"
        case .ocean:    return "Ocean"
        case .aurora:   return "Aurora"
        case .mocha:    return "Mocha"
        case .lavender: return "Lavender"
        case .cherry:   return "Cherry"
        }
    }
}
