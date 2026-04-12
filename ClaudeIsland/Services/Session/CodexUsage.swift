//
//  CodexUsage.swift
//  ClaudeIsland
//
//  Reads rate-limit / usage data from Codex rollout JSONL files.
//  Scans ~/.codex/sessions/rollout-*.jsonl for the most recent token_count event.
//

import Combine
import Foundation

struct CodexUsageWindow: Equatable, Codable, Sendable, Identifiable {
    var key: String
    var label: String
    var usedPercentage: Double
    var leftPercentage: Double
    var windowMinutes: Int
    var resetsAt: Date?

    var id: String { key }

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

struct CodexUsageSnapshot: Equatable, Codable, Sendable {
    var sourceFilePath: String
    var capturedAt: Date?
    var planType: String?
    var limitID: String?
    var windows: [CodexUsageWindow]

    var isEmpty: Bool { windows.isEmpty }
}

// MARK: - Usage Monitor

/// Periodically loads the latest Codex usage snapshot and publishes it for UI consumption.
/// Mirrors the interface of RateLimitMonitor.
@MainActor
class CodexUsageMonitor: ObservableObject {
    static let shared = CodexUsageMonitor()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?

    private init() {}

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        snapshot = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        snapshot = try? CodexUsageLoader.load()
    }
}

// MARK: - Usage Loader

enum CodexUsageLoader {
    static let defaultRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    static func load(
        fromRootURL rootURL: URL = defaultRootURL,
        fileManager: FileManager = .default
    ) throws -> CodexUsageSnapshot? {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return nil }

        var candidates: [Candidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  resourceValues.isRegularFile == true else { continue }
            candidates.append(Candidate(
                fileURL: fileURL,
                modifiedAt: resourceValues.contentModificationDate ?? .distantPast
            ))
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            lhs.modifiedAt == rhs.modifiedAt
                ? lhs.fileURL.path.localizedStandardCompare(rhs.fileURL.path) == .orderedDescending
                : lhs.modifiedAt > rhs.modifiedAt
        }

        for candidate in sortedCandidates {
            if let snapshot = loadLatestSnapshot(from: candidate.fileURL, modifiedAt: candidate.modifiedAt) {
                return snapshot
            }
        }

        return nil
    }

    private static func loadLatestSnapshot(from fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var latestSnapshot: CodexUsageSnapshot?
        contents.enumerateLines { line, _ in
            guard let snapshot = snapshot(from: line, filePath: fileURL.path, fallbackTimestamp: modifiedAt) else {
                return
            }
            latestSnapshot = snapshot
        }
        return latestSnapshot
    }

    private static func snapshot(from line: String, filePath: String, fallbackTimestamp: Date) -> CodexUsageSnapshot? {
        guard let object = jsonObject(for: line),
              object["type"] as? String == "event_msg" else { return nil }

        let payload = object["payload"] as? [String: Any] ?? [:]
        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        let windows = ["primary", "secondary"].compactMap { key in
            usageWindow(for: key, in: rateLimits)
        }
        guard !windows.isEmpty else { return nil }

        return CodexUsageSnapshot(
            sourceFilePath: filePath,
            capturedAt: timestamp(from: object["timestamp"]) ?? fallbackTimestamp,
            planType: string(from: rateLimits["plan_type"]),
            limitID: string(from: rateLimits["limit_id"]),
            windows: windows
        )
    }

    private static func usageWindow(for key: String, in rateLimits: [String: Any]) -> CodexUsageWindow? {
        guard let payload = rateLimits[key] as? [String: Any],
              let usedPercentage = number(from: payload["used_percent"]),
              let windowMinutes = integer(from: payload["window_minutes"]) else { return nil }

        return CodexUsageWindow(
            key: key,
            label: windowLabel(forMinutes: windowMinutes),
            usedPercentage: usedPercentage,
            leftPercentage: max(0, 100 - usedPercentage),
            windowMinutes: windowMinutes,
            resetsAt: date(from: payload["resets_at"])
        )
    }

    private static func windowLabel(forMinutes minutes: Int) -> String {
        let days = minutes / 1_440
        let remainingMinutesAfterDays = minutes % 1_440
        let hours = remainingMinutesAfterDays / 60
        let remainingMinutes = remainingMinutesAfterDays % 60

        if days > 0, hours == 0, remainingMinutes == 0 { return "\(days)d" }
        if days > 0, hours > 0 { return "\(days)d \(hours)h" }
        if hours > 0, remainingMinutes == 0 { return "\(hours)h" }
        if hours > 0 { return "\(hours)h \(remainingMinutes)m" }
        return "\(minutes)m"
    }

    private static func jsonObject(for line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private static func timestamp(from value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        switch value {
        case let number as NSNumber: return Date(timeIntervalSince1970: number.doubleValue)
        case let string as String:
            guard let seconds = Double(string) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        default: return nil
        }
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
