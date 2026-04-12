//
//  CodexFeatureGate.swift
//  ClaudeIsland
//
//  Master toggle for all Codex features. Off by default.
//

import Combine
import Foundation

@MainActor
final class CodexFeatureGate: ObservableObject {
    static let shared = CodexFeatureGate()

    private static let key = "codexEnabled"

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
            if isEnabled { didEnable() } else { didDisable() }
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Called once from AppDelegate.applicationDidFinishLaunching.
    func onLaunch() {
        guard isEnabled else { return }
        CodexHookInstaller.installIfNeeded()
        CodexUsageMonitor.shared.start()
    }

    private func didEnable() {
        CodexHookInstaller.installIfNeeded()
        CodexUsageMonitor.shared.start()
    }

    private func didDisable() {
        CodexHookInstaller.uninstall()
        CodexUsageMonitor.shared.stop()
    }
}
