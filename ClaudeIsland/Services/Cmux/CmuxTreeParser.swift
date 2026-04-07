//
//  CmuxTreeParser.swift
//  ClaudeIsland
//
//  Parses `cmux tree --all` output to locate surfaces across all windows.
//  Supports cross-window jumping via TTY matching, session ID, or directory name.
//

import Foundation

/// Represents a located surface in the cmux hierarchy
struct CmuxLocation: Sendable {
    let windowRef: String      // e.g., "window:2"
    let workspaceRef: String   // e.g., "workspace:4"
    let paneRef: String        // e.g., "pane:8"
    let surfaceRef: String     // e.g., "surface:14"
    let tty: String?           // e.g., "ttys008"
    let title: String          // e.g., "zhangzy@dgx-127: ~"
    let isSelected: Bool       // workspace has [selected] marker
}

/// Parses cmux tree output and provides cross-window surface lookup
struct CmuxTreeParser {
    static let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"

    /// Check if cmux is available
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: cmuxPath)
    }

    /// Run a cmux command synchronously and return output
    static func cmuxRun(_ args: [String]) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: cmuxPath)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    /// Parse the full `cmux tree --all` output into a list of CmuxLocations
    static func parseTree(_ treeOutput: String) -> [CmuxLocation] {
        var results: [CmuxLocation] = []
        var currentWindow: String?
        var currentWorkspace: String?
        var currentWorkspaceIsSelected = false
        var currentPane: String?

        for line in treeOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match window line: "window window:1 [current] ..."
            if let ref = extractRef(from: trimmed, prefix: "window ") {
                currentWindow = ref
                currentWorkspace = nil
                currentPane = nil
                continue
            }

            // Match workspace line: "workspace workspace:1 \"mini\" [selected] ..."
            if let ref = extractRef(from: trimmed, prefix: "workspace ") {
                currentWorkspace = ref
                currentWorkspaceIsSelected = trimmed.contains("[selected]")
                currentPane = nil
                continue
            }

            // Match pane line: "pane pane:1 [focused] ..."
            if let ref = extractRef(from: trimmed, prefix: "pane ") {
                currentPane = ref
                continue
            }

            // Match surface line: "surface surface:2 [terminal] \"title\" tty=ttys000"
            if let ref = extractRef(from: trimmed, prefix: "surface ") {
                guard let window = currentWindow,
                      let workspace = currentWorkspace,
                      let pane = currentPane else { continue }

                let tty = extractTTY(from: trimmed)
                let title = extractTitle(from: trimmed)

                results.append(CmuxLocation(
                    windowRef: window,
                    workspaceRef: workspace,
                    paneRef: pane,
                    surfaceRef: ref,
                    tty: tty,
                    title: title,
                    isSelected: currentWorkspaceIsSelected
                ))
            }
        }

        return results
    }

    /// Get all locations from `cmux tree --all`
    static func getAllLocations() -> [CmuxLocation] {
        guard isAvailable,
              let output = cmuxRun(["tree", "--all"]) else { return [] }
        return parseTree(output)
    }

    // MARK: - Lookup Methods

    /// Find a surface by TTY (most reliable method)
    /// If multiple surfaces share the same TTY, uses title containing host/dirName to disambiguate
    static func findByTTY(_ tty: String, host: String? = nil, dirName: String? = nil) -> CmuxLocation? {
        let locations = getAllLocations()
        let normalizedTTY = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        let candidates = locations.filter { $0.tty == normalizedTTY }

        if candidates.count == 1 { return candidates[0] }
        if candidates.isEmpty { return nil }

        // Disambiguate by title
        if let host = host,
           let match = candidates.first(where: { $0.title.contains(host) }) {
            return match
        }
        if let dirName = dirName,
           let match = candidates.first(where: { $0.title.contains(dirName) }) {
            return match
        }

        return candidates.first
    }

    /// Find a surface by session ID prefix or directory name across all windows
    static func findByContent(sessionId: String? = nil, dirName: String? = nil) -> CmuxLocation? {
        guard isAvailable else { return nil }

        let locations = getAllLocations()
        let sid = sessionId.map { String($0.prefix(8)) }

        // First try: match by session ID in title
        if let sid = sid,
           let match = locations.first(where: { $0.title.contains(sid) }) {
            return match
        }

        // Second try: match by directory name in title
        if let dirName = dirName,
           let match = locations.first(where: { $0.title.contains(dirName) }) {
            return match
        }

        // Third try: use cmux find-window across all windows
        // find-window only searches current window, so iterate windows
        if let dirName = dirName {
            return findByWindowSearch(query: dirName)
        }

        return nil
    }

    /// Find the workspace containing a surface by searching via find-window across all windows
    static func findByWindowSearch(query: String) -> CmuxLocation? {
        guard isAvailable else { return nil }

        // Get all window refs from tree output
        let locations = getAllLocations()
        let windowRefs = Array(Set(locations.map { $0.windowRef })).sorted()

        for windowRef in windowRefs {
            // Focus this window temporarily, try find-window
            _ = cmuxRun(["focus-window", "--window", windowRef])

            if let result = cmuxRun(["find-window", "--content", "--select", query]),
               result.contains("workspace:") {
                // Re-parse tree to get updated selected state
                let updatedLocations = getAllLocations()
                if let match = updatedLocations.first(where: {
                    $0.windowRef == windowRef && $0.isSelected
                }) {
                    return match
                }
            }
        }

        return nil
    }

    /// Find workspace ref that contains a given session (by sessionId or dirName) across all windows
    static func findWorkspaceRef(sessionId: String? = nil, dirName: String? = nil) -> String? {
        guard isAvailable else { return nil }

        let locations = getAllLocations()
        let sid = sessionId.map { String($0.prefix(8)) }

        // First pass: match by title in tree output
        for loc in locations {
            if let sid = sid, loc.title.contains(sid) { return loc.workspaceRef }
            if let dirName = dirName, loc.title.contains(dirName) { return loc.workspaceRef }
        }

        // Second pass: check via list-pane-surfaces for each unique workspace
        let uniqueWorkspaces = Array(Set(locations.map { $0.workspaceRef }))
        for wsRef in uniqueWorkspaces {
            guard let surfOutput = cmuxRun(["list-pane-surfaces", "--workspace", wsRef]) else { continue }
            if let sid = sid, surfOutput.contains(sid) { return wsRef }
            if let dirName = dirName, surfOutput.contains(dirName) { return wsRef }
        }

        return nil
    }

    // MARK: - Jump

    /// Perform a four-step jump to a CmuxLocation
    static func jump(to location: CmuxLocation) -> Bool {
        guard isAvailable else { return false }

        // 1. Focus the OS window
        _ = cmuxRun(["focus-window", "--window", location.windowRef])

        // 2. Select the workspace
        _ = cmuxRun(["select-workspace", "--workspace", location.workspaceRef])

        // 3. Focus the pane
        _ = cmuxRun(["focus-pane", "--pane", location.paneRef,
                      "--workspace", location.workspaceRef])

        // 4. Select the surface/tab
        _ = cmuxRun(["tab-action", "--action", "select",
                      "--surface", location.surfaceRef,
                      "--workspace", location.workspaceRef])

        return true
    }

    // MARK: - Visibility

    /// Check if a session's surface is currently the active/focused surface across all windows
    static func isSessionActive(sessionId: String, dirName: String, tty: String? = nil) -> Bool {
        guard isAvailable else { return true }

        // Get current focused info via cmux identify
        guard let identifyOutput = cmuxRun(["identify"]) else { return true }

        // Parse the focused workspace and surface refs from JSON
        guard let data = identifyOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let focused = json["focused"] as? [String: Any],
              let focusedWorkspace = focused["workspace_ref"] as? String,
              let focusedSurface = focused["surface_ref"] as? String else {
            return true
        }

        // Now find this session's location
        let locations = getAllLocations()
        let sid = String(sessionId.prefix(8))

        // Try TTY match first
        if let tty = tty {
            let normalizedTTY = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            let candidates = locations.filter { $0.tty == normalizedTTY }
            if let match = candidates.first {
                return match.workspaceRef == focusedWorkspace && match.surfaceRef == focusedSurface
            }
        }

        // Fall back to title matching
        for loc in locations {
            if loc.title.contains(sid) || loc.title.contains(dirName) {
                return loc.workspaceRef == focusedWorkspace && loc.surfaceRef == focusedSurface
            }
        }

        // Can't determine - assume active to avoid false alerts
        return true
    }

    // MARK: - Private Helpers

    /// Extract a ref like "window:1" or "workspace:2" from a line starting with the given prefix
    private static func extractRef(from line: String, prefix: String) -> String? {
        // Line examples:
        //   "window window:1 [current] ..."
        //   "workspace workspace:1 \"mini\" [selected] ..."
        //   "pane pane:1 [focused] ..."
        //   "surface surface:2 [terminal] \"title\" tty=ttys000"
        // Also handle tree drawing characters: "├── ", "└── ", "│   "
        let cleaned = line
            .replacingOccurrences(of: "├── ", with: "")
            .replacingOccurrences(of: "└── ", with: "")
            .replacingOccurrences(of: "│   ", with: "")
            .replacingOccurrences(of: "│", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard cleaned.hasPrefix(prefix) else { return nil }

        // The ref is the second word (e.g., "window:1")
        let words = cleaned.components(separatedBy: " ").filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }
        return words[1]
    }

    /// Extract TTY from a surface line (e.g., "tty=ttys008")
    private static func extractTTY(from line: String) -> String? {
        guard let range = line.range(of: "tty=") else { return nil }
        let afterTTY = String(line[range.upperBound...])
        let tty = afterTTY.components(separatedBy: " ").first ?? afterTTY
        return tty.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract quoted title from a surface line
    /// Format: surface surface:2 [terminal] "code | v4" [selected] tty=ttys000
    private static func extractTitle(from line: String) -> String {
        // Find first pair of quotes — that's the title
        guard let firstQuote = line.firstIndex(of: "\"") else { return "" }
        let afterFirst = line.index(after: firstQuote)
        guard afterFirst < line.endIndex else { return "" }
        let rest = line[afterFirst...]
        guard let secondQuote = rest.firstIndex(of: "\"") else { return String(rest) }
        return String(rest[..<secondQuote])
    }
}
