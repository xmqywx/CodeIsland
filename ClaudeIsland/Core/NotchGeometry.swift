//
//  NotchGeometry.swift
//  ClaudeIsland
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat

    /// The notch rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// The opened panel rect in screen coordinates for a given size
    func openedScreenRect(for size: CGSize) -> CGRect {
        // Add small padding (10px) around the panel for comfortable clicking
        let width = size.width + 10
        let height = size.height + 10
        return CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Default expansion width for Dynamic Island wings
    var expansionWidth: CGFloat = 240

    /// The collapsed content rect including wings (notch + expansion on both sides)
    func collapsedScreenRect(expansionWidth: CGFloat? = nil) -> CGRect {
        let width = expansionWidth ?? self.expansionWidth
        let totalWidth = deviceNotchRect.width + width
        return CGRect(
            x: screenRect.midX - totalWidth / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: totalWidth,
            height: deviceNotchRect.height
        )
    }

    /// Check if a point is in the clickable notch area (including expanded wings)
    func isPointInNotch(_ point: CGPoint, expansionWidth: CGFloat? = nil) -> Bool {
        collapsedScreenRect(expansionWidth: expansionWidth).insetBy(dx: -10, dy: -5).contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }
}
