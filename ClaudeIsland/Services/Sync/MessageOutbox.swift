//
//  MessageOutbox.swift
//  ClaudeIsland
//
//  Persistent message queue with WAL-style append + crash-recovery.
//  Uses atomic JSON file writes to avoid corruption on crash.
//

import Foundation
import os.log

/// Thread-safe persistent outbox for messages that failed to send.
/// Uses an append-only WAL (write-ahead log) pattern with atomic file moves.
actor MessageOutbox {
    static let shared = MessageOutbox()
    static let logger = Logger(subsystem: "com.codeisland", category: "MessageOutbox")

    // MARK: - Paths

    private let supportDir: URL
    private let outboxPath: URL       // pending messages
    private let lockPath: URL        // atomic write lock
    private let injectionsPath: URL   // recently injected text ring buffer
    private let mappingsPath: URL     // local→server session ID mappings

    // MARK: - In-memory caches (loaded from disk on init)

    private var pendingMessages: [OutboxEntry] = []
    private var injections: [String: [(text: String, at: Date)]] = [:]
    private var sessionMappings: [String: String] = [:]  // localId → serverId
    private var serverToLocal: [String: String] = [:]      // serverId → localId (reverse index)

    // MARK: - Config

    private let maxInjections = 1000
    private let maxRetries = 5
    private let batchSize = 50

    // MARK: - Init

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDir = appSupport.appendingPathComponent("CodeIsland", isDirectory: true)

        outboxPath = supportDir.appendingPathComponent("outbox.json")
        lockPath = supportDir.appendingPathComponent("outbox.lock")
        injectionsPath = supportDir.appendingPathComponent("injections.json")
        mappingsPath = supportDir.appendingPathComponent("session_mappings.json")

        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - Load / Persist

    private func loadAll() {
        loadOutbox()
        loadInjections()
        loadMappings()
    }

    private func loadOutbox() {
        guard let data = try? Data(contentsOf: outboxPath),
              let entries = try? JSONDecoder().decode([OutboxEntry].self, from: data) else {
            pendingMessages = []
            return
        }
        pendingMessages = entries.filter { $0.retryCount < maxRetries }
    }

    private func persistOutbox() {
        guard let data = try? JSONEncoder().encode(pendingMessages) else { return }
        atomicWrite(data: data, to: outboxPath)
    }

    private func loadInjections() {
        guard let data = try? Data(contentsOf: injectionsPath),
              let decoded = try? JSONDecoder().decode([String: [InjectionEntry]].self, from: data) else {
            injections = [:]
            return
        }
        injections = decoded.mapValues { entries in
            entries.map { ($0.text, Date(timeIntervalSince1970: $0.timestamp)) }
        }
        pruneInjections()
    }

    private func loadMappings() {
        guard let data = try? Data(contentsOf: mappingsPath),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            sessionMappings = [:]
            serverToLocal = [:]
            return
        }
        sessionMappings = decoded
        serverToLocal = Dictionary(uniqueKeysWithValues: decoded.map { key, value in (value, key) })  // serverId → localId
    }

    // MARK: - Outbox Operations

    /// Add a message to the outbox for later retry
    func enqueue(message: String, sessionId: String, localId: String?) {
        let entry = OutboxEntry(
            id: UUID().uuidString,
            sessionId: sessionId,
            content: message,
            localId: localId,
            createdAt: Date(),
            retryCount: 0
        )
        pendingMessages.append(entry)
        persistOutbox()
    }

    /// Get pending messages up to batchSize
    func dequeuePending() -> [OutboxEntry] {
        let batch = Array(pendingMessages.prefix(batchSize))
        return batch
    }

    /// Remove successfully delivered entries from outbox
    func markDelivered(ids: [String]) {
        pendingMessages.removeAll { ids.contains($0.id) }
        persistOutbox()
    }

    /// Increment retry count for failed entries
    func incrementRetries(ids: [String]) {
        for i in pendingMessages.indices {
            if ids.contains(pendingMessages[i].id) {
                pendingMessages[i].retryCount += 1
            }
        }
        // Drop entries that exceeded max retries
        pendingMessages.removeAll { $0.retryCount >= maxRetries }
        persistOutbox()
    }

    /// Number of pending messages
    var pendingCount: Int { pendingMessages.count }

    // MARK: - Injection Tracking

    func recordInjection(claudeUuid: String, text: String) {
        pruneInjections()
        injections[claudeUuid, default: []].append((text, Date()))
        persistInjections()
    }

    /// Returns true and removes the entry if `text` was recently injected
    func consumeInjection(claudeUuid: String, text: String) -> Bool {
        pruneInjections()
        guard var list = injections[claudeUuid] else { return false }
        if let idx = list.firstIndex(where: { $0.text == text }) {
            list.remove(at: idx)
            injections[claudeUuid] = list.isEmpty ? nil : list
            persistInjections()
            return true
        }
        return false
    }

    private func pruneInjections() {
        let cutoff = Date().addingTimeInterval(-60)
        for (k, v) in injections {
            let kept = v.filter { $0.at > cutoff }
            injections[k] = kept.isEmpty ? nil : kept
        }
        // Also cap total entries per uuid
        for (k, v) in injections {
            if v.count > maxInjections {
                injections[k] = Array(v.suffix(maxInjections))
            }
        }
    }

    private func persistInjections() {
        let encodable = injections.mapValues { entries in
            entries.map { InjectionEntry(text: $0.text, timestamp: $0.at.timeIntervalSince1970) }
        }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        atomicWrite(data: data, to: injectionsPath)
    }

    // MARK: - Session Mappings

    func recordMapping(localId: String, serverId: String) {
        sessionMappings[localId] = serverId
        serverToLocal[serverId] = localId
        persistMappings()
    }

    func getServerId(forLocalId localId: String) -> String? {
        sessionMappings[localId]
    }

    func getLocalId(forServerId serverId: String) -> String? {
        serverToLocal[serverId]
    }

    var allMappings: [String: String] { sessionMappings }

    private func persistMappings() {
        guard let data = try? JSONEncoder().encode(sessionMappings) else { return }
        atomicWrite(data: data, to: mappingsPath)
    }

    /// Clear all mappings (call when server connection is fully reset)
    func clearMappings() {
        sessionMappings.removeAll()
        serverToLocal.removeAll()
        persistMappings()
    }

    // MARK: - Cleanup

    /// Called on app launch and periodically to clean stale entries
    func cleanup() {
        // Remove outbox entries older than 24 hours
        let dayAgo = Date().addingTimeInterval(-86400)
        pendingMessages.removeAll { $0.createdAt < dayAgo && $0.retryCount >= maxRetries }
        persistOutbox()
    }

    // MARK: - Atomic Write

    /// Write data atomically using a temp file + rename ( POSIX rename is atomic )
    private nonisolated func atomicWrite(data: Data, to url: URL) {
        let tmp = url.appendingPathExtension("tmp")
        do {
            // Remove existing temp file first (moveItem fails if dst exists)
            try? FileManager.default.removeItem(at: tmp)
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch {
            Self.logger.error("atomicWrite failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

// MARK: - Data Types

struct OutboxEntry: Codable, Identifiable {
    let id: String
    let sessionId: String
    let content: String
    let localId: String?
    let createdAt: Date
    var retryCount: Int
}

struct InjectionEntry: Codable {
    let text: String
    let timestamp: TimeInterval
}
