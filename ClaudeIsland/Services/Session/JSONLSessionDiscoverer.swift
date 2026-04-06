//
//  JSONLSessionDiscoverer.swift
//  ClaudeIsland
//
//  Discovers Claude Code sessions by scanning ~/.claude/projects for recent
//  JSONL files. Used when hook-based discovery is unavailable (e.g., cmux
//  overrides ~/.claude/settings.json with its own --settings flag).
//

import Foundation
import os.log

/// Polls ~/.claude/projects for recent JSONL files and creates synthetic
/// hook events for sessions not already tracked.
@MainActor
final class JSONLSessionDiscoverer {

    static let shared = JSONLSessionDiscoverer()
    static let logger = Logger(subsystem: "com.codeisland", category: "JSONLDiscoverer")

    private var timer: Timer?

    /// Sessions considered "active" if their JSONL file was modified within this window
    private let activeWindow: TimeInterval = 300 // 5 minutes

    /// Poll interval
    private let pollInterval: TimeInterval = 5.0

    private var discoveredSessionIds = Set<String>()

    private init() {}

    func start() {
        stop()
        Self.logger.info("JSONLSessionDiscoverer started")

        // Do an initial scan immediately
        Task { await scan() }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        discoveredSessionIds.removeAll()
    }

    private func scan() async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects", isDirectory: true)

        guard fm.fileExists(atPath: projectsDir.path) else { return }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-activeWindow)
        var activeSessions: [(sessionId: String, cwd: String, modified: Date)] = []

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            // Decode cwd from directory name (e.g., "-Users-ying-Documents" → "/Users/ying/Documents")
            let dirName = projectDir.lastPathComponent
            let cwd = decodeCwd(dirName)

            guard let jsonlFiles = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in jsonlFiles where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate,
                      modified > cutoff else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent

                // Skip agent- files (subagent sessions)
                if sessionId.hasPrefix("agent-") { continue }

                activeSessions.append((sessionId: sessionId, cwd: cwd, modified: modified))
            }
        }

        // Create hook events for newly discovered sessions
        for discovered in activeSessions {
            if !discoveredSessionIds.contains(discovered.sessionId) {
                // Check if SessionStore already knows about it (from hooks)
                let existing = await SessionStore.shared.session(for: discovered.sessionId)
                if existing != nil {
                    discoveredSessionIds.insert(discovered.sessionId)
                    continue
                }

                discoveredSessionIds.insert(discovered.sessionId)
                Self.logger.info("Discovered session via JSONL: \(discovered.sessionId.prefix(8)) at \(discovered.cwd)")

                // Create a synthetic hook event so SessionStore creates the session
                let syntheticEvent = HookEvent(
                    sessionId: discovered.sessionId,
                    cwd: discovered.cwd,
                    event: "SessionStart",
                    status: "active",
                    pid: nil,
                    tty: nil,
                    tool: nil,
                    toolInput: nil,
                    toolUseId: nil,
                    notificationType: nil,
                    message: nil
                )
                await SessionStore.shared.process(.hookReceived(syntheticEvent))
            }
        }
    }

    /// Convert a project directory name back to a cwd path.
    /// E.g., "-Users-ying-Documents" → "/Users/ying/Documents"
    private func decodeCwd(_ dirName: String) -> String {
        return dirName.replacingOccurrences(of: "-", with: "/")
    }
}
