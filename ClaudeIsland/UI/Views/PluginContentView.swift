//
//  PluginContentView.swift
//  ClaudeIsland
//
//  Wraps a native plugin's NSView for display in the notch panel.
//  Includes a back button to return to instances view.
//

import SwiftUI

struct PluginContentView: View {
    let pluginId: String
    let viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    viewModel.exitChat()  // reuses exitChat to go back to instances
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                        Text(pluginName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Plugin view
            if let plugin = NativePluginManager.shared.plugin(for: pluginId) {
                PluginNSViewWrapper(plugin: plugin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Plugin not found")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 20)
    }

    private var pluginName: String {
        NativePluginManager.shared.plugin(for: pluginId)?.name ?? pluginId
    }
}

/// Bridges a plugin's NSView into SwiftUI via NSViewRepresentable.
struct PluginNSViewWrapper: NSViewRepresentable {
    let plugin: NativePluginManager.LoadedPlugin

    func makeNSView(context: Context) -> NSView {
        plugin.makeView() ?? NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
