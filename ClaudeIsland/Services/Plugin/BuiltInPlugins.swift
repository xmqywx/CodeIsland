//
//  BuiltInPlugins.swift
//  ClaudeIsland
//
//  Built-in "official" plugins that ship with the app. Users can
//  disable them (which hides them from the header) but the slot
//  stays visible in System Settings > Plugins so they can be
//  reinstalled with one click.
//

import AppKit
import SwiftUI

// MARK: - Pair iPhone Plugin

/// Shell plugin that opens QRPairingWindow when tapped.
final class PairPhonePlugin: NSObject, MioPlugin {
    var id: String { "pair-phone" }
    var name: String { "Pair iPhone" }
    var icon: String { "iphone" }
    var version: String { "1.0.0" }

    func activate() {}
    func deactivate() {}

    func makeView() -> NSView {
        NSHostingView(rootView: PairPhonePluginView())
    }

    /// Matches the music plugin's panel width (440pt) so the expanded area is
    /// consistent across built-ins and externals. Height trims the ~300pt of
    /// empty space the default 780 left below the QR + pills stack.
    @objc func preferredPanelSize() -> NSValue {
        NSValue(size: NSSize(width: 440, height: 480))
    }
}

/// Inline pairing panel — no popup. Server config is shown prominently
/// when unset so users don't silently skip it (issue #57).
private struct PairPhonePluginView: View {
    var body: some View {
        PairPhonePanelView()
    }
}

// MARK: - Official Plugin Registry

/// Metadata for official plugins that ship with the app.
/// These always appear in the Plugins settings page, even when
/// disabled, so users can re-enable them with one click.
///
/// Two kinds of officials:
///   - Swift built-ins: factory creates the instance directly (e.g. Pair iPhone)
///   - Bundle-based: factory is nil; the plugin is shipped as a .bundle loaded
///     from disk. When disabled the slot stays; reinstall reloads from disk.
struct OfficialPluginInfo {
    let id: String
    let name: String
    let icon: String
    let version: String
    let factory: (() -> MioPlugin)?
}

enum OfficialPlugins {
    static let all: [OfficialPluginInfo] = [
        OfficialPluginInfo(
            id: "pair-phone",
            name: "Pair iPhone",
            icon: "iphone",
            version: "1.0.0",
            factory: { PairPhonePlugin() }
        ),
        // Stats is shipped as a .bundle plugin (source in mio-plugin-stats).
        // It lives in ~/.config/codeisland/plugins/stats.bundle after install.
        OfficialPluginInfo(
            id: "stats",
            name: "Stats",
            icon: "chart.bar.fill",
            version: "1.0.0",
            factory: nil
        ),
    ]

    static let ids: Set<String> = Set(all.map { $0.id })

    static func info(id: String) -> OfficialPluginInfo? {
        all.first { $0.id == id }
    }
}
