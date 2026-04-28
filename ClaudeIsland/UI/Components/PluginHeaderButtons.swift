//
//  PluginHeaderButtons.swift
//  ClaudeIsland
//
//  Native SwiftUI buttons for loaded plugins in the instances header.
//  Each plugin gets an icon button based on its `icon` property.
//  Hover: fluorescent pink, scale up, hand cursor.
//

import SwiftUI

struct PluginHeaderButtons: View {
    let viewModel: NotchViewModel
    @ObservedObject private var manager = NativePluginManager.shared
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    /// Plugins shown directly in the header strip — those the user has
    /// pinned via the Dock window. Order matches `manager.pinnedIds`.
    /// Stale ids (plugin uninstalled but still in pinnedIds) are skipped
    /// silently; the slot remains in the Dock UI for re-pinning.
    private var pinnedHeaderPlugins: [NativePluginManager.LoadedPlugin] {
        manager.pinnedIds.compactMap { id in
            manager.loadedPlugins.first(where: { $0.id == id })
        }
    }

    /// True when there's at least one plugin loaded — the Dock is always
    /// reachable so users can pin/unpin/manage even when the strip is full.
    private var hasDockable: Bool { !manager.loadedPlugins.isEmpty }

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        // Pinned header icons (max 4). Reordering is done in the Dock
        // popover — a previous attempt at drag-to-reorder directly in the
        // header strip was removed because SwiftUI macOS drag inside the
        // notch panel's gesture chain was unreliable. The Dock UI's slots
        // and list rows already support drag for the same job.
        ForEach(pinnedHeaderPlugins) { plugin in
            PluginHeaderButton(plugin: plugin, viewModel: viewModel)
        }

        // "..." button — opens the Dock as an independent NSPanel window.
        //
        // Was previously a SwiftUI `.popover` attached to this button.
        // Three close-paths in the notch panel kept yanking the popover:
        // mouse-leave timer, outside-click handler that posts a synthetic
        // CGEvent into the popover, and hover region transitions. The
        // standalone window pattern sidesteps all three by living in its
        // own NSPanel with its own dismissal rules.
        if hasDockable {
            HeaderIconButton(icon: "ellipsis", hoverColor: Color.pluginAccent) {
                PluginDockWindow.shared.show(viewModel: viewModel)
            }
        }
    }
}

private struct PluginHeaderButton: View {
    let plugin: NativePluginManager.LoadedPlugin
    let viewModel: NotchViewModel
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        HeaderIconButton(icon: plugin.icon, hoverColor: Color.pluginAccent) {
            viewModel.showPlugin(plugin.id)
        }
    }
}

/// Reusable header icon button with hover effects.
/// Used for both plugin buttons and the settings gear.
struct HeaderIconButton: View {
    let icon: String
    var hoverColor: Color? = nil
    let action: () -> Void
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var isHovered = false

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isHovered ? (hoverColor ?? theme.workingColor) : theme.secondaryText.opacity(0.7))
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
