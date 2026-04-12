//
//  SyncManager.swift
//  ClaudeIsland
//
//  Top-level coordinator for CodeLight Server sync.
//  Manages connection lifecycle, message relay, and RPC execution.
//

import Combine
import Foundation
import os.log

/// Coordinates all CodeLight Server sync functionality.
/// Initialize once at app startup, connects/disconnects based on configuration.
@MainActor
final class SyncManager: ObservableObject {

    static let shared = SyncManager()
    static let logger = Logger(subsystem: "com.codeisland", category: "SyncManager")

    @Published private(set) var isEnabled = false
    @Published private(set) var connectionState: ServerConnectionState = .disconnected

    private var connection: ServerConnection?
    private var relay: MessageRelay?
    private var rpcExecutor: RPCExecutor?
    private var capabilityTimer: Timer?
    private var projectUploadTimer: Timer?

    /// Re-publishes the underlying ServerConnection.shortCode so SwiftUI views
    /// (PairPhoneView) can observe it via SyncManager directly.
    @Published private(set) var shortCode: String?

    /// The server URL to connect to. Stored in UserDefaults.
    var serverUrl: String? {
        get { UserDefaults.standard.string(forKey: "codelight-server-url") }
        set {
            UserDefaults.standard.set(newValue, forKey: "codelight-server-url")
            if let url = newValue, !url.isEmpty {
                Task { await connectToServer(url: url) }
            } else {
                disconnectFromServer()
            }
        }
    }

    private init() {
        // No hardcoded server URL on fresh install — the user must configure
        // their own CodeLight server URL in Settings before pairing. This
        // avoids accidentally routing every user's sessions through the
        // author's personal host.
        if let url = serverUrl, !url.isEmpty {
            Task { await connectToServer(url: url) }
        }
    }

    // MARK: - Connection Lifecycle

    func connectToServer(url: String) async {
        disconnectFromServer()

        let conn = ServerConnection(serverUrl: url)
        self.connection = conn

        do {
            try await conn.authenticate()
            conn.connect()

            // Handle messages from phone → type into terminal
            conn.onUserMessage = { [weak self] serverSessionId, messageText, claudeUuid, cwd in
                Task { @MainActor in
                    await self?.handlePhoneMessage(serverSessionId: serverSessionId, text: messageText, claudeUuid: claudeUuid, cwd: cwd)
                }
            }

            // Phone unpaired this Mac → log + future: clean up local state
            conn.onLinkRemoved = { [weak self] sourceDeviceId in
                Task { @MainActor in
                    Self.logger.info("iPhone \(sourceDeviceId.prefix(8), privacy: .public) unpaired from this Mac")
                    self?.objectWillChange.send()
                }
            }

            // Phone requested a remote session launch → spawn cmux subprocess
            conn.onSessionLaunch = { presetId, projectPath, requestedBy in
                Task { @MainActor in
                    let ok = LaunchService.shared.launch(presetId: presetId, projectPath: projectPath)
                    Self.logger.info("session-launch from \(requestedBy.prefix(8), privacy: .public): \(ok ? "ok" : "failed")")
                }
            }

            // Wait for socket to actually connect before starting relay
            let relay = MessageRelay(connection: conn)
            self.relay = relay
            let rpc = RPCExecutor()
            self.rpcExecutor = rpc

            // Restore persisted session mappings before starting relay
            let savedMappings = await MessageOutbox.shared.allMappings
            for (localId, serverId) in savedMappings {
                relay.restoreServerSessionId(localId: localId, serverId: serverId)
            }

            // Delay relay start to give socket time to connect
            Task { @MainActor in
                // Wait up to 5 seconds for socket connection
                for _ in 0..<50 {
                    if conn.isConnected { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                if conn.isConnected {
                    relay.startRelaying()
                    relay.scheduleOutboxDrain()
                    Self.logger.info("Relay started after socket connected")
                } else {
                    Self.logger.warning("Socket did not connect in time, starting relay anyway")
                    relay.startRelaying()
                }
            }

            isEnabled = true
            connectionState = .connected
            Self.logger.info("Sync enabled with \(url)")

            // Register this Mac with the server (lazy-allocates permanent shortCode).
            let macName = Host.current().localizedName ?? "Mac"
            await conn.registerDevice(name: macName, kind: "mac")
            self.shortCode = conn.shortCode

            // Push current preset list to the server so the phone can browse them.
            await uploadPresets()

            // Scan local capabilities and push to server so the phone can browse
            // available slash commands, skills, and MCP servers. Then refresh every
            // 10 minutes in case the user installs new plugins.
            scheduleCapabilityUploads()

            // Periodically upload known project paths so the phone can pick from
            // recent projects when launching a session.
            scheduleProjectUploads()
        } catch {
            connectionState = .error(error.localizedDescription)
            Self.logger.error("Sync connection failed: \(error)")
        }
    }

    /// Handle a user message received from the phone — type it into the matching terminal.
    /// Tries the locally tracked SessionState first; falls back to direct cmux lookup
    /// using the Claude UUID/path the server provides (so dormant sessions still work).
    private func handlePhoneMessage(serverSessionId: String, text: String, claudeUuid: String?, cwd: String?) async {
        let sessions = await SessionStore.shared.currentSessions()
        let localId = self.relay?.localSessionId(forServerId: serverSessionId)
        let preview = String(text.prefix(200))
        Self.logger.info("handlePhoneMessage: serverId=\(serverSessionId, privacy: .public) localId=\(localId ?? "nil", privacy: .public) tag=\(claudeUuid ?? "nil", privacy: .public) cwd=\(cwd ?? "nil", privacy: .public) raw=\(preview, privacy: .public)")

        // Resolve target identity ONCE up front and share across all paths
        // (control key / image / slash command / text). When SessionStore is
        // tracking this conversation, lift the live Claude PID off it — that's
        // the single most reliable identity for cmux routing because it was
        // captured from `os.getppid()` inside the hook script. Falls back to
        // server-provided UUID + cwd when not tracked.
        let trackedSession = localId.flatMap { id in sessions.first(where: { $0.sessionId == id }) }
        let targetUuid: String? = trackedSession?.sessionId ?? claudeUuid
        let livePid: Int? = trackedSession?.pid

        // Parse the message content — it may be plain text OR a JSON envelope with images.
        let (parsedText, imageBlobIds) = parseMessagePayload(text)

        // Control-key path: phone explicitly sends `{type:"key", key:"escape"}` etc.
        // These don't go through stdin — we fire them directly at the cmux surface.
        if let controlKey = parseControlKey(text) {
            if let uuid = targetUuid {
                let ok = await TerminalWriter.shared.sendControlKey(controlKey, claudeUuid: uuid, cwd: cwd, livePid: livePid)
                Self.logger.info("Phone control key '\(controlKey, privacy: .public)' (uuid=\(uuid.prefix(8), privacy: .public) pid=\(livePid?.description ?? "nil", privacy: .public)) → \(ok ? "success" : "failed")")
            } else {
                Self.logger.warning("Control key dropped: no target uuid")
            }
            return
        }
        Self.logger.info("parsed: text=\(parsedText.prefix(80), privacy: .public) blobCount=\(imageBlobIds.count)")

        // Image path: download blobs and paste via NSPasteboard + Cmd+V
        if !imageBlobIds.isEmpty {
            guard let targetUuid, let connection = self.connection else {
                Self.logger.warning("Phone image message dropped: no target uuid")
                return
            }
            var images: [Data] = []
            for blobId in imageBlobIds {
                do {
                    let (data, _) = try await connection.downloadBlob(blobId: blobId)
                    images.append(data)
                    // Ack so the server can delete the blob immediately
                    connection.sendBlobConsumed(blobId: blobId)
                } catch {
                    Self.logger.error("Failed to download blob \(blobId): \(error.localizedDescription)")
                }
            }
            if images.isEmpty {
                Self.logger.warning("No images could be downloaded — falling back to text-only")
            } else {
                let ok = await TerminalWriter.shared.sendImagesAndText(images: images, text: parsedText, claudeUuid: targetUuid, cwd: cwd, livePid: livePid)
                if ok { await MessageOutbox.shared.recordInjection(claudeUuid: targetUuid, text: parsedText) }
                Self.logger.info("Phone message with \(images.count) image(s) → terminal: \(ok ? "success" : "failed")")
                return
            }
        }

        // Slash-command path: Claude's built-in commands (/usage, /cost, /model, etc.)
        // don't emit hook events, so their output never hits the JSONL and the phone
        // wouldn't otherwise see the response. We snapshot the pane, inject the
        // command, wait, snapshot again, diff, and ship the new lines back as a
        // synthetic terminal_output message.
        if parsedText.hasPrefix("/"), let targetUuid {
            let output = await TerminalWriter.shared.sendSlashCommandAndCaptureOutput(parsedText, claudeUuid: targetUuid, cwd: cwd, livePid: livePid)
            await MessageOutbox.shared.recordInjection(claudeUuid: targetUuid, text: parsedText)
            if let output, !output.isEmpty {
                await sendTerminalOutputMessage(sessionId: serverSessionId, command: parsedText, output: output)
            }
            Self.logger.info("Phone slash command /\(parsedText.dropFirst().prefix(20)) → captured=\(output != nil)")
            return
        }

        // Plain text path — uses the unified target identity computed at the top.
        if let uuid = targetUuid {
            let sent = await TerminalWriter.shared.sendTextDirect(
                parsedText,
                claudeUuid: uuid,
                cwd: cwd,
                livePid: livePid
            )
            if sent { await MessageOutbox.shared.recordInjection(claudeUuid: uuid, text: parsedText) }
            Self.logger.info("Phone message → terminal (uuid=\(uuid.prefix(8), privacy: .public) pid=\(livePid?.description ?? "nil", privacy: .public)): \(sent ? "success" : "failed")")
            return
        }

        Self.logger.warning("Phone message dropped: no local session and no uuid for serverId=\(serverSessionId, privacy: .public)")
    }

    // MARK: - Capability Upload

    /// Scan the local filesystem for capabilities and push to the server now, then
    /// refresh every 10 minutes. Passes the most recent session's cwd so project-local
    /// commands/skills get included.
    private func scheduleCapabilityUploads() {
        capabilityTimer?.invalidate()
        Task { [weak self] in await self?.uploadCapabilitiesNow() }
        capabilityTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.uploadCapabilitiesNow() }
        }
    }

    private func uploadCapabilitiesNow() async {
        guard let connection = self.connection else { return }
        // Pick a project path from the most recent session (if any) so project-local
        // commands/skills get scanned too.
        let sessions = await SessionStore.shared.currentSessions()
        let projectPath = sessions.first?.cwd
        let snapshot = CapabilityScanner.scan(projectPath: projectPath)
        await connection.uploadCapabilities(snapshot)
        Self.logger.info("Uploaded capability snapshot (project=\(projectPath ?? "-"))")
    }

    // MARK: - Preset / Project Upload

    /// Push the current preset list to the server. Called on connect and on every preset mutation.
    func uploadPresets() async {
        guard let connection = self.connection else { return }
        let payload = PresetStore.shared.presets.map { $0.serverPayload }
        await connection.uploadPresets(payload)
        Self.logger.info("Uploaded \(payload.count) presets")
    }

    /// Schedule periodic uploads of known project paths (every 5 minutes).
    private func scheduleProjectUploads() {
        projectUploadTimer?.invalidate()
        Task { [weak self] in await self?.uploadProjectsNow() }
        projectUploadTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.uploadProjectsNow() }
        }
    }

    private func uploadProjectsNow() async {
        guard let connection = self.connection else { return }
        let sessions = await SessionStore.shared.currentSessions()

        // Dedupe by cwd, prefer the entry whose projectName is non-empty.
        var byPath: [String: String] = [:]
        for s in sessions {
            let cwd = s.cwd
            guard !cwd.isEmpty else { continue }
            let name = s.projectName.isEmpty ? URL(fileURLWithPath: cwd).lastPathComponent : s.projectName
            byPath[cwd] = name
        }

        let projects = byPath.map { (path, name) in
            ["path": path, "name": name]
        }
        guard !projects.isEmpty else { return }

        await connection.uploadProjects(projects)
        Self.logger.info("Uploaded \(projects.count) project paths")
    }

    /// Emit a synthetic `terminal_output` message on behalf of the user's session,
    /// so the phone can render the captured response to a slash command.
    private func sendTerminalOutputMessage(sessionId: String, command: String, output: String) async {
        guard let connection = self.connection, connection.isConnected else { return }
        let payload: [String: Any] = [
            "type": "terminal_output",
            "command": command,
            "text": output,
            "timestamp": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let localId = "term-\(UUID().uuidString)"
        connection.sendMessage(sessionId: sessionId, content: json, localId: localId)
    }

    /// Extract a control key name from a message payload of shape `{type:"key", key:"escape"}`.
    /// Returns nil if the message isn't a control-key envelope.
    private func parseControlKey(_ content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (dict["type"] as? String) == "key",
              let key = dict["key"] as? String
        else { return nil }
        return key
    }

    /// Extract `text` and `images[].blobId` from a message content string. If the content
    /// isn't a JSON object, treat it as plain text with no images.
    private func parseMessagePayload(_ content: String) -> (text: String, blobIds: [String]) {
        guard let data = content.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (content, [])
        }
        let text = dict["text"] as? String ?? ""
        var blobIds: [String] = []
        if let images = dict["images"] as? [[String: Any]] {
            blobIds = images.compactMap { $0["blobId"] as? String }
        }
        return (text, blobIds)
    }

    func disconnectFromServer() {
        relay?.stopRelaying()
        connection?.disconnect()
        connection = nil
        relay = nil
        rpcExecutor = nil
        capabilityTimer?.invalidate()
        capabilityTimer = nil
        projectUploadTimer?.invalidate()
        projectUploadTimer = nil
        shortCode = nil
        isEnabled = false
        connectionState = .disconnected
    }

    /// Called when a QR code is scanned with server details
    func handlePairingQR(serverUrl: String, tempPublicKey: String, deviceName: String) async {
        UserDefaults.standard.set(serverUrl, forKey: "codelight-server-url")
        await connectToServer(url: serverUrl)
        Self.logger.info("Paired with \(deviceName) via QR")
    }
}
