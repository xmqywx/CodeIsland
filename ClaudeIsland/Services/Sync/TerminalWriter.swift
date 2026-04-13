//
//  TerminalWriter.swift
//  ClaudeIsland
//
//  Sends text to a Claude Code terminal session.
//  Used by the sync module to relay messages from the phone.
//

import Foundation
import AppKit
import ApplicationServices
import Darwin
import os.log

/// File-scope helper: spawn a subprocess on a background queue, read its stdout,
/// and force-kill it if it exceeds the given timeout. Returns `(stdout, success)`.
///
/// This exists because `Process().waitUntilExit()` + `readDataToEndOfFile()` are
/// synchronous and will freeze the main thread if the child hangs (cmux CLI
/// unresponsive, osascript denied by macOS TCC, etc.). Every subprocess launch
/// in TerminalWriter MUST go through this helper — do not add new raw
/// `try process.run()` sites.
///
/// `terminationGrace` is the SIGTERM→SIGKILL gap; we escalate if the child
/// doesn't exit on its own after SIGTERM.
private func runShellWithTimeout(
    _ executable: String,
    _ arguments: [String],
    timeout: TimeInterval = 5.0,
    terminationGrace: TimeInterval = 0.25
) async -> (output: String?, success: Bool) {
    await withCheckedContinuation { (continuation: CheckedContinuation<(String?, Bool), Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice

            do {
                try p.run()
            } catch {
                DebugLogger.log("Shell", "launch failed: \(executable) \(arguments.joined(separator: " ")) — \(error.localizedDescription)")
                continuation.resume(returning: (nil, false))
                return
            }

            // Watchdog: SIGTERM at `timeout`, SIGKILL at `timeout + grace` if still alive.
            let watchdog = DispatchWorkItem { [p] in
                guard p.isRunning else { return }
                DebugLogger.log("Shell", "timeout \(timeout)s — SIGTERM \(executable) \(arguments.first ?? "")")
                p.terminate()
                Thread.sleep(forTimeInterval: terminationGrace)
                if p.isRunning {
                    DebugLogger.log("Shell", "still alive after SIGTERM — SIGKILL \(executable)")
                    kill(p.processIdentifier, SIGKILL)
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

            // Reads block until the pipe is closed — happens when the child exits
            // (normally or via watchdog termination above).
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            watchdog.cancel()

            let output = String(data: data, encoding: .utf8)
            let success = p.terminationStatus == 0
            continuation.resume(returning: (output, success))
        }
    }
}

/// Sends text input to a Claude Code terminal session.
@MainActor
final class TerminalWriter {

    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "TerminalWriter")
    static let shared = TerminalWriter()

    private init() {}

    // MARK: - Diagnostics (for Settings → cmux Connection tab)

    /// A snapshot of everything the cmux-relay path needs to work. Consumed by
    /// the cmux connection diagnostic UI in System Settings.
    struct ConnectionProbe: Sendable {
        let cmuxBinaryInstalled: Bool
        let accessibilityGranted: Bool
        let claudeSessionCount: Int
        /// Automation (AppleEvents) permission for the first running terminal.
        /// nil = no supported terminal running, or not yet prompted.
        let automationGranted: Bool?
        /// Which terminal was probed + human-readable status. Surfaced in the
        /// status row so users can tell "cmux granted" from "cmux not
        /// prompted" at a glance.
        let automationDetail: String
        /// First detected cmux-hosted target (workspaceId, surfaceId?), used by
        /// the "Test send" button. nil if no cmux-hosted Claude is running.
        let testTarget: (workspaceId: String, surfaceId: String?)?
    }

    /// Run all the health checks a user would need to diagnose "why isn't my
    /// phone message landing in cmux". Non-invasive — does not write to any
    /// terminal.
    func probeConnection() async -> ConnectionProbe {
        let cmuxOk = FileManager.default.isExecutableFile(atPath: self.cmuxPath)
        let axOk = AXIsProcessTrusted()
        let procs = await listClaudeProcesses()
        var firstTarget: (workspaceId: String, surfaceId: String?)?
        for proc in procs {
            if let t = await readCmuxIDs(forPid: proc.pid) {
                firstTarget = t
                break
            }
        }
        let (autoOk, autoDetail) = probeAutomationPermission()
        return ConnectionProbe(
            cmuxBinaryInstalled: cmuxOk,
            accessibilityGranted: axOk,
            claudeSessionCount: procs.count,
            automationGranted: autoOk,
            automationDetail: autoDetail,
            testTarget: firstTarget
        )
    }

    /// Non-invasive probe for Automation (AppleEvents) TCC permission. Uses
    /// `AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: false`
    /// so it never triggers the TCC dialog — the dedicated "Request
    /// Automation permission" button is responsible for that.
    ///
    /// We check cmux first (the primary relay target), then fall back to
    /// other supported terminals. Returns `(granted, detail)`:
    /// - `(true, "cmux ✓")`   — granted
    /// - `(false, "cmux — err=-1743")` — explicitly denied
    /// - `(nil, "cmux — not yet prompted")` — consent would be required
    /// - `(nil, "...")` — no supported terminal running
    private func probeAutomationPermission() -> (granted: Bool?, detail: String) {
        let candidates: [(bundleId: String, label: String)] = [
            ("com.cmuxterm.app", "cmux"),
            ("com.googlecode.iterm2", "iTerm"),
            ("com.mitchellh.ghostty", "Ghostty"),
            ("com.apple.Terminal", "Terminal")
        ]
        for (bundleId, label) in candidates {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { continue }

            var addr = AEAddressDesc()
            let bundleData = Data(bundleId.utf8)
            let createStatus: OSErr = bundleData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSErr in
                guard let baseAddress = bytes.baseAddress else { return OSErr(-1) }
                return AECreateDesc(DescType(typeApplicationBundleID),
                                    baseAddress,
                                    bytes.count,
                                    &addr)
            }
            guard createStatus == OSErr(noErr) else {
                return (nil, "\(label) — AECreateDesc err=\(createStatus)")
            }
            defer { AEDisposeDesc(&addr) }

            let status = AEDeterminePermissionToAutomateTarget(
                &addr,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                false
            )
            switch status {
            case noErr:
                return (true, "\(label) ✓")
            case OSStatus(errAEEventNotPermitted):
                return (false, "\(label) — denied (err=-1743)")
            case -1744: // errAEEventWouldRequireUserConsent
                return (nil, "\(label) — not yet prompted")
            default:
                return (nil, "\(label) — status=\(status)")
            }
        }
        return (nil, L10n.automationUnknown)
    }

    /// Proactively trigger the macOS Automation TCC prompt by dispatching a
    /// harmless `activate` AppleEvent to the first running supported terminal.
    /// Without this, the user never sees the permission dialog until they
    /// actually try to send a message — and by then the relay has already
    /// silently failed. Called from the Settings → cmux Connection tab.
    ///
    /// Uses `NSAppleScript` (in-process) rather than spawning `osascript` as
    /// a subprocess. Subprocess dispatch can confuse TCC attribution on some
    /// macOS builds — the event is blamed on osascript (which already has
    /// Automation entries from unrelated apps) instead of the parent, and no
    /// prompt ever fires. In-process NSAppleScript runs inside Code Island's
    /// own code signature, so TCC reliably attributes to `com.codeisland.app`
    /// and shows the dialog on first use.
    ///
    /// Returns `(ok, detail)` — on failure, `detail` contains the raw
    /// NSAppleScriptErrorNumber so we can diagnose TCC edge cases from the
    /// UI without opening Console.
    func requestAutomationPermission() async -> (ok: Bool, detail: String) {
        // Probe order matches TerminalJumper — cmux first since it's the
        // primary relay target.
        let candidates: [(bundleId: String, label: String)] = [
            ("com.cmuxterm.app", "cmux"),
            ("com.googlecode.iterm2", "iTerm"),
            ("com.mitchellh.ghostty", "Ghostty"),
            ("com.apple.Terminal", "Terminal")
        ]
        for (bundleId, label) in candidates {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { continue }

            let source = "tell application id \"\(bundleId)\" to activate"
            let script = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            _ = script?.executeAndReturnError(&errorInfo)

            if errorInfo == nil {
                return (true, "\(L10n.requestAutomationPrompted) (\(label))")
            }
            // Surface the raw error so we can tell "prompt shown, user denied"
            // (err -1743) from "script parse failure" from "target not
            // running" — they all need different fixes.
            let errNum = (errorInfo?["NSAppleScriptErrorNumber"] as? Int) ?? 0
            let errMsg = (errorInfo?["NSAppleScriptErrorMessage"] as? String) ?? "?"
            return (false, "\(L10n.requestAutomationDenied) (\(label) · err=\(errNum) · \(errMsg))")
        }
        return (false, L10n.requestAutomationNoTerminal)
    }

    /// Send a fixed diagnostic probe line to the first detected cmux target.
    /// Returns a human-readable result string that the UI can show directly.
    func testSendDiagnostic() async -> (ok: Bool, detail: String) {
        let probe = await probeConnection()
        guard probe.cmuxBinaryInstalled else {
            return (false, L10n.cmuxBinaryMissing)
        }
        guard let (wsId, surfId) = probe.testTarget else {
            return (false, L10n.testSendNoTarget)
        }
        // Deliberately empty-ish payload that won't spam the user's terminal:
        // a single `#` comment line which most shells treat as a no-op.
        var args = ["send", "--workspace", wsId]
        if let surfId { args += ["--surface", surfId] }
        args += ["--", "# CodeIsland probe\r"]
        let result = await cmuxRun(args)
        if result != nil {
            return (true, "\(L10n.testSendSuccess) — ws=\(wsId.prefix(8)) surf=\(surfId?.prefix(8).description ?? "-")")
        } else {
            return (false, L10n.testSendFailed)
        }
    }

    // MARK: - Relay entry points

    /// Send a text message to the terminal running the given session.
    func sendText(_ text: String, to session: SessionState) async -> Bool {
        let termApp = session.terminalApp?.lowercased() ?? ""

        // Try cmux first (most precise)
        if FileManager.default.isExecutableFile(atPath: cmuxPath) {
            if await sendViaCmux(text, session: session) {
                return true
            }
        }

        // Try AppleScript for known terminals
        if termApp.contains("iterm") {
            return await sendViaAppleScript(text, script: """
                tell application "iTerm2"
                    tell current session of current tab of current window
                        write text "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
                    end tell
                end tell
                """)
        }

        if termApp.contains("ghostty") {
            // Ghostty: use keystroke via System Events
            return await sendViaAppleScript(text, script: """
                tell application "Ghostty" to activate
                delay 0.3
                tell application "System Events"
                    keystroke "\(text.replacingOccurrences(of: "\"", with: "\\\""))"
                    key code 36
                end tell
                """)
        }

        if termApp.contains("terminal") && !termApp.contains("wez") {
            return await sendViaAppleScript(text, script: """
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
        guard let (wsId, surfId) = await findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid),
              let surfId else {
            Self.logger.warning("sendControlKey: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return false
        }
        let result = await cmuxRun(["send-key", "--workspace", wsId, "--surface", surfId, "--", key])
        Self.logger.info("Sent key '\(key)' to cmux (ws=\(wsId.prefix(8)) surf=\(surfId.prefix(8))) result=\(result != nil)")
        return result != nil
    }

    /// Snapshot the current cmux surface (visible pane + scrollback) as plain text.
    /// Used by the phone's "read screen" button so the user can check terminal state
    /// without injecting any input. Returns nil if the surface can't be located.
    func readScreen(claudeUuid: String, cwd: String? = nil, livePid: Int? = nil, lines: Int = 500) async -> String? {
        guard let (wsId, surfId) = await findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid),
              let surfId else {
            Self.logger.warning("readScreen: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return nil
        }
        let raw = await cmuxRun(["read-screen", "--workspace", wsId, "--surface", surfId, "--scrollback", "--lines", "\(lines)"]) ?? ""
        let split = raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let cleaned = cleanupOutputLines(split)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Capture the terminal output that appeared *after* a slash command was sent.
    /// Snapshots the pane before, sends the command, waits for output to settle,
    /// then diffs the two snapshots and returns only the new lines.
    ///
    /// Returns nil if we can't locate the cmux surface for this Claude session or
    /// capture fails.
    func sendSlashCommandAndCaptureOutput(_ command: String, claudeUuid: String, cwd: String? = nil, livePid: Int? = nil, settleMs: UInt64 = 1500) async -> String? {
        guard let (wsId, surfId) = await findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid),
              let surfId else {
            Self.logger.warning("captureOutput: no cmux target for uuid=\(claudeUuid.prefix(8))")
            return nil
        }

        // Pre-snapshot
        let before = await cmuxRun(["read-screen", "--workspace", wsId, "--surface", surfId, "--scrollback", "--lines", "500"]) ?? ""

        // Send the command
        let escaped = command.replacingOccurrences(of: "\n", with: "\r")
        _ = await cmuxRun(["send", "--workspace", wsId, "--surface", surfId, "--", "\(escaped)\r"])

        // Wait for the CLI to render its response
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)

        // Post-snapshot
        let after = await cmuxRun(["read-screen", "--workspace", wsId, "--surface", surfId, "--scrollback", "--lines", "500"]) ?? ""

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
        guard let (wsId, surfId) = await findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid) else {
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
        _ = await cmuxRun(["focus-panel", "--panel", surfId, "--workspace", wsId])

        // 2. Bring cmux.app to the foreground. AppleScript is more reliable than
        //    NSRunningApplication here (the latter sometimes fails to locate cmux).
        _ = await runOsascript(#"tell application id "com.cmuxterm.app" to activate"#)

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
            if !(await postCmdVViaAppleScript()) {
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
        _ = await cmuxRun(["send", "--workspace", wsId, "--surface", surfId, "--", trailing])

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
    nonisolated private func postCmdVViaAppleScript() async -> Bool {
        return await runOsascript(#"tell application "System Events" to keystroke "v" using {command down}"#)
    }

    /// Run an AppleScript snippet via osascript with a hard timeout. Silently
    /// returns `false` on TCC denial, hang, or non-zero exit — callers are
    /// expected to surface permission problems via the Settings UI, not this
    /// return value alone.
    @discardableResult
    nonisolated private func runOsascript(_ script: String) async -> Bool {
        let (_, ok) = await runShellWithTimeout("/usr/bin/osascript", ["-e", script], timeout: 5.0)
        return ok
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
        guard let (wsId, surfId) = await findCmuxTarget(claudeUuid: claudeUuid, cwd: cwd, livePid: livePid) else {
            Self.logger.warning("No cmux-hosted claude process for uuid=\(claudeUuid.prefix(8)) cwd=\(cwd ?? "nil") pid=\(livePid?.description ?? "nil") — session is orphaned, in a non-cmux terminal, or on another machine")
            return false
        }

        let escaped = text.replacingOccurrences(of: "\n", with: "\r")
        var args = ["send"]
        args += ["--workspace", wsId]
        if let surfId { args += ["--surface", surfId] }
        args += ["--", "\(escaped)\r"]
        guard await cmuxRun(args) != nil else {
            Self.logger.error("cmux send failed for workspace=\(wsId)")
            return false
        }
        Self.logger.info("Sent message via cmux (workspace=\(wsId.prefix(8)) surface=\(surfId?.prefix(8).description ?? "-"))")
        return true
    }

    /// Top-level resolver. Tries the most reliable identity first (live PID
    /// from CodeIsland's hook tracking), then falls back to argv match, then
    /// to cwd-scoped scanning.
    nonisolated private func findCmuxTarget(claudeUuid: String, cwd: String?, livePid: Int?) async -> (workspaceId: String, surfaceId: String?)? {
        // Pass 0: hook-recorded live pid. Most reliable — `os.getppid()` from
        // the python hook script gives us the exact Claude process.
        if let livePid, let target = await readCmuxIDs(forPid: livePid) {
            return target
        }
        // Falls back to argv-then-cwd inside the existing helper.
        return await findCmuxTargetForClaudeSession(uuid: claudeUuid, cwd: cwd)
    }

    /// Look up a cmux workspace+surface for the live Claude process backing the
    /// given session UUID. Tries argv match first (works when JSONL id == live
    /// id), falls back to cwd-scoped scan when the conversation was resumed
    /// (rotating live id) or when CodeIsland is reporting the JSONL filename.
    nonisolated private func findCmuxTargetForClaudeSession(uuid: String, cwd: String?) async -> (workspaceId: String, surfaceId: String?)? {
        let candidates = await listClaudeProcesses()
        if candidates.isEmpty { return nil }

        // Pass 1: exact argv match by --session-id
        if let exact = candidates.first(where: { $0.sessionId == uuid }),
           let target = await readCmuxIDs(forPid: exact.pid) {
            return target
        }

        // Pass 2: cwd-scoped fallback. Restrict to processes whose cwd matches
        // the session's cwd AND who have CMUX env vars (i.e. are inside a cmux
        // pane — no point routing to an iTerm window we can't drive).
        guard let cwd, !cwd.isEmpty else {
            DebugLogger.log("TerminalWriter", "findCmuxTarget: argv miss for uuid=\(uuid.prefix(8)) and no cwd to fall back on")
            return nil
        }

        var cwdMatched: [(pid: Int, target: (workspaceId: String, surfaceId: String?))] = []
        for proc in candidates where proc.cwd == cwd {
            if let target = await readCmuxIDs(forPid: proc.pid) {
                cwdMatched.append((proc.pid, target))
            }
        }

        guard !cwdMatched.isEmpty else {
            DebugLogger.log("TerminalWriter", "findCmuxTarget: no cwd-matching cmux-hosted claude in \(cwd)")
            return nil
        }

        if cwdMatched.count > 1 {
            DebugLogger.log("TerminalWriter", "findCmuxTarget: \(cwdMatched.count) candidates in cwd=\(cwd) — picking highest pid as heuristic")
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
    nonisolated private func listClaudeProcesses() async -> [ClaudeProcessInfo] {
        let (out, ok) = await runShellWithTimeout("/bin/ps", ["-Ax", "-o", "pid=,command="], timeout: 3.0)
        guard ok, let text = out else { return [] }

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
            let cwd = await lsofCwd(pid: pid)
            processes.append(ClaudeProcessInfo(pid: pid, sessionId: sid, cwd: cwd))
        }
        return processes
    }

    nonisolated private func lsofCwd(pid: Int) async -> String? {
        let (out, ok) = await runShellWithTimeout("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"], timeout: 2.0)
        guard ok, let text = out else { return nil }
        // Output format (-Fn): "p<pid>\nf<cwd>\nn<path>\n"
        for line in text.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Read CMUX_WORKSPACE_ID and CMUX_SURFACE_ID env vars from a running pid.
    /// Returns nil if the pid is gone, has no CMUX_WORKSPACE_ID, or ps -E fails.
    nonisolated private func readCmuxIDs(forPid pid: Int) async -> (workspaceId: String, surfaceId: String?)? {
        let (out, ok) = await runShellWithTimeout("/bin/ps", ["-E", "-p", "\(pid)", "-o", "command="], timeout: 2.0)
        guard ok, let envLine = out else { return nil }

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
        return (wsId, surfId)
    }

    // MARK: - cmux

    private func sendViaCmux(_ text: String, session: SessionState) async -> Bool {
        let dirName = URL(fileURLWithPath: session.cwd).lastPathComponent
        let sid = String(session.sessionId.prefix(8))

        // Find workspace
        guard let wsOutput = await cmuxRun(["list-workspaces"]) else { return false }

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
            guard let surfOutput = await cmuxRun(["list-pane-surfaces", "--workspace", wsRef]) else { continue }
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
        _ = await cmuxRun(["send", "--workspace", wsRef, "--", "\(escaped)\r"])
        Self.logger.info("Sent message to cmux workspace \(wsRef, privacy: .public)")
        return true
    }

    /// Invoke the cmux CLI with a hard timeout. Returns nil on launch failure,
    /// non-zero exit, or timeout. All cmux calls MUST go through here — the
    /// previous raw Process.waitUntilExit could freeze the main thread when
    /// cmux became unresponsive (main cause of the "CodeIsland 卡死" reports).
    nonisolated private func cmuxRun(_ args: [String]) async -> String? {
        let (out, ok) = await runShellWithTimeout(cmuxPath, args, timeout: 5.0)
        return ok ? out : nil
    }

    // MARK: - AppleScript

    /// Run an AppleScript snippet via osascript with a hard timeout. Like
    /// `cmuxRun`, this used to be a synchronous waitUntilExit which would
    /// freeze the UI if the user had not granted the Automation permission
    /// (TCC would block the AppleEvent dispatch indefinitely on some builds).
    private func sendViaAppleScript(_ text: String, script: String) async -> Bool {
        let (_, ok) = await runShellWithTimeout("/usr/bin/osascript", ["-e", script], timeout: 5.0)
        if ok {
            Self.logger.info("Sent message via AppleScript")
        }
        return ok
    }
}

// MARK: - cmuxPath hoist for nonisolated access

/// The nonisolated helpers above need access to `cmuxPath`, which is a
/// stored instance property. Since cmuxPath is a constant, expose it via
/// a nonisolated computed accessor.
extension TerminalWriter {
    nonisolated fileprivate var cmuxPath: String { "/Applications/cmux.app/Contents/Resources/bin/cmux" }
}
