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

    /// Map local sessionId → server session id
    private var serverSessionIds: [String: String] = [:]

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
        for session in sessions {
            let sessionId = session.sessionId

            // New session detected — create on server
            if !knownSessionIds.contains(sessionId) {
                knownSessionIds.insert(sessionId)
                syncedItemCounts[sessionId] = 0
                Task { await createServerSession(session) }
                startAliveTimer(for: sessionId)
            }

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
        }
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

        guard items.count > syncedCount else { return }
        guard connection.isConnected else {
            Self.logger.warning("Skipping sync: not connected")
            return
        }

        // Only sync new items
        let newItems = Array(items.dropFirst(syncedCount))
        syncedItemCounts[localId] = items.count

        for item in newItems {
            let content = serializeChatItem(item)
            connection.sendMessage(
                sessionId: serverId,  // Use server's session ID, not local
                content: content,
                localId: item.id
            )
        }

        Self.logger.info("Synced \(newItems.count) new messages for \(localId.prefix(8))...")
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
            "title": session.projectName,
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
