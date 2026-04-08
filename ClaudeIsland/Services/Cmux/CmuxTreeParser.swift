//
//  CmuxTreeParser.swift
//  ClaudeIsland
//
//  Provides cross-window cmux navigation using cmux's native AppleScript dictionary.
//  Commands used: `focus terminal`, `activate window`, `select tab`, `input text`.
//  No cmux socket or System Events needed — only Automation permission for cmux.
//

import AppKit
import Foundation

/// Reads cmux session state and provides cross-window jumping via AppleScript
struct CmuxTreeParser {

    /// Check if cmux is running
    static var isAvailable: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.cmuxterm.app").first != nil
    }

    // MARK: - Jump

    /// Focus the terminal whose working directory matches `cwd`.
    /// This brings the correct window to front, selects the workspace, and focuses the pane — all in one call.
    @discardableResult
    static func jump(cwd: String) -> Bool {
        let script = """
        tell application "cmux"
            set targetTerm to (first terminal whose working directory is "\(escapeAS(cwd))")
            focus targetTerm
        end tell
        """
        let ok = runAS(script)
        DebugLogger.log("Cmux", "focus terminal cwd=\"\(cwd)\" ok=\(ok)")
        return ok
    }

    /// Focus a terminal by its UUID (from session JSON panel id).
    @discardableResult
    static func jump(panelId: String) -> Bool {
        let script = """
        tell application "cmux"
            focus terminal id "\(escapeAS(panelId))"
        end tell
        """
        let ok = runAS(script)
        DebugLogger.log("Cmux", "focus terminal id=\"\(panelId.prefix(8))…\" ok=\(ok)")
        return ok
    }

    // MARK: - Send Text (for permission approval)

    /// Send text to a terminal identified by working directory.
    static func sendText(_ text: String, toCwd cwd: String) -> Bool {
        let script = """
        tell application "cmux"
            set targetTerm to (first terminal whose working directory is "\(escapeAS(cwd))")
            input text "\(escapeAS(text))" to targetTerm
        end tell
        """
        return runAS(script)
    }

    // MARK: - Visibility

    /// Check if a session's terminal is currently the focused terminal in the front window.
    static func isSessionActive(cwd: String) -> Bool {
        guard isAvailable else { return true }
        let script = """
        tell application "cmux"
            if not frontmost then return "no"
            set ft to focused terminal of (selected tab of front window)
            if working directory of ft is "\(escapeAS(cwd))" then return "yes"
            return "no"
        end tell
        """
        let result = runASResult(script)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "yes"
    }

    // MARK: - AppleScript Helpers

    private static func runAS(_ source: String) -> Bool {
        let p = Process()
        let errPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DebugLogger.log("Cmux", "AS error: \(stderr.prefix(300))")
            }
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runASResult(_ source: String) -> String? {
        let p = Process()
        let outPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func escapeAS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
