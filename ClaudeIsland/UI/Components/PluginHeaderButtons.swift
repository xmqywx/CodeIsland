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
    @State private var showOverflow = false

    private let maxVisible = 4

    private var visiblePlugins: [NativePluginManager.LoadedPlugin] {
        Array(manager.loadedPlugins.prefix(maxVisible))
    }

    private var overflowPlugins: [NativePluginManager.LoadedPlugin] {
        Array(manager.loadedPlugins.dropFirst(maxVisible))
    }

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        // Visible icons
        ForEach(visiblePlugins) { plugin in
            PluginHeaderButton(plugin: plugin, viewModel: viewModel)
        }

        // Overflow "..." button when >4 plugins
        if !overflowPlugins.isEmpty {
            HeaderIconButton(icon: "ellipsis", hoverColor: theme.workingColor) {
                showOverflow.toggle()
            }
            .popover(isPresented: $showOverflow, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                VStack(spacing: 2) {
                    ForEach(overflowPlugins) { plugin in
                        PluginOverflowRow(plugin: plugin) {
                            showOverflow = false
                            viewModel.showPlugin(plugin.id)
                        }
                    }
                }
                .padding(6)
                .frame(minWidth: 180)
                .background(theme.overlay)
            }
        }
    }
}

/// One row in the overflow popover. Whole row (icon + name + trailing
/// space) is the clickable hit target.
///
/// macOS popover contents have aggressive hit-shape clipping — neither
/// a plain `Button` nor a bare `onTapGesture` on a styled HStack
/// reliably extend the hit area to the trailing whitespace. The
/// pattern that does work: a ZStack that explicitly puts a hit-eating
/// `Color.clear.contentShape(Rectangle())` underneath the visible
/// content, with `onTapGesture` on the bottom layer. The Color.clear
/// rectangle takes the full frame and absorbs every tap regardless of
/// what label sits on top.
private struct PluginOverflowRow: View {
    let plugin: NativePluginManager.LoadedPlugin
    let action: () -> Void
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    @State private var isHovered = false

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        ZStack {
            // Visible background tint on hover
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? theme.needsYouColor.opacity(0.18) : Color.clear)

            // Row content
            HStack(spacing: 10) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 12))
                    .frame(width: 18, alignment: .center)
                Text(plugin.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(theme.primaryText.opacity(isHovered ? 1.0 : 0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)  // let taps fall through to the ZStack below
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { action() }
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

private struct PluginHeaderButton: View {
    let plugin: NativePluginManager.LoadedPlugin
    let viewModel: NotchViewModel
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        HeaderIconButton(icon: plugin.icon, hoverColor: theme.needsYouColor) {
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
