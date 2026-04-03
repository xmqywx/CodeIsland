//
//  RateLimitMonitor.swift
//  ClaudeIsland
//
//  Monitors Claude Code rate limit status by parsing JSONL or querying CLI.
//

import Combine
import Foundation
import SwiftUI

/// Parsed rate limit display info
struct RateLimitDisplayInfo: Equatable {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let fiveHourResetAt: Date?
    let sevenDayResetAt: Date?
    let planName: String?

    var displayText: String {
        var parts: [String] = []

        // 5h: just percentage + reset time, no label
        if let pct = fiveHourPercent {
            let resetStr = formatRemaining(fiveHourResetAt)
            parts.append("\(pct)%\(resetStr.isEmpty ? "" : " \(resetStr)")")
        }

        // 7d: show when >= 5%
        if let pct = sevenDayPercent, pct >= 5 {
            let resetStr = formatRemaining(sevenDayResetAt)
            parts.append("\(pct)%\(resetStr.isEmpty ? "" : " \(resetStr)")")
        }

        return parts.isEmpty ? "--" : parts.joined(separator: "|\(parts.count > 1 ? "" : "")")
    }

    var tooltip: String {
        var lines: [String] = []
        if let plan = planName {
            lines.append("Plan: \(plan)")
        }
        if let pct = fiveHourPercent {
            let reset = formatRemainingLong(fiveHourResetAt)
            lines.append("5小时窗口: \(pct)%\(reset.isEmpty ? "" : " (\(reset)后重置)")")
        }
        if let pct = sevenDayPercent {
            let reset = formatRemainingLong(sevenDayResetAt)
            lines.append("7天窗口: \(pct)%\(reset.isEmpty ? "" : " (\(reset)后重置)")")
        }
        return lines.isEmpty ? "Claude 用量" : lines.joined(separator: "\n")
    }

    var color: Color {
        let maxPct = max(fiveHourPercent ?? 0, sevenDayPercent ?? 0)
        if maxPct >= 90 {
            return Color(red: 0.94, green: 0.27, blue: 0.27)  // red
        }
        if maxPct >= 70 {
            return Color(red: 1.0, green: 0.6, blue: 0.2)  // orange
        }
        return Color(red: 0.29, green: 0.87, blue: 0.5)  // green
    }

    private func formatRemaining(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "" }
        if remaining < 3600 {
            return "\(Int(remaining / 60))m"
        } else if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(Int(remaining / 86400))d"
    }

    private func formatRemainingLong(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "" }
        if remaining < 3600 {
            return "\(Int(remaining / 60))分钟"
        } else if remaining < 86400 {
            let h = Int(remaining / 3600)
            let m = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)小时\(m)分钟" : "\(h)小时"
        }
        return "\(Int(remaining / 86400))天"
    }
}

@MainActor
class RateLimitMonitor: ObservableObject {
    static let shared = RateLimitMonitor()

    @Published private(set) var rateLimitInfo: RateLimitDisplayInfo?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?

    private init() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let info = await fetchFromAPI() {
            rateLimitInfo = info
        }
    }

    /// Read OAuth token from macOS Keychain and call Anthropic usage API
    private func fetchFromAPI() async -> RateLimitDisplayInfo? {
        // Read token from Keychain
        guard let token = readOAuthToken() else {
            DebugLogger.log("RateLimit", "No OAuth token found")
            return nil
        }

        // Call https://api.anthropic.com/api/oauth/usage
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DebugLogger.log("RateLimit", "API error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let fiveHour = json["five_hour"] as? [String: Any]
            let sevenDay = json["seven_day"] as? [String: Any]

            let fiveHourPct = (fiveHour?["utilization"] as? Double).map { Int($0) }
            let sevenDayPct = (sevenDay?["utilization"] as? Double).map { Int($0) }
            let fiveHourReset = (fiveHour?["resets_at"] as? String).flatMap { formatter.date(from: $0) }
            let sevenDayReset = (sevenDay?["resets_at"] as? String).flatMap { formatter.date(from: $0) }

            DebugLogger.log("RateLimit", "API: 5h=\(fiveHourPct ?? -1)% 7d=\(sevenDayPct ?? -1)%")

            return RateLimitDisplayInfo(
                fiveHourPercent: fiveHourPct,
                sevenDayPercent: sevenDayPct,
                fiveHourResetAt: fiveHourReset,
                sevenDayResetAt: sevenDayReset,
                planName: nil
            )
        } catch {
            DebugLogger.log("RateLimit", "Fetch error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Read OAuth access token from macOS Keychain
    private func readOAuthToken() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else { return nil }
            return token
        } catch {
            return nil
        }
    }
}
