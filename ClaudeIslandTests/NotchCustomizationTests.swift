//
//  NotchCustomizationTests.swift
//  ClaudeIslandTests
//
//  Unit tests for the NotchCustomization value type and its
//  supporting enums. Covers defaults, Codable roundtrip, forward-
//  compat decoding, FontScale multiplier mapping + raw stability,
//  NotchThemeID raw decoding, and HardwareNotchMode cases.
//
//  Note (2026-04-09): the ClaudeIsland Xcode project does not
//  currently define a dedicated test target — the existing files in
//  ClaudeIslandTests/ are reference tests that compile only when a
//  test target is added. These tests document the intended behavior
//  and can be wired into a target in a follow-up.
//

import XCTest
@testable import ClaudeIsland

final class NotchCustomizationTests: XCTestCase {

    // MARK: - Defaults

    func test_default_hasExpectedValues() {
        let c = NotchCustomization.default
        XCTAssertEqual(c.theme, .classic)
        XCTAssertEqual(c.fontScale, .default)
        XCTAssertTrue(c.showBuddy)
        XCTAssertTrue(c.showUsageBar)
        XCTAssertEqual(c.defaultGeometry.maxWidth, 440)
        XCTAssertEqual(c.defaultGeometry.horizontalOffset, 0)
        XCTAssertEqual(c.hardwareNotchMode, .auto)
    }

    // MARK: - Codable roundtrip

    func test_codable_roundtripPreservesAllFields() throws {
        var original = NotchCustomization.default
        original.theme = .neonLime
        original.fontScale = .large
        original.showBuddy = false
        original.showUsageBar = false
        original.defaultGeometry.maxWidth = 520
        original.defaultGeometry.horizontalOffset = -42
        original.hardwareNotchMode = .forceVirtual

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_codable_forwardCompat_missingFieldsUseDefaults() throws {
        // Older persisted blobs (or ones produced by a hypothetical
        // pre-release) may be missing some fields. Decoding should
        // succeed and fill missing fields with struct defaults.
        let partial = #"{"theme":"cyber"}"#
        let decoded = try JSONDecoder().decode(
            NotchCustomization.self,
            from: Data(partial.utf8)
        )
        XCTAssertEqual(decoded.theme, .cyber)
        XCTAssertEqual(decoded.fontScale, .default)
        XCTAssertTrue(decoded.showBuddy)
        XCTAssertTrue(decoded.showUsageBar)
        XCTAssertEqual(decoded.defaultGeometry.maxWidth, 440)
        XCTAssertEqual(decoded.defaultGeometry.horizontalOffset, 0)
        XCTAssertEqual(decoded.hardwareNotchMode, .auto)
    }

    // MARK: - FontScale

    func test_fontScale_multiplierMapping() {
        XCTAssertEqual(FontScale.small.multiplier,   0.85)
        XCTAssertEqual(FontScale.default.multiplier, 1.0)
        XCTAssertEqual(FontScale.large.multiplier,   1.15)
        XCTAssertEqual(FontScale.xLarge.multiplier,  1.3)
    }

    func test_fontScale_rawValueStability() {
        // These raw strings are persisted. Renaming any case is a
        // breaking change that requires a migration, so pin them
        // here to make the breakage loud.
        XCTAssertEqual(FontScale.small.rawValue,    "small")
        XCTAssertEqual(FontScale.default.rawValue,  "default")
        XCTAssertEqual(FontScale.large.rawValue,    "large")
        XCTAssertEqual(FontScale.xLarge.rawValue,   "xLarge")
    }

    func test_fontScale_caseIterableCoversAllFour() {
        XCTAssertEqual(FontScale.allCases.count, 4)
    }

    // MARK: - NotchThemeID

    func test_notchThemeID_allSixCasesDecodeFromRawValues() throws {
        for id in NotchThemeID.allCases {
            let json = "\"\(id.rawValue)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(NotchThemeID.self, from: json)
            XCTAssertEqual(decoded, id)
        }
    }

    func test_notchThemeID_caseIterableHasSix() {
        XCTAssertEqual(NotchThemeID.allCases.count, 6)
    }

    // MARK: - HardwareNotchMode

    func test_hardwareNotchMode_bothCasesDecode() throws {
        let auto = try JSONDecoder().decode(
            HardwareNotchMode.self,
            from: "\"auto\"".data(using: .utf8)!
        )
        let virt = try JSONDecoder().decode(
            HardwareNotchMode.self,
            from: "\"forceVirtual\"".data(using: .utf8)!
        )
        XCTAssertEqual(auto, .auto)
        XCTAssertEqual(virt, .forceVirtual)
    }

    // MARK: - ScreenGeometry

    func test_screenGeometry_defaultValues() {
        let geo = ScreenGeometry.default
        XCTAssertEqual(geo.maxWidth, 440)
        XCTAssertEqual(geo.horizontalOffset, 0)
        XCTAssertEqual(geo.notchHeight, 38)
    }

    func test_screenGeometry_codableRoundtrip() throws {
        var geo = ScreenGeometry.default
        geo.maxWidth = 520
        geo.horizontalOffset = -42
        geo.notchHeight = 50
        let data = try JSONEncoder().encode(geo)
        let decoded = try JSONDecoder().decode(ScreenGeometry.self, from: data)
        XCTAssertEqual(decoded, geo)
    }

    // MARK: - Per-screen geometry

    func test_geometry_forUnknownScreen_returnsDefault() {
        let c = NotchCustomization.default
        let geo = c.geometry(for: "999")
        XCTAssertEqual(geo, ScreenGeometry.default)
    }

    func test_updateGeometry_storesPerScreen() {
        var c = NotchCustomization.default
        c.updateGeometry(for: "42") { $0.notchHeight = 60 }
        XCTAssertEqual(c.geometry(for: "42").notchHeight, 60)
        XCTAssertEqual(c.geometry(for: "99").notchHeight, 38)
    }

    func test_codable_legacyMigration_topLevelFieldsToDefaultGeometry() throws {
        let legacy = """
        {"theme":"classic","fontScale":"default","showBuddy":true,"showUsageBar":true,
         "maxWidth":520,"horizontalOffset":-30,"hardwareNotchMode":"auto"}
        """
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.defaultGeometry.maxWidth, 520)
        XCTAssertEqual(decoded.defaultGeometry.horizontalOffset, -30)
        XCTAssertEqual(decoded.defaultGeometry.notchHeight, 38)
        XCTAssertTrue(decoded.screenGeometries.isEmpty)
    }

    func test_codable_newFormat_roundtrip() throws {
        var original = NotchCustomization.default
        original.updateGeometry(for: "42") { $0.maxWidth = 600; $0.notchHeight = 50 }
        original.updateGeometry(for: "99") { $0.horizontalOffset = 20 }
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
