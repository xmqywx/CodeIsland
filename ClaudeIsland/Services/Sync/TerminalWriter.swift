//
//  TerminalWriter.swift
//  ClaudeIsland
//
//  Sends text to a Claude Code terminal session.
//  Used by the sync module to relay messages from the phone.
//

import Foundation
import AppKit
import os.log

/// Sends text input to a Claude Code terminal session.
@MainActor
final class TerminalWriter {

    static let logger = Logger(subsystem: "com.codeisland", category: "TerminalWriter")
    static let shared = TerminalWriter()

    private let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"

    private init() {}

    /// Send a text message to the terminal running the given session.
    func sendText(_ text: String, to session: SessionState) async -> Bool {
        let termApp = session.terminalApp?.lowercased() ?? ""

        // SSH remote sessions: route via relay command
        if session.isSSH, let host = session.remoteHost, let user = session.sshUser, let target = session.remoteTmuxTarget {
            return await sendTextViaSSH(text, host: host, user: user, target: target)
        }

        // Try cmux first (most precise)
        if FileManager.default.isExecutableFile(atPath: cmuxPath) {
            if await sendViaCmux(text, session: session) {
                return true
            }
        }

        // Try AppleScript for known terminals
        if termApp.contains("iterm") {
            return sendViaAppleScript(text, script: """
                tell application "iTerm2"
                    tell current session of current tab of current window
                        write text "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
                    end tell
                end tell
                """)
        }

        if termApp.contains("ghostty") {
            // Ghostty: use keystroke via System Events
            return sendViaAppleScript(text, script: """
                tell application "Ghostty" to activate
                delay 0.3
                tell application "System Events"
                    keystroke "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
                    key code 36
                end tell
                """)
        }

        if termApp.contains("terminal") && !termApp.contains("wez") {
            return sendViaAppleScript(text, script: """
                tell application "Terminal"
                    do script "\(text.replacingOccurrences(of: "\"", with: "\\\""))" in selected tab of front window
                end tell
                """)
        }

        Self.logger.warning("No supported terminal for session \(session.sessionId.prefix(8))")
        return false
    }

    /// Send text directly via cmux using a Claude session UUID + cwd, without needing
    /// a SessionState in SessionStore. Used when phone sends a message to a session
    /// CodeIsland isn't currently tracking locally.
    ///
    /// `livePid` is optional but strongly preferred — when SyncManager has a
    /// `SessionState` it can pass `session.pid`, which CodeIsland captured from
    /// the Claude process via `os.getppid()` in the hook script. That's the
    /// only 100% reliable identity, because it doesn't depend on argv parsing
    /// or cwd matching. argv/cwd fallbacks only kick in if the pid is missing
    /// or stale.
    func sendTextDirect(_ text: String, claudeUuid: String, cwd: String?, livePid: Int? = nil) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: cmuxPath) else {
            Self.logger.warning("cmux not found at \(self.cmuxPath)")
            return false
        }
        return await sendViaCmuxDirect(text, claudeUuid: claudeUuid, cwd: cwd, livePid: livePid)
    }

    /// Send a single control key (escape, ctrl+c, enter, …) to the Claude terminal.
    /// Returns true if the cmux surface was found and send-key invoked.
    func sendControlKey(_ key: String, claudeUuid: String, cwd: String? = nil, livePid: Int? = nil) async -> Bool {
        guard let (wsId, surfId) = findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid),
              let surfId else {
            Self.logger.warning("sendControlKey: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return false
        }
        let result = cmuxRun(["send-key", "--workspace", wsId, "--surface", surfId, "--", key])
        Self.logger.info("Sent key '\(key)' to cmux (ws=\(wsId.prefix(8)) surf=\(surfId.prefix(8))) result=\(result != nil)")
        return result != nil
    }

    /// Capture the terminal output that appeared *after* a slash command was sent.
    /// Snapshots the pane before, sends the command, waits for output to settle,
    /// then diffs the two snapshots and returns only the new lines.
    ///
    /// Returns nil if we can't locate the cmux surface for this Claude session or
    /// capture fails.
    func sendSlashCommandAndCaptureOutput(_ command: String, claudeUuid: String, cwd: String? = nil, livePid: Int? = nil, settleMs: UInt64 = 1500) async -> String? {
        guard let (wsId, surfId) = findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid),
              let surfId else {
            Self.logger.warning("captureOutput: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return nil
        }

        // Pre-snapshot
        let before = cmuxRun(["read-screen", "--workspace", wsId, "--surface", surfId, "--scrollback", "--lines", "500"]) ?? ""

        // Send the command
        let escaped = command.replacingOccurrences(of: "\n", with: "\r")
        _ = cmuxRun(["send", "--workspace", wsId, "--surface", surfId, "--", "\(escaped)\r"])

        // Wait for the CLI to render its response
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)

        // Post-snapshot
        let after = cmuxRun(["read-screen", "--workspace", wsId, "--surface", surfId, "--scrollback", "--lines", "500"]) ?? ""

        let diff = diffTerminalSnapshots(before: before, after: after)
        return diff.isEmpty ? nil : diff
    }

    /// Extract the text that newly appeared in `after` relative to `before`.
    /// Strategy: find the last non-empty anchor line from `before` in `after`,
    /// return everything after it. Falls back to the trailing portion if no anchor.
    nonisolated private func diffTerminalSnapshots(before: String, after: String) -> String {
        let beforeLines = before.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let afterLines = after.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard !afterLines.isEmpty else { return "" }

        // Find an anchor: the last non-empty meaningful line from `before` that
        // also appears in `after`. Search from the end of `before` forward.
        let meaningful = beforeLines.reversed().first { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.count > 4
        }

        if let anchor = meaningful,
           let idx = afterLines.lastIndex(of: anchor) {
            let newLines = Array(afterLines.suffix(from: afterLines.index(after: idx)))
            return cleanupOutputLines(newLines)
        }

        // Fallback: return the last N lines of the after snapshot
        let trailing = Array(afterLines.suffix(40))
        return cleanupOutputLines(trailing)
    }

    /// Normalize captured terminal lines: trim trailing whitespace, drop leading
    /// blank lines, collapse long runs of empty lines, cap total length.
    nonisolated private func cleanupOutputLines(_ lines: [String]) -> String {
        var cleaned: [String] = []
        var blankRun = 0
        for rawLine in lines {
            let line = rawLine.replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 && !cleaned.isEmpty {
                    cleaned.append("")
                }
            } else {
                blankRun = 0
                cleaned.append(line)
            }
        }
        // Trim leading/trailing blanks
        while let first = cleaned.first, first.isEmpty { cleaned.removeFirst() }
        while let last = cleaned.last, last.isEmpty { cleaned.removeLast() }
        var joined = cleaned.joined(separator: "\n")
        if joined.count > 4000 {
            joined = String(joined.suffix(4000))
        }
        return joined
    }

    /// Paste one or more images into the terminal running the given Claude session,
    /// then send any accompanying text. Uses NSPasteboard + CGEvent Cmd+V via cmux focus.
    /// Returns true if at least the focusing + paste attempts succeeded.
    func sendImagesAndText(images: [Data], text: String, claudeUuid: String, cwd: String? = nil, livePid: Int? = nil) async -> Bool {
        guard let (wsId, surfId) = findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid) else {
            Self.logger.warning("sendImagesAndText: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return false
        }
        guard let surfId else {
            Self.logger.warning("sendImagesAndText: missing surface id for uuid=\(claudeUuid.prefix(8))")
            return false
        }

        // Accessibility self-check — CGEvent and System Events keystrokes both
        // silently fail without this permission.
        let axTrusted = AXIsProcessTrusted()
        Self.logger.info("Accessibility trusted=\(axTrusted)")

        // 1. Switch cmux internally to the target surface. `focus-panel` is the
        //    correct command — cmux calls surfaces "panels" in CLI-speak.
        _ = cmuxRun(["focus-panel", "--panel", surfId, "--workspace", wsId])

        // 2. Bring cmux.app to the foreground. AppleScript is more reliable than
        //    NSRunningApplication here (the latter sometimes fails to locate cmux).
        _ = runOsascript(#"tell application id "com.cmuxterm.app" to activate"#)

        // Wait up to 1s for cmux to actually become frontmost.
        var frontOk = false
        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.cmuxterm.app" {
                frontOk = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        Self.logger.info("cmux frontmost=\(frontOk)")

        // Extra settle time after cmux is frontmost.
        try? await Task.sleep(nanoseconds: 200_000_000)

        for (idx, imgData) in images.enumerated() {
            writeImageToPasteboard(imgData)
            // Ensure pasteboard is settled before firing the key.
            try? await Task.sleep(nanoseconds: 120_000_000)
            // Use AppleScript keystroke as the primary path — it's more reliable than
            // raw CGEvent in many window server configurations. Fall back to CGEvent.
            if !postCmdVViaAppleScript() {
                Self.logger.info("AppleScript paste failed, falling back to CGEvent")
                postCmdV()
            }
            // Delay between multi-image pastes so Claude can ingest each.
            if idx < images.count - 1 {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        // Settle before sending the accompanying text so it doesn't race the paste.
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Text goes through cmux's own channel (bypasses the pasteboard path).
        let trailing = text.isEmpty
            ? "\r"
            : "\(text.replacingOccurrences(of: "\n", with: "\r"))\r"
        _ = cmuxRun(["send", "--workspace", wsId, "--surface", surfId, "--", trailing])

        Self.logger.info("Pasted \(images.count) image(s) + text via cmux (ws=\(wsId.prefix(8)) surf=\(surfId.prefix(8)))")
        return true
    }

    /// Place raw image bytes on the general pasteboard in the formats most terminals
    /// expect. We use the native format (jpeg/png) and also include TIFF as a lingua
    /// franca fallback.
    nonisolated private func writeImageToPasteboard(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // Decode so we can emit a TIFF representation too.
        guard let image = NSImage(data: data) else {
            // Fallback: just stamp the raw bytes under a guess.
            pb.setData(data, forType: NSPasteboard.PasteboardType("public.jpeg"))
            return
        }

        // Write NSImage first — terminals that register for image types pick this up.
        pb.writeObjects([image])

        // Also write the raw bytes under both jpeg and tiff types for maximum compat.
        pb.setData(data, forType: NSPasteboard.PasteboardType("public.jpeg"))
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    /// Post a Cmd+V key event via CGEvent. Requires Accessibility permission on macOS.
    nonisolated private func postCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // "V"
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    /// Simulate Cmd+V via AppleScript System Events. Returns true on success.
    nonisolated private func postCmdVViaAppleScript() -> Bool {
        return runOsascript(#"tell application "System Events" to keystroke "v" using {command down}"#)
    }

    @discardableResult
    nonisolated private func runOsascript(_ script: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func sendViaCmuxDirect(_ text: String, claudeUuid: String, cwd: String?, livePid: Int?) async -> Bool {
        // Resolution order (in increasing fallback unreliability):
        //   1. **Live PID from CodeIsland's hook tracking** — captured at hook
        //      time via `os.getppid()`, this is the actual Claude process for
        //      the conversation. Read CMUX_*_ID env vars from /proc and we're
        //      done. This works regardless of `claude --resume` rotating the
        //      live session-id, and it works for multiple sessions in the same
        //      cwd. THE preferred path.
        //   2. argv match by --session-id (works only for fresh, non-resumed
        //      sessions whose argv id == JSONL filename).
        //   3. cwd-scoped scan (heuristic — picks highest pid when multiple).
        guard let (wsId, surfId) = findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid) else {
            Self.logger.warning("No cmux-hosted claude process for uuid=\(claudeUuid.prefix(8)) cwd=\(cwd ?? "nil") pid=\(livePid?.description ?? "nil") — session is orphaned, in a non-cmux terminal, or on another machine")
            return false
        }

        let escaped = text.replacingOccurrences(of: "\n", with: "\r")
        var args = ["send"]
        args += ["--workspace", wsId]
        if let surfId { args += ["--surface", surfId] }
        args += ["--", "\(escaped)\r"]
        guard cmuxRun(args) != nil else {
            Self.logger.error("cmux send failed for workspace=\(wsId)")
            return false
        }
        Self.logger.info("Sent message via cmux (workspace=\(wsId.prefix(8)) surface=\(surfId?.prefix(8).description ?? "-"))")
        return true
    }

    /// Top-level resolver. Tries the most reliable identity first (live PID
    /// from CodeIsland's hook tracking), then falls back to argv match, then
    /// to cwd-scoped scanning.
    nonisolated private func findCmuxTarget(claudeUuid: String, cwd: String?, livePid: Int?) -> (workspaceId: String, surfaceId: String?)? {
        // Pass 0: hook-recorded live pid. Most reliable — `os.getppid()` from
        // the python hook script gives us the exact Claude process.
        if let livePid, let target = readCmuxIDs(forPid: livePid) {
            return target
        }
        // Falls back to argv-then-cwd inside the existing helper.
        return findCmuxTargetForClaudeSession(uuid: claudeUuid, cwd: cwd)
    }

    /// Look up a cmux workspace+surface for the live Claude process backing the
    /// given session UUID. Tries argv match first (works when JSONL id == live
    /// id), falls back to cwd-scoped scan when the conversation was resumed
    /// (rotating live id) or when CodeIsland is reporting the JSONL filename.
    nonisolated private func findCmuxTargetForClaudeSession(uuid: String, cwd: String?) -> (workspaceId: String, surfaceId: String?)? {
        let candidates = listClaudeProcesses()
        if candidates.isEmpty { return nil }

        // Pass 1: exact argv match by --session-id
        if let exact = candidates.first(where: { $0.sessionId == uuid }),
           let target = readCmuxIDs(forPid: exact.pid) {
            return target
        }

        // Pass 2: cwd-scoped fallback. Restrict to processes whose cwd matches
        // the session's cwd AND who have CMUX env vars (i.e. are inside a cmux
        // pane — no point routing to an iTerm window we can't drive).
        guard let cwd, !cwd.isEmpty else {
            Self.logger.info("findCmuxTarget: argv miss for uuid=\(uuid.prefix(8)) and no cwd to fall back on")
            return nil
        }

        let cwdMatched = candidates
            .filter { $0.cwd == cwd }
            .compactMap { proc -> (pid: Int, target: (workspaceId: String, surfaceId: String?))? in
                guard let target = readCmuxIDs(forPid: proc.pid) else { return nil }
                return (proc.pid, target)
            }

        guard !cwdMatched.isEmpty else {
            Self.logger.info("findCmuxTarget: no cwd-matching cmux-hosted claude in \(cwd)")
            return nil
        }

        if cwdMatched.count > 1 {
            Self.logger.warning("findCmuxTarget: \(cwdMatched.count) candidates in cwd=\(cwd) — picking highest pid as heuristic")
        }
        return cwdMatched.max { $0.pid < $1.pid }?.target
    }

    /// One running claude process — its pid, the session-id from argv, and its cwd.
    nonisolated private struct ClaudeProcessInfo {
        let pid: Int
        let sessionId: String
        let cwd: String?
    }

    /// Enumerate every `claude --session-id …` process. cwd resolved per pid via
    /// `lsof -p <pid> -d cwd -Fn` (lightweight: 1 line per pid).
    nonisolated private func listClaudeProcesses() -> [ClaudeProcessInfo] {
        let ps = Process()
        let out = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-Ax", "-o", "pid=,command="]
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var processes: [ClaudeProcessInfo] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("/claude"),
                  let sidRange = trimmed.range(of: "--session-id ")
            else { continue }
            let afterFlag = trimmed[sidRange.upperBound...]
            let sid: String = {
                if let space = afterFlag.firstIndex(of: " ") {
                    return String(afterFlag[..<space])
                }
                return String(afterFlag)
            }()
            let pidStr = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            guard let pid = Int(pidStr) else { continue }
            let cwd = lsofCwd(pid: pid)
            processes.append(ClaudeProcessInfo(pid: pid, sessionId: sid, cwd: cwd))
        }
        return processes
    }

    nonisolated private func lsofCwd(pid: Int) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Output format (-Fn): "p<pid>\nf<cwd>\nn<path>\n"
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Read CMUX_WORKSPACE_ID and CMUX_SURFACE_ID env vars from a running pid.
    /// Returns nil if the pid is gone, has no CMUX_WORKSPACE_ID, or ps -E fails.
    /// Results are cached for 5 minutes to avoid repeated ps syscalls.
    nonisolated private func readCmuxIDs(forPid pid: Int) -> (workspaceId: String, surfaceId: String?)? {
        // Check cache first
        if let cached = CmuxTargetCache.shared.get(pid) {
            return cached
        }

        let ps = Process()
        let pipe = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-E", "-p", "\(pid)", "-o", "command="]
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let envLine = String(data: data, encoding: .utf8) else { return nil }

        var wsId: String?
        var surfId: String?
        for token in envLine.split(separator: " ") {
            if token.hasPrefix("CMUX_WORKSPACE_ID=") {
                wsId = String(token.dropFirst("CMUX_WORKSPACE_ID=".count))
            } else if token.hasPrefix("CMUX_SURFACE_ID=") {
                surfId = String(token.dropFirst("CMUX_SURFACE_ID=".count))
            }
        }
        guard let wsId else { return nil }
        let result = (wsId, surfId)
        // Cache the result
        CmuxTargetCache.shared.set(pid, target: result)
        return result
    }

    // MARK: - cmux

    private func sendViaCmux(_ text: String, session: SessionState) async -> Bool {
        let dirName = URL(fileURLWithPath: session.cwd).lastPathComponent
        let sid = String(session.sessionId.prefix(8))

        // Find workspace
        guard let wsOutput = cmuxRun(["list-workspaces"]) else { return false }

        var targetWsRef: String?
        for wsLine in wsOutput.components(separatedBy: "\n") where !wsLine.isEmpty {
            guard let wsRef = wsLine.components(separatedBy: " ").first(where: { $0.hasPrefix("workspace:") }) else { continue }

            // Fast path: cmux often puts the Claude UUID and/or project name directly
            // in the workspace TITLE (e.g. `workspace:1  server · <title> · 6da6225e-…`),
            // while `list-pane-surfaces` may only show a short surface name. Check the
            // workspace line itself first.
            if wsLine.contains(sid) || wsLine.contains(dirName) {
                targetWsRef = wsRef
                break
            }

            // Fall back to matching inside the surface output.
            guard let surfOutput = cmuxRun(["list-pane-surfaces", "--workspace", wsRef]) else { continue }
            if surfOutput.contains(sid) || surfOutput.contains(dirName) {
                targetWsRef = wsRef
                break
            }
        }

        guard let wsRef = targetWsRef else {
            Self.logger.warning("No matching cmux workspace for sid=\(sid, privacy: .public) dir=\(dirName, privacy: .public)")
            return false
        }

        // Send text + Enter
        let escaped = text.replacingOccurrences(of: "\n", with: "\r")
        _ = cmuxRun(["send", "--workspace", wsRef, "--", "\(escaped)\r"])
        Self.logger.info("Sent message to cmux workspace \(wsRef, privacy: .public)")
        return true
    }

    // MARK: - SSH Remote

    /// Valid tmux target pattern: alphanumeric with session separators
    private static let tmuxTargetPattern = #"^[a-zA-Z0-9_.:#@-%]+$"#

    /// Send text to a remote tmux session via SSH relay.
    /// SECURITY: Text is base64-encoded to prevent command injection when passed through
    /// a shell command string. Without this, characters like $() or backticks in the text
    /// would be evaluated as shell commands on the remote.
    /// The tmux target is also validated against a strict pattern.
    private func sendTextViaSSH(_ text: String, host: String, user: String, target: String) async -> Bool {
        // Validate target to prevent command injection through tmux target field
        guard let regex = try? NSRegularExpression(pattern: Self.tmuxTargetPattern),
              regex.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)) != nil else {
            Self.logger.error("Invalid tmux target rejected: \(target)")
            return false
        }

        var sshArgs = ["-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "\(user)@\(host)"]

        // Base64-encode the text to prevent shell injection via $(), backticks, etc.
        guard let textData = text.data(using: .utf8) else { return false }
        let encoded = textData.base64EncodedString()
        // Decode on remote and pass to tmux -- stops shell interpretation entirely.
        // The decoded content is passed to tmux send-keys -- which takes literal text.
        let remoteCmd = "printf '%s' '\(encoded)' | base64 -d | tmux send-keys -t \(target) -- - && tmux send-keys -t \(target) Enter"

        do {
            _ = try await ProcessExecutor.shared.run(
                "/usr/bin/ssh",
                arguments: sshArgs + ["-o", "StrictHostKeyChecking=accept-new", remoteCmd]
            )
            Self.logger.info("Sent text via SSH to \(host):\(target)")
            return true
        } catch {
            Self.logger.error("SSH send failed to \(host):\(target): \(error.localizedDescription)")
            return false
        }
    }

    private func cmuxRun(_ args: [String]) -> String? {
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

    // MARK: - AppleScript

    private func sendViaAppleScript(_ text: String, script: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let success = process.terminationStatus == 0
            if success {
                Self.logger.info("Sent message via AppleScript")
            }
            return success
        } catch {
            return false
        }
    }
}
