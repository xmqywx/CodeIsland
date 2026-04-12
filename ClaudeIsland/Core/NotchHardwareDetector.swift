//
//  NotchHardwareDetector.swift
//  ClaudeIsland
//
//  Pure helper for deriving hardware-notch metrics from an
//  `NSScreen`. Used by `NotchWindowController` when recomputing
//  the panel geometry after a customization change.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 5.5.
//

import AppKit
import CoreGraphics

enum NotchHardwareDetector {

    /// Whether the given screen has a physical notch, honoring a
    /// user override. `.forceVirtual` causes the detector to
    /// return false even on MacBooks with a real notch so the
    /// overlay can be drawn as a free-floating virtual notch.
    static func hasHardwareNotch(on screen: NSScreen?, mode: HardwareNotchMode) -> Bool {
        switch mode {
        case .forceVirtual:
            return false
        case .auto:
            guard let screen else { return false }
            return (screen.safeAreaInsets.top > 0)
        }
    }

    /// Width of the hardware notch in points, derived from the
    /// screen's safe-area insets. Returns zero when there is no
    /// hardware notch (or when the mode is `.forceVirtual`).
    static func hardwareNotchWidth(on screen: NSScreen?, mode: HardwareNotchMode) -> CGFloat {
        guard hasHardwareNotch(on: screen, mode: mode), let screen else { return 0 }
        let insets = screen.safeAreaInsets
        return screen.frame.width - insets.left - insets.right
    }

    // MARK: - Auto-width clamp formula (pure, unit-testable)

    /// Minimum idle notch width — a hard floor ensuring the notch
    /// never becomes narrower than "pet icon + 3-char status +
    /// tiny indicator" at default font scale.
    static let minIdleWidth: CGFloat = 140

    // MARK: - Notch height clamp

    /// Minimum custom notch height — ensures the notch is always visible.
    static let minNotchHeight: CGFloat = 20

    /// Maximum custom notch height — prevents excessive screen coverage.
    static let maxNotchHeight: CGFloat = 80

    /// Clamp a user-provided notch height to the valid range. Pure function.
    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        max(minNotchHeight, min(height, maxNotchHeight))
    }

    /// Clamp the measured content width against the user's
    /// `maxWidth` and the hard `minIdleWidth` floor. Pure function;
    /// no global state.
    static func clampedWidth(
        measuredContentWidth: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        return max(minIdleWidth, min(measuredContentWidth, maxWidth))
    }

    /// Render-time clamp for the horizontal offset. Stateless: the
    /// stored value is preserved and only clamped when computing
    /// the final frame.
    static func clampedHorizontalOffset(
        storedOffset: CGFloat,
        runtimeWidth: CGFloat,
        screenWidth: CGFloat
    ) -> CGFloat {
        let baseX = (screenWidth - runtimeWidth) / 2
        let minOffset = -baseX
        let maxOffset = screenWidth - baseX - runtimeWidth
        return max(minOffset, min(storedOffset, maxOffset))
    }
}
