//
//  PluginStoreView.swift
//  ClaudeIsland
//
//  Plugin Store tab in System Settings. Shows installed themes,
//  buddies, and sounds with apply/uninstall actions.
//

import SwiftUI

struct PluginStoreView: View {
    @ObservedObject private var pluginManager = PluginManager.shared
    @ObservedObject private var themeRegistry = ThemeRegistry.shared
    @ObservedObject private var buddyRegistry = BuddyRegistry.shared
    @ObservedObject private var store = NotchCustomizationStore.shared

    @State private var selectedCategory = 0

    private let categories = ["Themes", "Buddies", "Sounds"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $selectedCategory) {
                ForEach(0..<categories.count, id: \.self) { i in
                    Text(categories[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            switch selectedCategory {
            case 0: themesSection
            case 1: buddiesSection
            case 2: soundsSection
            default: EmptyView()
            }

            Spacer()

            pluginDirHint
        }
        .padding(20)
    }

    // MARK: - Themes

    private var themesSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
            ForEach(themeRegistry.themes) { theme in
                themeCard(theme)
            }
        }
    }

    private func themeCard(_ theme: ThemeDefinition) -> some View {
        let isActive = store.customization.theme == theme.id
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.palette.bg)
                .frame(height: 60)
                .overlay(
                    Text("Aa")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(theme.palette.fg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? Color.green : Color.white.opacity(0.1), lineWidth: isActive ? 2 : 0.5)
                )

            Text(theme.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 4) {
                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button("Apply") {
                        store.update { $0.theme = theme.id }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                }

                if !theme.isBuiltIn {
                    Button {
                        pluginManager.uninstall(type: "themes", id: theme.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Buddies

    private var buddiesSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
            ForEach(buddyRegistry.buddies) { buddy in
                buddyCard(buddy)
            }
        }
    }

    private func buddyCard(_ buddy: BuddyDefinition) -> some View {
        let isActive = store.customization.buddyId == buddy.id
        return VStack(spacing: 6) {
            Group {
                if buddy.isBuiltIn {
                    PixelCharacterView(state: .idle)
                } else {
                    PluginBuddyView(definition: buddy, state: .idle)
                }
            }
            .frame(width: 52, height: 44)
            .scaleEffect(0.9)

            Text(buddy.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 4) {
                if isActive {
                    Text("Active")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button("Apply") {
                        store.update { $0.buddyId = buddy.id }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                }

                if !buddy.isBuiltIn {
                    Button {
                        pluginManager.uninstall(type: "buddies", id: buddy.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Sounds

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let soundPlugins = pluginManager.installedPlugins.filter { $0.type == .sound }
            if soundPlugins.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No sound plugins installed")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(soundPlugins) { plugin in
                    soundRow(plugin)
                }
            }
        }
    }

    private func soundRow(_ plugin: PluginManifest) -> some View {
        HStack {
            Image(systemName: "music.note")
                .foregroundColor(.white.opacity(0.6))
            Text(plugin.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Button {
                pluginManager.uninstall(type: "sounds", id: plugin.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Hint

    private var pluginDirHint: some View {
        Text("Install plugins to ~/.config/codeisland/plugins/")
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.3))
    }
}
