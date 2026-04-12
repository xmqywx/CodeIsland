//
//  Ext+NSScreen.swift
//  ClaudeIsland
//
//  Extensions for NSScreen to detect notch and built-in display
//

import AppKit

extension NSScreen {
    /// Returns the size of the notch on this screen (pixel-perfect using macOS APIs)
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            // Fallback for non-notch displays (matches typical MacBook notch)
            return CGSize(width: 224, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            // Fallback if auxiliary areas unavailable
            return CGSize(width: 180, height: notchHeight)
        }

        // +4 to match boring.notch's calculation for proper alignment
        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// Whether this is the built-in display
    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// The built-in display (with notch on newer MacBooks)
    static var builtin: NSScreen? {
        if let builtin = screens.first(where: { $0.isBuiltinDisplay }) {
            return builtin
        }
        return NSScreen.main
    }

    /// Whether this screen has a physical notch (camera housing)
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// Stable string identifier for per-screen settings persistence.
    /// Uses vendor+model+serial for external displays (survives reboots
    /// and port changes). Falls back to CGDirectDisplayID when the
    /// hardware identifiers are unavailable (returns 0 for all three).
    var persistentID: String {
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return "0"
        }
        let vendor = CGDisplayVendorNumber(displayID)
        let model  = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        // If hardware identifiers are available, use the stable composite key.
        // The triple (0,0,0) means the display doesn't report EDID data —
        // fall back to the session-scoped CGDirectDisplayID.
        if vendor == 0, model == 0, serial == 0 {
            return String(displayID)
        }
        return "\(vendor)-\(model)-\(serial)"
    }
}
