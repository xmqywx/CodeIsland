//
//  AutoWidthTests.swift
//  ClaudeIslandTests
//
//  Unit tests for the pure clamp formulas in NotchHardwareDetector.
//  The actual SwiftUI / AppKit geometry pipeline is covered by
//  manual QA in docs/qa/notch-customization.md — these tests only
//  exercise the scalar math that decides runtimeWidth and
//  clampedHorizontalOffset.
//

import XCTest
import CoreGraphics
@testable import ClaudeIsland

final class AutoWidthTests: XCTestCase {

    // MARK: - clampedWidth

    func test_clampedWidth_belowMinIdleFloor_returnsMinIdle() {
        XCTAssertEqual(
            NotchHardwareDetector.clampedWidth(measuredContentWidth: 80, maxWidth: 440),
            NotchHardwareDetector.minIdleWidth
        )
    }

    func test_clampedWidth_aboveMaxWidth_returnsMaxWidth() {
        XCTAssertEqual(
            NotchHardwareDetector.clampedWidth(measuredContentWidth: 800, maxWidth: 440),
            440
        )
    }

    func test_clampedWidth_betweenMinAndMax_returnsMeasured() {
        XCTAssertEqual(
            NotchHardwareDetector.clampedWidth(measuredContentWidth: 260, maxWidth: 440),
            260
        )
    }

    func test_clampedWidth_neverExceedsMaxWidth() {
        for measured: CGFloat in stride(from: 0, to: 1000, by: 37) {
            for maxWidth: CGFloat in [200, 300, 440, 600] {
                let clamped = NotchHardwareDetector.clampedWidth(
                    measuredContentWidth: measured,
                    maxWidth: maxWidth
                )
                XCTAssertLessThanOrEqual(clamped, maxWidth)
                XCTAssertGreaterThanOrEqual(clamped, NotchHardwareDetector.minIdleWidth)
            }
        }
    }

    // MARK: - clampedHorizontalOffset

    func test_clampedHorizontalOffset_zero_returnsZero() {
        let clamped = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: 0,
            runtimeWidth: 440,
            screenWidth: 1440
        )
        XCTAssertEqual(clamped, 0)
    }

    func test_clampedHorizontalOffset_withinBounds_passesThrough() {
        let clamped = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: 100,
            runtimeWidth: 440,
            screenWidth: 1440
        )
        XCTAssertEqual(clamped, 100)
    }

    func test_clampedHorizontalOffset_tooNegative_clampsToLeftEdge() {
        // baseX = (1440 - 440) / 2 = 500, so min offset = -500
        let clamped = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: -9999,
            runtimeWidth: 440,
            screenWidth: 1440
        )
        XCTAssertEqual(clamped, -500)
    }

    func test_clampedHorizontalOffset_tooPositive_clampsToRightEdge() {
        // baseX = 500, max offset = 1440 - 500 - 440 = 500
        let clamped = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: 9999,
            runtimeWidth: 440,
            screenWidth: 1440
        )
        XCTAssertEqual(clamped, 500)
    }

    // MARK: - clampedHeight

    func test_clampedHeight_withinRange_passesThrough() {
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(50), 50)
    }

    func test_clampedHeight_belowMin_returnsMin() {
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(5), NotchHardwareDetector.minNotchHeight)
    }

    func test_clampedHeight_aboveMax_returnsMax() {
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(200), NotchHardwareDetector.maxNotchHeight)
    }

    // MARK: - hasHardwareNotch mode override

    func test_hasHardwareNotch_forceVirtual_alwaysFalse() {
        XCTAssertFalse(NotchHardwareDetector.hasHardwareNotch(on: nil, mode: .forceVirtual))
    }

    func test_hasHardwareNotch_autoWithNoScreen_false() {
        XCTAssertFalse(NotchHardwareDetector.hasHardwareNotch(on: nil, mode: .auto))
    }
}
