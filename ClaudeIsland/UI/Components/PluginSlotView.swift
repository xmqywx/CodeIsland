//
//  PluginSlotView.swift
//  ClaudeIsland
//
//  Generic SwiftUI view that renders plugin views for a given slot.
//  Used by the main app to inject plugin UI at predefined positions
//  without knowing anything about specific plugins.
//
//  Slots:
//    "header"      — top-right icon area (small, ~24x24)
//    "footer"      — bottom of notch panel (full width)
//    "overlay"     — center overlay on instances
//    "sessionItem" — per session row badge
//

import SwiftUI

/// Renders all plugin views for a given slot in a horizontal stack.
struct PluginSlotView: View {
    let slot: String
    var context: [String: Any] = [:]

    @ObservedObject private var manager = NativePluginManager.shared

    var body: some View {
        ForEach(manager.loadedPlugins) { plugin in
            if let nsView = plugin.viewForSlot(slot, context: context) {
                PluginSlotNSViewWrapper(nsView: nsView)
            }
        }
    }
}

/// Bridges a plugin's slot NSView into SwiftUI.
private struct PluginSlotNSViewWrapper: NSViewRepresentable {
    let nsView: NSView

    func makeNSView(context: Context) -> NSView { nsView }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
