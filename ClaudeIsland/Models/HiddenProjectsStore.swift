//
//  HiddenProjectsStore.swift
//  ClaudeIsland
//
//  User-managed hidden project list, keyed by absolute cwd path.
//  Two tiers:
//    - sessionDismissed: in-memory only, cleared on app restart.
//    - blacklisted: persisted via UserDefaults, survives restart.
//  Both tiers cause UI layers to filter the cwd out of all displays.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class HiddenProjectsStore: ObservableObject {
    static let shared = HiddenProjectsStore()

    /// Persisted blacklist (survives restart).
    @Published private(set) var blacklisted: Set<String> = []

    /// Session-only dismissals (cleared on restart).
    @Published private(set) var sessionDismissed: Set<String> = []

    private let defaultsKey = "hiddenProjectCwds"

    private init() {
        if let arr = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            blacklisted = Set(arr)
        }
    }

    /// True if the cwd is hidden by either tier.
    func isHidden(cwd: String) -> Bool {
        let key = Self.normalize(cwd)
        return blacklisted.contains(key) || sessionDismissed.contains(key)
    }

    /// Hide the cwd until next app launch.
    func dismissForSession(cwd: String) {
        sessionDismissed.insert(Self.normalize(cwd))
    }

    /// Add the cwd to the persistent blacklist.
    func blacklist(cwd: String) {
        let key = Self.normalize(cwd)
        blacklisted.insert(key)
        sessionDismissed.remove(key)  // promote: no need to keep both
        persist()
    }

    /// Remove a single cwd from the persistent blacklist.
    func unblacklist(cwd: String) {
        blacklisted.remove(Self.normalize(cwd))
        persist()
    }

    /// Clear both tiers entirely.
    func clearAll() {
        blacklisted.removeAll()
        sessionDismissed.removeAll()
        persist()
    }

    /// Sorted snapshot for settings UI.
    var allBlacklisted: [String] { blacklisted.sorted() }

    private func persist() {
        UserDefaults.standard.set(Array(blacklisted), forKey: defaultsKey)
    }

    private static func normalize(_ cwd: String) -> String {
        URL(fileURLWithPath: cwd).standardizedFileURL.path
    }
}
