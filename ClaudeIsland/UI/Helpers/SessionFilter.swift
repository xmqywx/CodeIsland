//
//  SessionFilter.swift
//  ClaudeIsland
//
//  Extracted filtering logic for session display list.
//  Separated for testability.
//

import Foundation

enum SessionFilter {
    /// Known probe/telemetry working directory markers from third-party tools
    /// (e.g. CodexBar uses ~/Library/Application Support/CodexBar/ClaudeProbe/).
    private static let probeMarkers = ["ClaudeProbe", "CodexBar"]

    /// Maximum sessions shown in the UI to prevent performance degradation.
    private static let displayLimit = 50

    /// Filter sessions for display:
    /// 1. Hide probe/telemetry sessions from third-party tools.
    /// 2. Hide rate-limit noise (ended sessions that ran < 30s).
    /// 3. Hide user-blacklisted projects (passed via `isHidden` predicate).
    /// 4. Cap total count to prevent UI freeze with excessive sessions.
    static func filterForDisplay(
        _ sessions: [SessionState],
        isHidden: (String) -> Bool = { _ in false }
    ) -> [SessionState] {
        let filtered = sessions.filter { session in
            // Filter probe sessions by cwd
            let cwd = session.cwd
            if probeMarkers.contains(where: { cwd.contains($0) }) {
                return false
            }
            // User-hidden projects
            if isHidden(cwd) {
                return false
            }

            // Rate-limit noise: short-lived sessions that ended quickly
            if session.phase == .ended {
                let duration = Date().timeIntervalSince(session.createdAt)
                return duration >= 30
            }
            return true
        }

        // Cap: keep active/recent sessions, drop oldest ended ones first
        guard filtered.count > displayLimit else { return filtered }
        let sorted = filtered.sorted { a, b in
            if a.phase != .ended && b.phase == .ended { return true }
            if a.phase == .ended && b.phase != .ended { return false }
            return a.lastActivity > b.lastActivity
        }
        return Array(sorted.prefix(displayLimit))
    }
}
