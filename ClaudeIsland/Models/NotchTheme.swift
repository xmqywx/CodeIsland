//
//  NotchTheme.swift
//  ClaudeIsland
//
//  Palette definitions for the built-in notch themes. Palette
//  colors drive the notch background, primary foreground (text,
//  icons), and the dimmer secondary foreground (timestamps,
//  percentage indicators). Status colors (success / warning / error)
//  are intentionally NOT part of the palette — they preserve
//  semantic meaning across themes and live in Assets.xcassets
//  under NotchStatus/.
//
//  v2 line-up (2026-04-20): Classic + six themes designed via
//  Claude Design (see /tmp/codeisland-themes/island/project/themes.jsx
//  for the full spec including per-state dots, corner SVGs, and
//  custom fonts — not all of which the NotchPalette 3-field shape
//  expresses today). The 3 fields below ARE the safe subset that
//  every call site already consumes.
//

import SwiftUI

struct NotchPalette: Equatable {
    let bg: Color
    let fg: Color
    let secondaryFg: Color
    /// Signature tint for idle-state dots, buddy highlights, and theme
    /// preview swatches. NOT used for semantic status (red/amber/green for
    /// error/attention/success) — those stay universal across themes.
    let accent: Color
}

extension NotchPalette {
    /// Lookup the palette for a given theme ID. All cases are
    /// defined inline so adding a theme means touching exactly one
    /// switch statement.
    static func `for`(_ id: NotchThemeID) -> NotchPalette {
        switch id {
        case .classic:
            return NotchPalette(
                bg: .black,
                fg: .white,
                secondaryFg: Color(white: 1, opacity: 0.4),
                accent: Color(hex: "CAFF00")
            )
        case .forest:
            return NotchPalette(
                bg: Color(hex: "0d1f14"),
                fg: Color(hex: "e8f5e9"),
                secondaryFg: Color(hex: "8ba896"),
                accent: Color(hex: "7cc85a")
            )
        case .neonTokyo:
            return NotchPalette(
                bg: Color(hex: "0a0520"),
                fg: Color(hex: "f0e6ff"),
                secondaryFg: Color(hex: "9a7ac8"),
                accent: Color(hex: "ff2e97")
            )
        case .sunset:
            return NotchPalette(
                bg: Color(hex: "fff4e8"),
                fg: Color(hex: "4a2618"),
                secondaryFg: Color(hex: "a06850"),
                accent: Color(hex: "e8552a")
            )
        case .retroArcade:
            return NotchPalette(
                bg: Color(hex: "c4cfa1"),
                fg: Color(hex: "2a3018"),
                secondaryFg: Color(hex: "5a6038"),
                accent: Color(hex: "2a3018")
            )
        case .highContrast:
            return NotchPalette(
                bg: .black,
                fg: .white,
                secondaryFg: .white,
                accent: Color(hex: "ffe600")
            )
        case .sakura:
            return NotchPalette(
                bg: Color(hex: "fff0f3"),
                fg: Color(hex: "6b2a3e"),
                secondaryFg: Color(hex: "b07088"),
                accent: Color(hex: "e66a88")
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
        case .classic:      return "Classic"
        case .forest:       return "Forest"
        case .neonTokyo:    return "Neon Tokyo"
        case .sunset:       return "Sunset"
        case .retroArcade:  return "Retro Arcade"
        case .highContrast: return "High Contrast"
        case .sakura:       return "Sakura"
        }
    }
}
