//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch
//

import Foundation
import os.log

struct HookInstaller {
    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "HookInstaller")

    /// Install hook script and update settings.json on app launch
    static func installIfNeeded() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        // Use direct path lookup instead of Bundle.main.url to avoid development build issues
        var bundled: URL?
        if let resourcePath = Bundle.main.resourcePath {
            let url = URL(fileURLWithPath: resourcePath).appendingPathComponent("codeisland-state.py")
            if FileManager.default.fileExists(atPath: url.path) {
                bundled = url
            }
        }

        if let bundled = bundled {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
            Self.logger.info("Installed codeisland-state.py from bundle at \(bundled.path)")
        } else {
            Self.logger.error("Could not find codeisland-state.py in app bundle at \(Bundle.main.resourcePath ?? "nil")")
        }

        updateSettings(at: settings)
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) ~/.claude/hooks/codeisland-state.py"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("codeisland-state.py")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        // First verify the Python script actually exists on disk
        guard FileManager.default.fileExists(atPath: pythonScript.path) else {
            return false
        }

        // Then verify settings.json contains our hook entry
        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("codeisland-state.py") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("codeisland-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("codeisland-state.py")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    // MARK: - Remote SSH Deployment

    /// Validates a hostname or IP address for SSRF prevention.
    /// Returns nil if valid, or an error message if invalid.
    private static func validateHost(_ host: String) -> String? {
        // Allow IP addresses (IPv4)
        let ipv4Pattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
        // Allow hostnames (letters, digits, dots, hyphens)
        let hostnamePattern = #"^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9.-]{0,61}[a-zA-Z0-9])?)*$"#

        if let ipv4Regex = try? NSRegularExpression(pattern: ipv4Pattern),
           ipv4Regex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil {
            // Validate each octet is 0-255
            let octets = host.split(separator: ".").compactMap { Int($0) }
            if octets.count == 4 && octets.allSatisfy({ $0 >= 0 && $0 <= 255 }) {
                return nil  // Valid IPv4
            }
        }

        if let hostnameRegex = try? NSRegularExpression(pattern: hostnamePattern),
           hostnameRegex.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil {
            return nil  // Valid hostname
        }

        return "Invalid host: \(host). Only IP addresses or hostnames are allowed."
    }

    /// Deploy relay and hook scripts to a remote SSH host.
    /// Returns error message on failure, nil on success.
    static func deployToSSHHost(
        host: SSHHost,
        macIP: String,
        psk: String,
        sshKeyPath: String?
    ) async -> String? {
        // Validate host to prevent SSRF
        if let error = validateHost(host.host) {
            return error
        }

        // Use direct path lookup instead of Bundle.main.url to avoid development build issues
        var relayScript: URL?
        var hookScript: URL?
        if let resourcePath = Bundle.main.resourcePath {
            let resURL = URL(fileURLWithPath: resourcePath)
            let relayURL = resURL.appendingPathComponent("codeisland-ssh-relay.py")
            let hookURL = resURL.appendingPathComponent("codeisland-state.py")
            if FileManager.default.fileExists(atPath: relayURL.path) { relayScript = relayURL }
            if FileManager.default.fileExists(atPath: hookURL.path) { hookScript = hookURL }
        }

        guard let relayPath = relayScript, let hookPath = hookScript else {
            return "Could not find bundled Python scripts"
        }

        // Build SSH args
        var scpArgs = ["-o", "BatchMode=yes"]
        var sshArgs = ["-o", "BatchMode=yes"]

        if let keyPath = sshKeyPath ?? host.sshKeyPath {
            scpArgs += ["-i", keyPath]
            sshArgs += ["-i", keyPath]
        }

        if host.port != 22 {
            scpArgs += ["-P", "\(host.port)"]
            sshArgs += ["-p", "\(host.port)"]
        }

        let remoteDir = "~/.codeisland"
        let remoteUserHost = "\(host.user)@\(host.host)"

        // 1. Create remote directory
        let mkdirCmd = "mkdir -p \(remoteDir)"
        let (mkdirSuccess, mkdirStderr) = runSSHCommandWithOutput(args: sshArgs + [remoteUserHost, mkdirCmd], timeout: 30)
        if mkdirSuccess == nil {
            return "Failed to create remote directory on \(host.host): \(mkdirStderr ?? "unknown error")"
        }

        // 2. SCP relay script
        let (scpRelaySuccess, scpRelayStderr) = runSCPFile(
            localPath: relayPath.path,
            remotePath: "\(remoteUserHost):\(remoteDir)/codeisland-ssh-relay.py",
            args: scpArgs
        )
        if !scpRelaySuccess {
            return "Failed to upload relay script to \(host.host): \(scpRelayStderr ?? "unknown error")"
        }

        // 3. SCP hook script to ~/.claude/hooks/ (same path as local install)
        let (scpHookSuccess, scpHookStderr) = runSCPFile(
            localPath: hookPath.path,
            remotePath: "\(remoteUserHost):~/.claude/hooks/codeisland-state.py",
            args: scpArgs
        )
        if !scpHookSuccess {
            return "Failed to upload hook script to \(host.host): \(scpHookStderr ?? "unknown error")"
        }

        // 4. Make scripts executable
        let chmodCmd = "chmod +x \(remoteDir)/codeisland-ssh-relay.py ~/.claude/hooks/codeisland-state.py"
        let (chmodSuccess, chmodStderr) = runSSHCommandWithOutput(args: sshArgs + [remoteUserHost, chmodCmd], timeout: 30)
        if chmodSuccess == nil {
            return "Failed to set permissions on \(host.host): \(chmodStderr ?? "unknown error")"
        }

        // 5. Verify Python on remote
        let pythonCheck = "which python3 || which python"
        let (pythonResult, pythonStderr) = runSSHCommandWithOutput(args: sshArgs + [remoteUserHost, pythonCheck], timeout: 30)
        guard pythonResult != nil else {
            return "Python not found on \(host.host): \(pythonStderr ?? "command failed")"
        }

        // 6. Generate config file using base64 to avoid shell injection.
        // Use compact single-line format (no heredoc) to avoid embedded newlines in base64.
        // For direct mode: relay connects directly to Mac IP (same LAN or public IP)
        // For tunnel mode: relay connects to localhost through SSH tunnel
        let relayHost = (host.connectionMode == .direct) ? macIP : "localhost"
        let configLines = [
            "RELAY_HOST=\(relayHost)",
            "RELAY_PORT=\(host.localPort)",
            "PSK=\(psk)"
        ]
        let configContent = configLines.joined(separator: "\n")

        let configBase64 = configContent.data(using: .utf8)!.base64EncodedString()
        let remoteConfig = "printf '\(configBase64)' | base64 -d > \(remoteDir)/relay.conf"

        // 7. Generate startup script using base64 to avoid shell injection
        let startupScript = """
        #!/bin/bash
        cd \(remoteDir)
        # Kill any existing relay processes
        pkill -f codeisland-ssh-relay.py || true
        sleep 1
        nohup ./codeisland-ssh-relay.py > \(remoteDir)/relay.log 2>&1 &
        echo "Relay started with PID $!"
        """

        let startupBase64 = startupScript.data(using: .utf8)!.base64EncodedString()
        let remoteStart = "\(remoteConfig) && printf '\(startupBase64)' | base64 -d > \(remoteDir)/start-relay.sh && chmod +x \(remoteDir)/start-relay.sh && \(remoteDir)/start-relay.sh"

        let (startSuccess, startStderr) = runSSHCommandWithOutput(args: sshArgs + [remoteUserHost, remoteStart], timeout: 30)
        if startSuccess == nil {
            return "Failed to start relay on \(host.host): \(startStderr ?? "unknown error")"
        }

        return nil
    }

    /// Stop the relay on a remote SSH host.
    static func stopRemoteRelay(host: SSHHost, sshKeyPath: String?) async -> Bool {
        var sshArgs = ["-o", "StrictHostKeyChecking=accept-new", "-o", "BatchMode=yes"]

        if let keyPath = sshKeyPath ?? host.sshKeyPath {
            sshArgs += ["-i", keyPath]
        }

        if host.port != 22 {
            sshArgs += ["-p", "\(host.port)"]
        }

        let remoteUserHost = "\(host.user)@\(host.host)"
        let stopCmd = "pkill -f codeisland-ssh-relay.py || true"

        return runSSHCommand(args: sshArgs + [remoteUserHost, stopCmd], timeout: 30)
    }

    // MARK: - SSH Helpers

    private static func runSSHCommand(args: [String], timeout: Int) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + .seconds(timeout))
            timer.setEventHandler {
                if p.isRunning { p.terminate() }
            }
            timer.resume()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runSSHCommandWithOutput(args: [String], timeout: Int) -> (stdout: String?, stderr: String?) {
        let p = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = args
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        do {
            try p.run()
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + .seconds(timeout))
            timer.setEventHandler {
                if p.isRunning { p.terminate() }
            }
            timer.resume()
            p.waitUntilExit()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)
            let stderr = String(data: stderrData, encoding: .utf8)
            guard p.terminationStatus == 0 else { return (nil, stderr) }
            return (stdout, stderr)
        } catch let error as NSError {
            return (nil, "Process error: \(error.localizedDescription)")
        }
    }

    private static func runSCPFile(localPath: String, remotePath: String, args: [String]) -> (success: Bool, stderr: String?) {
        let p = Process()
        let stderrPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        p.arguments = args + [localPath, remotePath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = stderrPipe
        do {
            try p.run()
            p.waitUntilExit()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8)
            return (p.terminationStatus == 0, stderr)
        } catch let error as NSError {
            return (false, "Process error: \(error.localizedDescription)")
        }
    }
}
