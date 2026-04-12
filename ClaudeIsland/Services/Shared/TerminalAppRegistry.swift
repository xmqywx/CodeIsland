//
//  TerminalAppRegistry.swift
//  ClaudeIsland
//
//  Centralized registry of known terminal applications
//

import Foundation

/// Registry of known terminal application names and bundle identifiers
struct TerminalAppRegistry: Sendable {
    /// Terminal app names for process matching
    static let appNames: Set<String> = [
        "Terminal",
        "iTerm2",
        "iTerm",
        "Ghostty",
        "Alacritty",
        "kitty",
        "Hyper",
        "Warp",
        "WezTerm",
        "Tabby",
        "Rio",
        "Contour",
        "foot",
        "st",
        "urxvt",
        "xterm",
        "cmux",
        "Electron",       // VS Code (macOS binary name in ps)
        "Code",           // VS Code
        "Code - Insiders",
        "Cursor",
        "Windsurf",
        "zed",
        "Zellij"
    ]

    /// Bundle identifiers for terminal apps (for window enumeration)
    static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "com.cmuxterm.app"
    ]

    /// Map a process command name to a friendly display name
    static func displayName(for command: String) -> String {
        let lower = command.lowercased()

        // Known mappings (process name → display name)
        let mappings: [(match: String, name: String)] = [
            ("ghostty", "Ghostty"),
            ("warp", "Warp"),
            ("stable", "Warp"),      // Warp's binary is called "stable"
            ("iterm", "iTerm2"),
            ("terminal", "Terminal"),
            ("alacritty", "Alacritty"),
            ("kitty", "Kitty"),
            ("wezterm", "WezTerm"),
            ("hyper", "Hyper"),
            ("tabby", "Tabby"),
            ("cmux", "cmux"),
            ("zellij", "Zellij"),
            ("electron", "VS Code"), // VS Code binary name as seen in ps on macOS
            ("code", "VS Code"),
            ("cursor", "Cursor"),
            ("windsurf", "Windsurf"),
            ("zed", "Zed"),
            ("rio", "Rio"),
            ("tmux", "tmux"),
        ]

        for (match, name) in mappings {
            if lower.contains(match) { return name }
        }

        return command // fallback to raw command name
    }

    /// Check if an app name or command path is a known terminal
    static func isTerminal(_ appNameOrCommand: String) -> Bool {
        let lower = appNameOrCommand.lowercased()

        // Check if any known app name is contained in the command (case-insensitive)
        for name in appNames {
            if lower.contains(name.lowercased()) {
                return true
            }
        }

        // Additional checks for common patterns
        return lower.contains("terminal") || lower.contains("iterm")
    }

    /// Check if a bundle identifier is a known terminal
    static func isTerminalBundle(_ bundleId: String) -> Bool {
        bundleIdentifiers.contains(bundleId)
    }
}
