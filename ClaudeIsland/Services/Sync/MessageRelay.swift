//
//  MessageRelay.swift
//  ClaudeIsland
//
//  Bridges SessionStore events to CodeLight Server.
//  Subscribes to session state changes and relays them upstream.
//

import Combine
import Foundation
import os.log

/// Relays session events from SessionStore to the CodeLight Server.
@MainActor
final class MessageRelay {

    static let logger = Logger(subsystem: "com.codeisland", category: "MessageRelay")

    private let connection: ServerConnection
    private var cancellables = Set<AnyCancellable>()
    private var aliveTimers: [String: Timer] = [:]
    private var knownSessionIds = Set<String>()

    /// Track how many chat items we've already synced per session
    private var syncedItemCounts: [String: Int] = [:]

    /// Last serialized content sent to server, keyed by session+item id.
    /// Used to detect tool status mutations (running→success) that need re-sync.
    private var syncedItemContents: [String: [String: String]] = [:]

    /// Map local sessionId → server session id
    private var serverSessionIds: [String: String] = [:]

    /// Track last sent phase per session to avoid duplicate updates
    private var lastSentPhase: [String: String] = [:]
    private var lastSentTool: [String: String] = [:]
    private var lastSentTitle: [String: String] = [:]

    /// Reverse lookup: server session id → local session id
    func localSessionId(forServerId serverId: String) -> String? {
        return serverSessionIds.first(where: { $0.value == serverId })?.key
    }

    init(connection: ServerConnection) {
        self.connection = connection
    }

    /// Start relaying session events to the server.
    func startRelaying() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.handleSessionsUpdate(sessions)
            }
            .store(in: &cancellables)

        Self.logger.info("Message relay started")
    }

    func stopRelaying() {
        cancellables.removeAll()
        aliveTimers.values.forEach { $0.invalidate() }
        aliveTimers.removeAll()
        Self.logger.info("Message relay stopped")
    }

    // MARK: - Session State Processing

    private func handleSessionsUpdate(_ sessions: [SessionState]) {
        Self.logger.debug("handleSessionsUpdate: \(sessions.count) sessions, known=\(self.knownSessionIds.count), server=\(self.serverSessionIds.count)")
        for session in sessions {
            let sessionId = session.sessionId

            // New session detected — create on server
            if !knownSessionIds.contains(sessionId) {
                Self.logger.info("New session detected: \(sessionId.prefix(8))")
                knownSessionIds.insert(sessionId)
                syncedItemCounts[sessionId] = 0
                Task { await createServerSession(session) }
                startAliveTimer(for: sessionId)
            }

            // Sync phase changes
            syncPhaseChange(session)

            // Sync new chat items
            syncNewMessages(session)

            // Handle ended sessions
            if session.phase == .ended {
                if let sId = serverSessionIds[sessionId] {
                    connection.sendSessionEnd(sessionId: sId)
                }
                stopAliveTimer(for: sessionId)
                knownSessionIds.remove(sessionId)
                syncedItemCounts.removeValue(forKey: sessionId)
                syncedItemContents.removeValue(forKey: sessionId)
                serverSessionIds.removeValue(forKey: sessionId)
            }
        }

        // Clean up sessions that disappeared
        let activeIds = Set(sessions.map(\.sessionId))
        for id in knownSessionIds.subtracting(activeIds) {
            connection.sendSessionEnd(sessionId: id)
            stopAliveTimer(for: id)
            knownSessionIds.remove(id)
            syncedItemCounts.removeValue(forKey: id)
            syncedItemContents.removeValue(forKey: id)
        }
    }

    // MARK: - Phase Sync

    /// Map session phase + active tool to a phase string for the phone
    private func mappedPhase(_ session: SessionState) -> (phase: String, toolName: String?) {
        // Find currently running tool (if any)
        let runningTool = session.toolTracker.inProgress.values.first?.name

        switch session.phase {
        case .idle:
            return ("idle", nil)
        case .processing:
            // If a tool is running, show tool_running, otherwise thinking
            if let tool = runningTool {
                return ("tool_running", tool)
            }
            return ("thinking", nil)
        case .waitingForApproval(let ctx):
            return ("waiting_approval", ctx.toolName)
        case .waitingForQuestion:
            return ("waiting_question", nil)
        case .waitingForInput:
            // "Waiting for user input" = Claude just finished successfully
            return ("ended", nil)
        case .compacting:
            return ("thinking", "compacting")
        case .ended:
            return ("ended", nil)
        }
    }

    private func syncPhaseChange(_ session: SessionState) {
        let localId = session.sessionId
        guard let serverId = serverSessionIds[localId] else {
            Self.logger.debug("syncPhaseChange skipped: no serverSessionId for \(localId.prefix(8))")
            return
        }
        guard connection.isConnected else {
            Self.logger.debug("syncPhaseChange skipped: not connected")
            return
        }

        // Update session metadata when title changes (conversation summary evolves)
        let currentTitle = session.displayTitle
        if lastSentTitle[localId] != currentTitle {
            lastSentTitle[localId] = currentTitle
            let metadata: [String: Any] = [
                "path": session.cwd,
                "title": currentTitle,
                "projectName": session.projectName,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: metadata),
               let json = String(data: data, encoding: .utf8) {
                connection.updateMetadata(sessionId: serverId, metadata: json, expectedVersion: 0)
            }
        }

        let mapped = mappedPhase(session)
        let phase = mapped.phase
        let tool = mapped.toolName ?? ""

        // Extract last user message and assistant summary from chat items
        let lastUserMsg = extractLastUserMessage(session.chatItems)
        let lastAssistant = extractLastAssistantSummary(session.chatItems)

        // Include messages in dedup key so we update when messages change
        let dedupKey = "\(phase)|\(tool)|\(lastUserMsg.prefix(50))|\(lastAssistant.prefix(50))"
        if lastSentPhase[localId] == dedupKey {
            return
        }
        lastSentPhase[localId] = dedupKey

        // Build payload
        var payload: [String: Any] = [
            "type": "phase",
            "phase": phase,
            "toolName": mapped.toolName as Any,
            "timestamp": Date().timeIntervalSince1970,
        ]
        if !lastUserMsg.isEmpty {
            payload["lastUserMessage"] = String(lastUserMsg.prefix(120))
        }
        if !lastAssistant.isEmpty {
            payload["lastAssistantSummary"] = String(lastAssistant.prefix(200))
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        let phaseId = "phase-\(localId)-\(Int(Date().timeIntervalSince1970 * 1000))"
        connection.sendMessage(sessionId: serverId, content: json, localId: phaseId)
        Self.logger.info("Phase sync: \(localId.prefix(8)) → \(phase) tool=\(tool)")
    }

    /// Find the most recent user message text
    private func extractLastUserMessage(_ items: [ChatHistoryItem]) -> String {
        for item in items.reversed() {
            if case .user(let text) = item.type {
                return text
            }
        }
        return ""
    }

    /// Find the most recent assistant text response
    private func extractLastAssistantSummary(_ items: [ChatHistoryItem]) -> String {
        for item in items.reversed() {
            if case .assistant(let text) = item.type, !text.isEmpty {
                return text
            }
        }
        return ""
    }

    // MARK: - Message Sync

    private func syncNewMessages(_ session: SessionState) {
        let localId = session.sessionId
        let syncedCount = syncedItemCounts[localId] ?? 0
        let items = session.chatItems

        // Need the server session ID (created via createServerSession)
        guard let serverId = serverSessionIds[localId] else {
            Self.logger.debug("No server session ID yet for \(localId.prefix(8))...")
            return
        }

        let isConn = self.connection.isConnected
        Self.logger.info("syncNewMessages: \(localId.prefix(8))... items=\(items.count) synced=\(syncedCount) connected=\(isConn) serverId=\(serverId.prefix(8))...")

        guard connection.isConnected else {
            Self.logger.warning("Skipping sync: not connected")
            return
        }

        var contentMap = syncedItemContents[localId] ?? [:]
        var sentCount = 0

        // Sync new items (count-based)
        if items.count > syncedCount {
            let newItems = Array(items.dropFirst(syncedCount))
            syncedItemCounts[localId] = items.count

            for item in newItems {
                // Dedup: skip user messages that the phone just injected via cmux — they'd
                // otherwise round-trip back to the phone as a second copy.
                if case .user(let text) = item.type,
                   SyncManager.shared.consumePhoneInjection(claudeUuid: localId, text: text) {
                    Self.logger.info("Skipping echo of phone-injected user message")
                    continue
                }
                let content = serializeChatItem(item)
                contentMap[item.id] = content
                connection.sendMessage(sessionId: serverId, content: content, localId: item.id)
                sentCount += 1
            }
        }

        // Re-sync mutated tool items (running→success, result populated).
        // Count-based tracking misses in-place mutations, so we compare content.
        // Only tool items mutate after initial sync; other types are immutable.
        for item in items.prefix(syncedCount) {
            guard case .toolCall = item.type else { continue }
            let content = serializeChatItem(item)
            if let prev = contentMap[item.id], prev != content {
                contentMap[item.id] = content
                connection.sendMessage(sessionId: serverId, content: content, localId: item.id)
                sentCount += 1
                Self.logger.info("Re-synced mutated tool \(item.id.prefix(12))...")
            }
        }

        syncedItemContents[localId] = contentMap

        if sentCount > 0 {
            Self.logger.info("Synced \(sentCount) messages for \(localId.prefix(8))...")
        }
    }

    /// Serialize a ChatHistoryItem to a JSON string for the server.
    private func serializeChatItem(_ item: ChatHistoryItem) -> String {
        var dict: [String: Any] = [
            "id": item.id,
            "timestamp": item.timestamp.timeIntervalSince1970,
        ]

        switch item.type {
        case .user(let text):
            dict["type"] = "user"
            dict["text"] = text
        case .assistant(let text):
            dict["type"] = "assistant"
            dict["text"] = text
        case .thinking(let text):
            dict["type"] = "thinking"
            dict["text"] = text
        case .toolCall(let tool):
            dict["type"] = "tool"
            dict["toolName"] = tool.name
            dict["toolInput"] = tool.input
            dict["toolStatus"] = String(describing: tool.status)
            if let result = tool.result {
                dict["toolResult"] = String(result.prefix(2000)) // Truncate large results
            }
        case .interrupted:
            dict["type"] = "interrupted"
            dict["text"] = "[Interrupted by user]"
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"unknown\"}"
        }
        return json
    }

    // MARK: - Server Session Management

    private func createServerSession(_ session: SessionState) async {
        let metadata: [String: Any] = [
            "path": session.cwd,
            "title": session.displayTitle,     // Smart title: summary > user msg > project name
            "projectName": session.projectName, // Folder name as fallback
        ]

        guard let metadataJson = try? JSONSerialization.data(withJSONObject: metadata),
              let metadataString = String(data: metadataJson, encoding: .utf8) else { return }

        do {
            let result = try await connection.createSession(
                tag: session.sessionId,
                metadata: metadataString
            )
            if let serverId = result["id"] as? String {
                serverSessionIds[session.sessionId] = serverId
                Self.logger.info("Created server session \(serverId) for \(session.sessionId)")
            }
        } catch {
            Self.logger.error("Failed to create server session: \(error)")
        }
    }

    // MARK: - Alive Timer

    private func startAliveTimer(for sessionId: String) {
        stopAliveTimer(for: sessionId)
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let serverId = self?.serverSessionIds[sessionId] else { return }
            self?.connection.sendAlive(sessionId: serverId)
        }
        aliveTimers[sessionId] = timer
    }

    private func stopAliveTimer(for sessionId: String) {
        aliveTimers[sessionId]?.invalidate()
        aliveTimers.removeValue(forKey: sessionId)
    }
}
