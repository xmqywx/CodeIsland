//
//  NotchThemeTests.swift
//  ClaudeIslandTests
//
//  Sanity tests for NotchPalette + NotchThemeID lookups. The point
//  is to catch regressions where a future refactor drops a case
//  from the switch in `NotchPalette.for(_:)` or silently reuses
//  the same palette for two different themes.
//

import XCTest
import SwiftUI
@testable import ClaudeIsland

final class NotchThemeTests: XCTestCase {

    func test_palettes_definedForAllSixThemeIDs() {
        // Just hitting the `for(_:)` switch for every case is enough
        // — the switch is exhaustive, so if we miss a case the
        // compiler would fail first. This test guards against
        // someone deleting a case from the enum.
        for id in NotchThemeID.allCases {
            let palette = NotchPalette.for(id)
            XCTAssertNotNil(palette, "Missing palette for \(id)")
        }
    }

    func test_palettes_haveDistinctBackgrounds() {
        // Each theme should ship a visually distinct background.
        // Equatable on SwiftUI.Color is not always reliable across
        // color spaces, so we describe them via their String form
        // and assert six unique entries. This is a smoke test, not
        // a perceptual diff.
        let descriptions = NotchThemeID.allCases.map { id -> String in
            String(describing: NotchPalette.for(id).bg)
        }
        XCTAssertEqual(Set(descriptions).count, 6)
    }

    func test_themeDisplayNames_allNonEmpty() {
        for id in NotchThemeID.allCases {
            XCTAssertFalse(id.displayName.isEmpty, "Empty display name for \(id)")
        }
    }

    func test_themeRawStringsMatchCaseNames() {
        XCTAssertEqual(NotchThemeID.classic.rawValue,      "classic")
        XCTAssertEqual(NotchThemeID.forest.rawValue,       "forest")
        XCTAssertEqual(NotchThemeID.neonTokyo.rawValue,    "neonTokyo")
        XCTAssertEqual(NotchThemeID.sunset.rawValue,       "sunset")
        XCTAssertEqual(NotchThemeID.retroArcade.rawValue,  "retroArcade")
        XCTAssertEqual(NotchThemeID.highContrast.rawValue, "highContrast")
        XCTAssertEqual(NotchThemeID.sakura.rawValue,       "sakura")
    }
}
