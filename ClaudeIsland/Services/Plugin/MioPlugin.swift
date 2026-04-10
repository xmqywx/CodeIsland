//
//  MioPlugin.swift
//  ClaudeIsland
//
//  Native plugin protocol. Plugins are compiled .bundle files
//  that implement this protocol. Full access to app internals —
//  no sandbox, no restrictions. All plugins are reviewed before
//  distribution.
//

import AppKit

/// Protocol that all native MioIsland plugins must implement.
/// The principal class of the .bundle must conform to this protocol.
@objc protocol MioPlugin: AnyObject {
    /// Unique plugin identifier (kebab-case)
    var id: String { get }
    /// Display name
    var name: String { get }
    /// SF Symbol name for the plugin icon
    var icon: String { get }
    /// Plugin version (semver)
    var version: String { get }

    /// Called when the plugin is loaded. Use this to set up state,
    /// register observers, etc.
    func activate()

    /// Called when the plugin is unloaded or the app quits.
    func deactivate()

    /// Return the plugin's main NSView (full plugin page).
    /// Displayed when user navigates to this plugin from the menu.
    /// Use NSHostingView to wrap SwiftUI views.
    func makeView() -> NSView

    /// Return a view for a specific UI slot. Return nil to skip a slot.
    ///
    /// Available slots:
    ///   - "header"      → Top-right icon area of instances view (small button, ~24x24)
    ///   - "footer"      → Bottom of the notch panel (full width, e.g. mini player bar)
    ///   - "overlay"     → Center overlay on instances view (e.g. notification popup)
    ///   - "sessionItem" → Injected into each session row (extra badge/label)
    ///
    /// The `context` dict may contain:
    ///   - "sessionId": String  (for "sessionItem" slot)
    ///
    /// Example: a music plugin returns a 🎵 button for "header" and a mini
    /// player bar for "footer". A monitoring plugin returns a CPU badge for
    /// "sessionItem".
    @objc optional func viewForSlot(_ slot: String, context: [String: Any]) -> NSView?
}
