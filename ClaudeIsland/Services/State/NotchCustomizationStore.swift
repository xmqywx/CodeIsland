//
//  NotchCustomizationStore.swift
//  ClaudeIsland
//
//  Central ObservableObject that holds the user's NotchCustomization
//  and persists it atomically under the UserDefaults key
//  `notchCustomization.v1`. Also handles a one-shot legacy migration
//  from older @AppStorage keys (`usePixelCat`) and owns the live
//  edit mode state machine (snapshot / commit / cancel).
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 5.2.
//

import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class NotchCustomizationStore: ObservableObject {
    static let shared = NotchCustomizationStore()

    private static let log = Logger(subsystem: "com.codeisland.app", category: "notchStore")
    static let defaultsKey = "notchCustomization.v1"

    @Published private(set) var customization: NotchCustomization

    /// Ephemeral, NOT persisted. Views observe this to switch into
    /// live edit mode visuals.
    @Published var isEditing: Bool = false

    /// Snapshot of `customization` taken at `enterEditMode()`. On
    /// `cancelEdit()` this is assigned back, rolling all in-session
    /// changes in one atomic step. On `commitEdit()` this is cleared.
    private var editDraftOrigin: NotchCustomization?

    /// `internal` (not `private`) so tests can construct fresh
    /// instances that don't share state with the singleton. Normal
    /// production code uses `.shared`.
    init() {
        if let loaded = Self.loadFromDefaults() {
            self.customization = loaded
            return
        }
        // No v1 key yet — one-shot migration from legacy keys.
        self.customization = Self.readLegacyOrDefault()
        if self.saveAndVerify() {
            Self.removeLegacyKeys()
        } else {
            Self.log.error("Initial v1 write failed; legacy keys retained for retry on next launch")
        }
    }

    // MARK: - Mutation

    /// All mutations funnel through here so the save call happens
    /// exactly once per user action.
    func update(_ mutation: (inout NotchCustomization) -> Void) {
        mutation(&customization)
        save()
    }

    /// Convenience for updating geometry of a specific screen.
    func updateGeometry(for screenID: String, _ mutation: (inout ScreenGeometry) -> Void) {
        update { $0.updateGeometry(for: screenID, mutation) }
    }

    // MARK: - Live edit lifecycle

    func enterEditMode() {
        editDraftOrigin = customization
        isEditing = true
    }

    func commitEdit() {
        editDraftOrigin = nil
        isEditing = false
        save()
    }

    func cancelEdit() {
        if let origin = editDraftOrigin {
            customization = origin
            save()
        }
        editDraftOrigin = nil
        isEditing = false
    }

    // MARK: - Persistence

    @discardableResult
    private func save() -> Bool {
        do {
            let data = try JSONEncoder().encode(customization)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            return true
        } catch {
            Self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Save and then read back to confirm the bytes landed. Used by
    /// migration so we only delete legacy keys after the new key is
    /// demonstrably on disk.
    private func saveAndVerify() -> Bool {
        guard save() else { return false }
        return Self.loadFromDefaults() != nil
    }

    private static func loadFromDefaults() -> NotchCustomization? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(NotchCustomization.self, from: data)
    }

    // MARK: - Legacy migration

    /// Pull legacy @AppStorage values into a new NotchCustomization.
    /// Does NOT mutate UserDefaults — deletion is a separate step that
    /// only runs after the v1 key is successfully written.
    private static func readLegacyOrDefault() -> NotchCustomization {
        var c = NotchCustomization.default
        let d = UserDefaults.standard
        if d.object(forKey: "usePixelCat") != nil {
            c.showBuddy = d.bool(forKey: "usePixelCat")
        }
        // Future legacy keys go here, following the same pattern.
        return c
    }

    private static func removeLegacyKeys() {
        UserDefaults.standard.removeObject(forKey: "usePixelCat")
        // Future legacy keys go here.
    }
}
