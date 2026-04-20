//
//  NotchCustomizationStoreTests.swift
//  ClaudeIslandTests
//
//  Unit tests for the NotchCustomizationStore singleton / DI
//  surface. Covers init from fresh state, init from existing v1
//  blob, legacy usePixelCat migration (both true and false),
//  update-closure persistence, and the enter/commit/cancel edit
//  lifecycle including persistence across simulated reload.
//
//  NOTE: these tests manipulate UserDefaults.standard directly and
//  so must each clean up the keys they touch (setUp / tearDown).
//

import XCTest
@testable import ClaudeIsland

@MainActor
final class NotchCustomizationStoreTests: XCTestCase {

    private let v1Key = NotchCustomizationStore.defaultsKey
    private let legacyBuddyKey = "usePixelCat"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: v1Key)
        UserDefaults.standard.removeObject(forKey: legacyBuddyKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: v1Key)
        UserDefaults.standard.removeObject(forKey: legacyBuddyKey)
    }

    // MARK: - Init / load

    func test_init_withNoKeys_returnsDefault() {
        let store = NotchCustomizationStore()
        XCTAssertEqual(store.customization, .default)
    }

    func test_init_withExistingV1Key_loadsIt() throws {
        var persisted = NotchCustomization.default
        persisted.theme = .neonTokyo
        persisted.defaultGeometry.maxWidth = 520
        let data = try JSONEncoder().encode(persisted)
        UserDefaults.standard.set(data, forKey: v1Key)

        let store = NotchCustomizationStore()
        XCTAssertEqual(store.customization.theme, .neonTokyo)
        XCTAssertEqual(store.customization.defaultGeometry.maxWidth, 520)
    }

    // MARK: - Migration

    func test_init_migratesLegacyUsePixelCatFalse() {
        UserDefaults.standard.set(false, forKey: legacyBuddyKey)

        let store = NotchCustomizationStore()
        XCTAssertFalse(store.customization.showBuddy)
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: v1Key),
            "v1 key should be written after migration"
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: legacyBuddyKey),
            "legacy key should be removed after successful migration"
        )
    }

    func test_init_migratesLegacyUsePixelCatTrue() {
        UserDefaults.standard.set(true, forKey: legacyBuddyKey)

        let store = NotchCustomizationStore()
        XCTAssertTrue(store.customization.showBuddy)
    }

    // MARK: - update closure

    func test_update_mutatesAndPersists() throws {
        let store = NotchCustomizationStore()
        store.update { $0.theme = .forest }

        XCTAssertEqual(store.customization.theme, .forest)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: v1Key))
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
        XCTAssertEqual(decoded.theme, .forest)
    }

    func test_updateGeometry_mutatesAndPersists() throws {
        let store = NotchCustomizationStore()
        store.updateGeometry(for: "42") { $0.notchHeight = 55 }

        XCTAssertEqual(store.customization.geometry(for: "42").notchHeight, 55)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: v1Key))
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
        XCTAssertEqual(decoded.geometry(for: "42").notchHeight, 55)
    }

    // MARK: - Edit lifecycle

    func test_enterEditMode_setsIsEditing() {
        let store = NotchCustomizationStore()
        XCTAssertFalse(store.isEditing)
        store.enterEditMode()
        XCTAssertTrue(store.isEditing)
    }

    func test_cancelEdit_rollsBackToSnapshot() {
        let store = NotchCustomizationStore()
        store.update { $0.defaultGeometry.maxWidth = 400 }
        store.enterEditMode()
        store.update { $0.defaultGeometry.maxWidth = 600 }
        XCTAssertEqual(store.customization.defaultGeometry.maxWidth, 600)
        store.cancelEdit()
        XCTAssertEqual(store.customization.defaultGeometry.maxWidth, 400)
        XCTAssertFalse(store.isEditing)
    }

    func test_commitEdit_keepsChanges() {
        let store = NotchCustomizationStore()
        store.update { $0.defaultGeometry.maxWidth = 400 }
        store.enterEditMode()
        store.update { $0.defaultGeometry.maxWidth = 600 }
        store.commitEdit()
        XCTAssertEqual(store.customization.defaultGeometry.maxWidth, 600)
        XCTAssertFalse(store.isEditing)
    }

    func test_editLifecycle_persistsCommittedChangesAcrossSimulatedReload() throws {
        let store1 = NotchCustomizationStore()
        store1.enterEditMode()
        store1.update { $0.theme = .sakura }
        store1.commitEdit()

        let store2 = NotchCustomizationStore()
        XCTAssertEqual(store2.customization.theme, .sakura)
    }
}
