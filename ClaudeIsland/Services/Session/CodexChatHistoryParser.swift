//
//  CodexChatHistoryParser.swift
//  ClaudeIsland
//
//  Parses Codex rollout JSONL files into ChatMessage objects for display in ChatView.
//  Prefers response_item entries (full API format) over event_msg summaries.
//

import Foundation
import os.log

actor CodexChatHistoryParser {
    static let shared = CodexChatHistoryParser()
    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "CodexParser")

    private struct CachedResult {
        let modificationDate: Date
        let messages: [ChatMessage]
    }
    private var cache: [String: CachedResult] = [:]

    /// Parse a rollout JSONL file into an ordered array of ChatMessages.
    /// Uses modification-date caching to avoid re-parsing unchanged files.
    func parse(transcriptPath: String) -> [ChatMessage] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: transcriptPath),
              let attrs = try? fileManager.attributesOfItem(atPath: transcriptPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return []
        }

        if let cached = cache[transcriptPath], cached.modificationDate == modDate {
            return cached.messages
        }

        guard let contents = try? String(contentsOf: URL(fileURLWithPath: transcriptPath), encoding: .utf8) else {
            return []
        }

        var messages: [ChatMessage] = []
        var counter = 0

        // First pass: collect response_item messages (authoritative, full content)
        contents.enumerateLines { line, _ in
            guard let object = self.jsonObject(for: line),
                  object["type"] as? String == "response_item" else { return }
            let timestamp = self.parseTimestamp(object["timestamp"] as? String) ?? Date()
            let payload = object["payload"] as? [String: Any] ?? [:]
            if let msg = self.parseResponseItem(payload, timestamp: timestamp, counter: &counter) {
                messages.append(msg)
            }
        }

        // Fall back to event_msg stream if no response_item messages were found
        if messages.isEmpty {
            contents.enumerateLines { line, _ in
                guard let object = self.jsonObject(for: line),
                      object["type"] as? String == "event_msg" else { return }
                let timestamp = self.parseTimestamp(object["timestamp"] as? String) ?? Date()
                let payload = object["payload"] as? [String: Any] ?? [:]
                if let msg = self.parseEventMsg(payload, timestamp: timestamp, counter: &counter) {
                    messages.append(msg)
                }
            }
        }

        cache[transcriptPath] = CachedResult(modificationDate: modDate, messages: messages)
        return messages
    }

    // MARK: - Private

    private func parseResponseItem(
        _ payload: [String: Any],
        timestamp: Date,
        counter: inout Int
    ) -> ChatMessage? {
        guard payload["type"] as? String == "message",
              let roleStr = payload["role"] as? String,
              let contentArray = payload["content"] as? [[String: Any]] else { return nil }

        let role: ChatRole = roleStr == "user" ? .user : .assistant
        let textType = roleStr == "user" ? "input_text" : "output_text"

        var blocks: [MessageBlock] = []
        for item in contentArray {
            guard item["type"] as? String == textType,
                  let text = item["text"] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if role == .user, isInjectedBlock(trimmed) { continue }
            blocks.append(.text(trimmed))
        }
        guard !blocks.isEmpty else { return nil }

        counter += 1
        return ChatMessage(id: "codex-\(counter)", role: role, timestamp: timestamp, content: blocks)
    }

    private func parseEventMsg(
        _ payload: [String: Any],
        timestamp: Date,
        counter: inout Int
    ) -> ChatMessage? {
        guard let msgType = payload["type"] as? String,
              let text = payload["message"] as? String,
              !text.isEmpty else { return nil }

        let role: ChatRole
        switch msgType {
        case "user_message": role = .user
        case "agent_message": role = .assistant
        default: return nil
        }

        counter += 1
        return ChatMessage(id: "codex-evt-\(counter)", role: role, timestamp: timestamp, content: [.text(text)])
    }

    private func isInjectedBlock(_ text: String) -> Bool {
        text.hasPrefix("# AGENTS.md instructions for ")
            || text.hasPrefix("<environment_context>")
            || text.hasPrefix("<permissions instructions>")
            || text.hasPrefix("<collaboration_mode>")
            || text.hasPrefix("<skills_instructions>")
    }

    private func jsonObject(for line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private func parseTimestamp(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
