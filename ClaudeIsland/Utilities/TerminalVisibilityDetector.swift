//
//  TerminalVisibilityDetector.swift
//  ClaudeIsland
//
//  Detects if terminal windows are visible on current space
//

import AppKit
import CoreGraphics

struct TerminalVisibilityDetector {
    /// Check if any terminal window is visible on the current space
    static func isTerminalVisibleOnCurrentSpace() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }

            if TerminalAppRegistry.isTerminal(ownerName) {
                return true
            }
        }

        return false
    }

    /// Check if the frontmost (active) application is a terminal
    static func isTerminalFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return TerminalAppRegistry.isTerminalBundle(bundleId)
    }

    /// Check if a specific session's terminal tab/workspace is currently visible and active
    static func isSessionTerminalFrontmost(_ session: SessionState) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        guard TerminalAppRegistry.isTerminalBundle(bundleId) else {
            return false
        }

        let termApp = session.terminalApp?.lowercased() ?? ""
        let dirName = URL(fileURLWithPath: session.cwd).lastPathComponent

        // cmux: check workspace
        if termApp.contains("cmux") {
            return isCmuxSessionActive(session)
        }

        // iTerm2: check if current session name contains project dir
        if bundleId == "com.googlecode.iterm2" {
            return isITermSessionActive(dirName: dirName)
        }

        // Ghostty: check if current window title contains project dir
        if bundleId == "com.mitchellh.ghostty" {
            return isGhosttySessionActive(dirName: dirName)
        }

        // Terminal.app: check if current tab contains project dir
        if bundleId == "com.apple.Terminal" {
            return isTerminalAppSessionActive(dirName: dirName)
        }

        // Other terminals: terminal frontmost = assume session visible
        return true
    }

    /// Check if a cmux session's terminal is currently focused in the front window
    private static func isCmuxSessionActive(_ session: SessionState) -> Bool {
        return CmuxTreeParser.isSessionActive(cwd: session.cwd)
    }

    // MARK: - iTerm2

    private static func isITermSessionActive(dirName: String) -> Bool {
        let script = """
        tell application "iTerm2"
            try
                set sessionName to name of current session of current tab of current window
                if sessionName contains "\(dirName)" then return "true"
            end try
            return "false"
        end tell
        """
        return runAppleScriptBool(script)
    }

    // MARK: - Ghostty

    private static func isGhosttySessionActive(dirName: String) -> Bool {
        let script = """
        tell application "System Events"
            tell process "Ghostty"
                try
                    set winTitle to name of front window
                    if winTitle contains "\(dirName)" then return "true"
                end try
            end tell
        end tell
        return "false"
        """
        return runAppleScriptBool(script)
    }

    // MARK: - Terminal.app

    private static func isTerminalAppSessionActive(dirName: String) -> Bool {
        let script = """
        tell application "Terminal"
            try
                set tabTitle to custom title of selected tab of front window
                if tabTitle contains "\(dirName)" then return "true"
                set tabHistory to history of selected tab of front window
                if tabHistory contains "\(dirName)" then return "true"
            end try
            return "false"
        end tell
        """
        return runAppleScriptBool(script)
    }

    // MARK: - AppleScript Helper

    private static func runAppleScriptBool(_ script: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output == "true"
        } catch {
            return false
        }
    }

    /// Check if a Claude session is currently focused (user is looking at it)
    /// - Parameter sessionPid: The PID of the Claude process
    /// - Returns: true if the session's terminal is frontmost and (for tmux) the pane is active
    static func isSessionFocused(sessionPid: Int) async -> Bool {
        // If no terminal is frontmost, session is definitely not focused
        guard isTerminalFrontmost() else {
            return false
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: sessionPid, tree: tree)

        if isInTmux {
            // For tmux sessions, check if the session's pane is active
            return await TmuxTargetFinder.shared.isSessionPaneActive(claudePid: sessionPid)
        } else {
            // For non-tmux sessions, check if the session's terminal app is frontmost
            guard let sessionTerminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: sessionPid, tree: tree),
                  let frontmostApp = NSWorkspace.shared.frontmostApplication else {
                return false
            }

            return sessionTerminalPid == Int(frontmostApp.processIdentifier)
        }
    }
}
